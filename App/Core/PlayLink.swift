import Foundation
import Network
#if os(iOS)
import UIKit
#endif

/// The phone's connection to the TV's game console: finds the TV on the home Wi-Fi (Bonjour), pairs once with the code the
/// TV shows, then keeps one secure WebSocket open. The controller page (shown in a web view) talks through it; this class
/// only carries its messages and remembers the latest game list, controller layout and player number, so a page that is
/// reloaded can be shown the same thing again.
@MainActor
final class PlayLink: ObservableObject {
    enum Link: Equatable {
        case searching, connecting, needsPairing, ready
        case offline(String)
    }

    enum PairingStep: Equatable { case none, requesting, enterCode, verifying }

    static let port = 8731
    static let webPort = 8732

    @Published var link: Link = .searching
    @Published var pairing: PairingStep = .none
    @Published var pairingError: String?
    @Published var host: String { didSet { defaults.set(host, forKey: "tv.host") } }

    /// Every message from the TV, for the controller page.
    var onTV: (([String: Any]) -> Void)?
    /// Off only for tests that must not open a connection by themselves.
    var autoConnect = true

    private let defaults = UserDefaults.standard
    private var task: URLSessionWebSocketTask?
    private var browser: NWBrowser?
    private var identity: PairedIdentity?
    private var connectionNonce = Data()
    private var challenge: (tvPub: Data, nonce: Data)?
    private var pendingPair: WBCrypto.Pairing?
    private var retryAfter: TimeInterval = 2
    private var retryWork: DispatchWorkItem?
    /// The newest message of each kind the page needs to redraw itself.
    private var latest: [String: [String: Any]] = [:]

    init() {
        host = defaults.string(forKey: "tv.host") ?? ""
        if let d = Keychain.load("identity"), let id = try? JSONDecoder().decode(PairedIdentity.self, from: d) { identity = id }
    }

    var isPaired: Bool { identity != nil }

    var canReach: Bool {
        switch link {
        case .needsPairing, .ready: return true
        default: return false
        }
    }

    // MARK: - Connection

    func start() {
        guard autoConnect, task == nil else { return }
        retryWork?.cancel()
        if !host.isEmpty { open(host) } else { link = .searching }
        discover()
    }

    /// The app is leaving the screen: say goodbye so the TV frees this controller, and close.
    func stop() {
        retryWork?.cancel()
        browser?.cancel()
        browser = nil
        if link == .ready { send(["t": "bye"]) }
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        link = .searching
    }

    func retryNow() {
        retryWork?.cancel()
        retryAfter = 2
        if task == nil {
            if !host.isEmpty { open(host) } else { link = .searching }
            discover()
        }
    }

    private func open(_ address: String) {
        guard task == nil, let url = URL(string: "ws://\(address):\(Self.port)/ws") else { return }
        link = .connecting
        let t = URLSession.shared.webSocketTask(with: url)
        task = t
        t.resume()
        receive(t)
    }

