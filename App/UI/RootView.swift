import SwiftUI

/// The controller page fills the screen. Until it has loaded from the TV, or while this phone isn't paired, the app's own
/// screen covers it with the one thing to do. Once the page is up, it shows short drops of the connection itself.
struct RootView: View {
    @EnvironmentObject var link: PlayLink
    @Environment(\.scenePhase) private var phase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PlayWebView(link: link)
                .ignoresSafeArea()
                .opacity(link.pageReady ? 1 : 0)
            if showCover {
                ConnectView().transition(.opacity.combined(with: .scale(scale: 1.02)))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: showCover)
        .persistentSystemOverlays(.hidden)
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
        .onAppear {
            #if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = true      // a game in progress must not dim the controller
            #endif
            link.start()
        }
        .onChange(of: phase) { p in
            if p == .active { link.start() } else if p == .background { link.stop() }
        }
    }

    private var showCover: Bool {
        link.link == .needsPairing || !link.pageReady
    }
}
