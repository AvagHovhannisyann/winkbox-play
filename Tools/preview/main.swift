// Renders the app's own screens on the Mac (SwiftUI for macOS) at iPhone size, to check the design without a device.
// usage: preview <outdir>     (built by Tools/preview/run.sh)
import AppKit
import SwiftUI

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
app.appearance = NSAppearance(named: .darkAqua)

func render<V: View>(_ view: V, _ name: String, landscape: Bool = false) {
    let size = landscape ? NSSize(width: 874, height: 402) : NSSize(width: 402, height: 874)
    let root = view.frame(width: size.width, height: size.height).environment(\.colorScheme, .dark)
    let host = NSHostingView(rootView: root)
    host.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .darkAqua)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.8))
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    host.cacheDisplay(in: host.bounds, to: rep)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
    print("\(outDir)/\(name).png")
}

@MainActor func link(_ l: PlayLink.Link, _ p: PlayLink.PairingStep = .none, error: String? = nil) -> PlayLink {
    let k = PlayLink()
    k.autoConnect = false
    k.link = l
    k.pairing = p
    k.pairingError = error
    return k
}

@MainActor func renderAll() {
    for land in [false, true] {
        let t = land ? "l" : "p"
        render(ConnectView().environmentObject(link(.searching)), "\(t)1-searching", landscape: land)
        render(ConnectView().environmentObject(link(.needsPairing)), "\(t)2-welcome", landscape: land)
        render(ConnectView().environmentObject(link(.needsPairing, .enterCode)), "\(t)3-code", landscape: land)
        render(ConnectView().environmentObject(link(.needsPairing, .enterCode, error: "That isn\u{2019}t the code on the TV. Check it and try again.")), "\(t)4-code-wrong", landscape: land)
        render(ConnectView().environmentObject(link(.offline("The request timed out."))), "\(t)5-offline", landscape: land)
    }
}

Task { @MainActor in
    renderAll()
    exit(0)
}
app.run()