    private func receive(_ t: URLSessionWebSocketTask) {
        t.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.task === t else { return }
                switch result {
                case .success(let message):
                    if case .string(let s) = message { self.handle(s) }
                    self.receive(t)
                case .failure(let error):
                    self.dropped(error)
                }
            }
        }
    }

    private func dropped(_ error: Error) {
        task?.cancel()
        task = nil
        connectionNonce = Data()
        link = .offline(error.localizedDescription)
        scheduleRetry()
    }

    private func scheduleRetry() {
        retryWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.task == nil else { return }
                if !self.host.isEmpty { self.open(self.host) }
                self.discover()
            }
        }
        retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + retryAfter, execute: work)
        retryAfter = min(retryAfter * 1.6, 12)
    }

    private func discover() {
        guard browser == nil else { return }
        let b = NWBrowser(for: .bonjour(type: "_winkbox._tcp", domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in self?.found(results) }
        }
        b.start(queue: .main)
        browser = b
    }

    private func found(_ results: Set<NWBrowser.Result>) {
        guard let first = results.first else { return }
        resolve(first.endpoint) { [weak self] address in
            guard let self, let address else { return }
            if address != self.host { self.host = address }
            if self.task == nil { self.open(address) }
        }
    }

    /// Turns a Bonjour service into an IPv4 address by connecting to it once.
    private func resolve(_ endpoint: NWEndpoint, done: @escaping (String?) -> Void) {
        let params = NWParameters.tcp
        if let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
        let c = NWConnection(to: endpoint, using: params)
        c.stateUpdateHandler = { state in
            switch state {
            case .ready:
                var address: String?
                if case let .hostPort(h, _)? = c.currentPath?.remoteEndpoint, case let .ipv4(a) = h {
                    address = "\(a)".split(separator: "%").first.map(String.init)
                }
                c.cancel()
                DispatchQueue.main.async { done(address) }
            case .failed:
                c.cancel()
                DispatchQueue.main.async { done(nil) }
            default:
                break
            }
        }
        c.start(queue: .main)
    }

    /// Sends a message to the TV, once this phone has signed in.
    func send(_ object: [String: Any]) {
        guard let t = task, let data = try? JSONSerialization.data(withJSONObject: object),
              let s = String(data: data, encoding: .utf8) else { return }
        t.send(.string(s)) { _ in }
    }

    /// Sends a controller message ("in") only while connected and signed in; button and stick events are not worth queueing.
    func sendInput(_ object: [String: Any]) {
        guard link == .ready else { return }
        send(object)
    }

    // MARK: - Messages from the TV

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8), let m = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = m["t"] as? String else { return }
        switch type {
        case "hello":
            retryAfter = 2
            connectionNonce = Data(base64Encoded: m["nonce"] as? String ?? "") ?? Data()
            if let id = identity {
                send(["t": "auth", "deviceId": id.deviceId,
                      "mac": WBCrypto.hmac(id.secret, Data("auth".utf8), connectionNonce).base64EncodedString()])
            } else {
                link = .needsPairing
            }
        case "status":
            if link != .ready { link = .ready }
        case "auth_failed":
            // The TV no longer knows this phone (it was forgotten, or the TV was reset): pair again.
            Keychain.delete("identity")
            identity = nil
            link = .needsPairing
        case "pair_challenge":
            if let pub = Data(base64Encoded: m["tvPub"] as? String ?? ""), let nonce = Data(base64Encoded: m["nonce"] as? String ?? "") {
                challenge = (pub, nonce)
                pairing = .enterCode
                pairingError = nil
            }
        case "paired":
            if let p = pendingPair, let id = m["deviceId"] as? String, let proof = Data(base64Encoded: m["tvProof"] as? String ?? ""), p.tvProof(proof) {
                let ident = PairedIdentity(deviceId: id, secret: p.secret)
                if let d = try? JSONEncoder().encode(ident) { Keychain.save(d, for: "identity") }
                identity = ident
                pairing = .none
                pendingPair = nil
                // The pairing connection becomes the signed-in one: the TV treats a phone that has just paired as signed in.
                link = .ready
                Haptics.play("success")
            } else {
                pairingError = "The TV's answer didn't check out. Try again."
                pairing = .none
            }
        case "pair_failed":
            switch m["reason"] as? String ?? "" {
            case "wrong_code": pairingError = "That isn't the code on the TV. Check it and try again."; pairing = .enterCode
            case "expired": pairingError = "The code expired. Start again."; pairing = .none
            case "locked": pairingError = "Too many wrong codes. Wait a minute and try again."; pairing = .none
            default: pairingError = "Pairing didn't work. Try again."; pairing = .none
            }
        case "error":
            if (m["code"] as? String) == "auth" { link = .needsPairing }
            onTV?(m)
        case "games", "pad", "slot":
            latest[type] = m
            onTV?(m)
        default:
            onTV?(m)
        }
    }

    /// Shows the page again what it was last told (it was reloaded, or has just loaded).
    func replay() {
        for type in ["games", "slot", "pad"] { if let m = latest[type] { onTV?(m) } }
        if link == .ready { send(["t": "games"]) }
    }

    // MARK: - Pairing

    func beginPairing() {
        guard task != nil else { return }
        pairing = .requesting
        pairingError = nil
        send(["t": "pair_start"])
    }

    func finishPairing(code: String) {
        guard let c = challenge else { return }
        do {
            let p = try WBCrypto.pair(code: code, tvPub: c.tvPub, nonce: c.nonce)
            pendingPair = p
            pairing = .verifying
            #if os(iOS)
            let name = UIDevice.current.name
            #else
            let name = Host.current().localizedName ?? "Mac"
            #endif
            // `app: play` asks for the limited role: this phone may play games and nothing else.
            send(["t": "pair_finish", "app": "play", "device": name, "phonePub": p.phonePub.base64EncodedString(), "proof": p.proof.base64EncodedString()])
        } catch {
            pairingError = "That code couldn't be used. Start again."
            pairing = .none
        }
    }

    func cancelPairing() {
        pairing = .none
        pairingError = nil
    }

    func forgetThisPhone() {
        if let id = identity, link == .ready { send(["t": "forget", "deviceId": id.deviceId]) }
        Keychain.delete("identity")
        identity = nil
        latest = [:]
        link = task == nil ? .searching : .needsPairing
    }
}

/// Buzzes the phone for the controller page and for the TV (a game can ask for a buzz).
enum Haptics {
    #if os(iOS)
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let notify = UINotificationFeedbackGenerator()
    #endif

    static func play(_ style: String) {
        #if os(iOS)
        switch style {
        case "heavy": heavy.impactOccurred()
        case "medium": medium.impactOccurred()
        case "success": notify.notificationOccurred(.success)
        default: light.impactOccurred(intensity: 0.8)
        }
        #endif
    }
}
