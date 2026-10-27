import SwiftUI

/// The controller page fills the screen. While the TV hasn't been found, or this phone isn't paired yet, a plain screen
/// from the app itself covers it with the one thing to do.
struct RootView: View {
    @EnvironmentObject var link: PlayLink
    @Environment(\.scenePhase) private var phase

    private let night = Color(red: 0.043, green: 0.051, blue: 0.157)

    var body: some View {
        ZStack {
            night.ignoresSafeArea()
            PlayWebView(link: link).ignoresSafeArea()
            if link.link != .ready {
                ConnectView().transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: link.link)
        .persistentSystemOverlays(.hidden)
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true      // a game in progress must not dim the controller
            link.start()
        }
        .onChange(of: phase) { p in
            if p == .active { link.start() } else if p == .background { link.stop() }
        }
    }
}

/// Looking for the TV, or pairing with it.
struct ConnectView: View {
    @EnvironmentObject var link: PlayLink
    @State private var code = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.17, green: 0.11, blue: 0.48), Color(red: 0.05, green: 0.04, blue: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: "gamecontroller.fill").font(.system(size: 54)).foregroundColor(.white)
                    Text("WinkBox Play").font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundColor(.white)
                    content
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 28)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch link.link {
        case .needsPairing:
            pairing
        case .offline:
            message("Can\u{2019}t reach the TV", "Is it on, and on the same Wi-Fi as this phone?")
            pill("Try again") { link.retryNow() }
        default:
            ProgressView().tint(.white).scaleEffect(1.3).padding(.top, 6)
            message("Looking for your TV\u{2026}", "The TV needs to be on and on the same Wi-Fi.")
            pill("Try again") { link.retryNow() }
        }
    }

    @ViewBuilder private var pairing: some View {
        switch link.pairing {
        case .none, .requesting:
            message("Connect to your TV", "Tap the button. The TV will show 6 numbers.")
            if let e = link.pairingError { error(e) }
            pill(link.pairing == .requesting ? "Asking the TV\u{2026}" : "Show the code on the TV") { link.beginPairing() }
        case .enterCode, .verifying:
            message("Type the 6 numbers from the TV", "")
            TextField("000000", text: $code)
                .keyboardType(.numberPad)
                .focused($focused)
                .multilineTextAlignment(.center)
                .font(.system(size: 36, weight: .heavy, design: .monospaced))
                .foregroundColor(.white)
                .padding(14)
                .background(Color.white.opacity(0.15))
                .cornerRadius(16)
                .onChange(of: code) { v in
                    let digits = String(v.filter { $0.isNumber }.prefix(6))
                    if digits != v { code = digits }
                    if digits.count == 6 { focused = false; link.finishPairing(code: digits) }
                }
                .onAppear { focused = true }
            if let e = link.pairingError { error(e) }
            if link.pairing == .verifying { ProgressView().tint(.white) }
            pill("Start again", filled: false) { code = ""; link.cancelPairing() }
        }
    }

    private func message(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.system(size: 21, weight: .bold, design: .rounded)).foregroundColor(.white).multilineTextAlignment(.center)
            if !detail.isEmpty { Text(detail).font(.system(size: 16, weight: .medium)).foregroundColor(Color.white.opacity(0.75)).multilineTextAlignment(.center) }
        }
    }

    private func error(_ text: String) -> some View {
        Text(text).font(.system(size: 15, weight: .semibold)).foregroundColor(Color(red: 1, green: 0.72, blue: 0.3)).multilineTextAlignment(.center)
    }

    private func pill(_ title: String, filled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(filled ? Color(red: 0.06, green: 0.08, blue: 0.22) : .white)
                .padding(.horizontal, 26).padding(.vertical, 14)
                .background(filled ? Color(red: 1, green: 0.82, blue: 0.4) : Color.white.opacity(0.15))
                .clipShape(Capsule())
        }
    }
}
