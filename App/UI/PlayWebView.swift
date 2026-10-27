import SwiftUI
import WebKit

/// Shows the controller page the TV serves, and carries messages between it and the TV connection. The page draws the shelf of
/// games and whatever controls the running game asks for; this view lets it send input, buzz the phone and switch tilt on.
struct PlayWebView: UIViewRepresentable {
    @ObservedObject var link: PlayLink

    func makeCoordinator() -> Coordinator { Coordinator(link) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.userContentController.add(WeakHandler(context.coordinator), name: "wb")
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.backgroundColor = web.backgroundColor
        web.scrollView.isScrollEnabled = false        // the page scrolls its own shelf; the page itself never moves
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.navigationDelegate = context.coordinator
        context.coordinator.web = web
        link.onTV = { [weak c = context.coordinator] m in c?.deliver(m) }
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.update()
    }

    /// The web view keeps a strong reference to its message handlers; this keeps that from holding the coordinator alive forever.
    @MainActor
    final class WeakHandler: NSObject, WKScriptMessageHandler {
        weak var target: Coordinator?
        init(_ t: Coordinator) { target = t }
        func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
            target?.received(message.body)
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let link: PlayLink
        weak var web: WKWebView?
        private var loadedHost = ""
        private var reloadWork: DispatchWorkItem?
        private let tilt = Tilt()

        init(_ link: PlayLink) {
            self.link = link
        }

        /// Loads the page once the TV is reachable and tells it how the connection is doing.
        func update() {
            guard let web else { return }
            if link.link == .ready, !link.host.isEmpty, loadedHost != link.host {
                loadedHost = link.host
                let l = link
                Task { @MainActor in l.pageReady = false }               // not during the view update itself
                if let url = URL(string: "http://\(link.host):\(PlayLink.webPort)/web/index.html") { web.load(URLRequest(url: url)) }
            }
            push("window.WBHost&&WBHost.link(\(js(linkName)),\(js(linkDetail)))")
        }

        private var linkName: String {
            switch link.link {
            case .ready: return "ready"
            case .offline: return "offline"
            default: return "connecting"
            }
        }

        private var linkDetail: String {
            if case .offline(let why) = link.link { return why }
            return ""
        }

        func deliver(_ message: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: message), let s = String(data: data, encoding: .utf8) else { return }
            push("window.WBHost&&WBHost.tv(\(s))")
        }

        private func push(_ script: String) {
            web?.evaluateJavaScript(script, completionHandler: nil)
        }

        private func js(_ s: String) -> String {
            guard let d = try? JSONSerialization.data(withJSONObject: [s]), let t = String(data: d, encoding: .utf8) else { return "\"\"" }
            return String(t.dropFirst().dropLast())
        }

        /// What the page asks of the phone: {op: send | haptic | tilt | forget | ready}.
        func received(_ body: Any) {
            guard let m = body as? [String: Any], let op = m["op"] as? String else { return }
            switch op {
            case "send":
                if let msg = m["m"] as? [String: Any] { link.sendInput(msg) }
            case "haptic":
                Haptics.play(m["style"] as? String ?? "light")
            case "tilt":
                tilt.set(m["on"] as? Bool ?? false, name: m["n"] as? String ?? "tilt", link: link)
            case "forget":
                link.forgetThisPhone()
            case "retry":
                link.retryNow()
            case "ready":
                link.pageReady = true
                update()
                link.replay()
            default:
                break
            }
        }

        // MARK: - navigation

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Only the TV's own page: nothing in it should send the phone anywhere else.
            let host = action.request.url?.host ?? ""
            decisionHandler(host.isEmpty || host == link.host ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { reloadSoon() }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { reloadSoon() }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { link.pageReady = false; reloadSoon() }

        private func reloadSoon() {
            reloadWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, let web = self.web, self.link.link == .ready else { return }
                    self.loadedHost = ""
                    self.update()
                    _ = web
                }
            }
            reloadWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
        }
    }
}
