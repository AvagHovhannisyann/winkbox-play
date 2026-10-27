import SwiftUI

@main
struct WinkPlayApp: App {
    @StateObject private var link = PlayLink()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(link)
        }
    }
}
