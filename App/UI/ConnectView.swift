import SwiftUI

/// Looking for the TV, or pairing with it: the app's own screen, shown until the TV's controller page can take over.
/// Built like Apple's welcome screens: the app's icon and name, what it does, and one clear thing to do next.
struct ConnectView: View {
    @EnvironmentObject var link: PlayLink
    @State private var code = ""
    @State private var wrongTries = 0

    var body: some View {
        GeometryReader { g in
        ZStack {
            Backdrop()
            ScrollView {
                Group {
                    if g.size.width > g.size.height && g.size.height < 520 {          // an iPhone on its side
                        HStack(alignment: .center, spacing: 44) {
                            header.frame(maxWidth: 300)
                            VStack(spacing: 0) { content }.frame(maxWidth: 380)
                        }
                        .padding(.vertical, 24)
                    } else {
                        VStack(spacing: 0) {
                            header
                            VStack(spacing: 0) { content }.padding(.top, 34)
                        }
                        .frame(maxWidth: 420)
                        .padding(.vertical, 56)
                    }
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, minHeight: g.size.height)
            }
        }
        }
        .onChange(of: link.pairingError) { e in
            if e != nil { code = ""; withAnimation(.default) { wrongTries += 1 }; Haptics.play("error") }
        }
        .onChange(of: link.pairing) { p in
            if p == .none { code = "" }
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            AppGlyph().frame(width: 96, height: 96)
            Text("WinkBox Play")
                .font(.system(size: 34, weight: .bold))
                .padding(.top, 20)
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
        }
    }

    private var subtitle: String {
        switch link.link {
        case .needsPairing: return link.pairing == .enterCode || link.pairing == .verifying ? "Almost there." : "Games on the TV. Controls on your iPhone."
        case .offline: return "The TV isn\u{2019}t answering."
        default: return "Games on the TV. Controls on your iPhone."
        }
    }

    @ViewBuilder private var content: some View {
        switch link.link {
        case .needsPairing:
            pairing
        case .offline(let why):
            VStack(spacing: 14) {
                Label("Can\u{2019}t Reach the TV", systemImage: "wifi.exclamationmark")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text("Check that the TV is on and that this iPhone is on the same Wi-Fi." + (why.isEmpty ? "" : "\n(\(why))"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                PrimaryButton(title: "Try Again", systemImage: "arrow.clockwise") { Haptics.play("light"); link.retryNow() }
                    .padding(.top, 8)
            }
        default:
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Looking for your TV\u{2026}").font(.headline)
                }
                Text("Make sure the TV is on and on the same Wi-Fi as this iPhone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 22)
            .glassCard(radius: 26)
        }
    }

    @ViewBuilder private var pairing: some View {
        switch link.pairing {
        case .none, .requesting:
            VStack(alignment: .leading, spacing: 20) {
                Feature(symbol: "gamecontroller.fill", tint: .indigo, title: "Your iPhone is the controller", detail: "Buttons, sticks and tilting, made for each game.")
                Feature(symbol: "tv.fill", tint: .blue, title: "Games play on the TV", detail: "Choose one here, or with the TV\u{2019}s remote.")
                Feature(symbol: "person.2.fill", tint: .green, title: "Play together", detail: "Brothers, sisters and friends join from their own phones.")
            }
            .padding(.bottom, 30)
            if let e = link.pairingError {
                Text(e).font(.subheadline).foregroundStyle(.red).multilineTextAlignment(.center).padding(.bottom, 12)
            }
            PrimaryButton(title: link.pairing == .requesting ? "Asking the TV\u{2026}" : "Connect to TV", systemImage: "tv", busy: link.pairing == .requesting) {
                Haptics.play("medium")
                link.beginPairing()
            }
            Text("The TV will show a 6-digit code.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 12)
        case .enterCode, .verifying:
            VStack(spacing: 16) {
                Text("Enter the Code").font(.title2.bold())
                Text("Type the 6 numbers shown on the TV.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                CodeField(code: $code, disabled: link.pairing == .verifying) { digits in
                    Haptics.play("light")
                    link.pairingError = nil                                    // so the same answer twice still shakes
                    link.finishPairing(code: digits)
                }
                .modifier(Shake(amount: CGFloat(wrongTries)))
                .padding(.top, 6)
                Group {
                    if link.pairing == .verifying {
                        HStack(spacing: 8) { ProgressView(); Text("Checking\u{2026}").foregroundStyle(.secondary) }
                    } else if let e = link.pairingError {
                        Text(e).foregroundStyle(.red).multilineTextAlignment(.center)
                    } else {
                        Text(" ")
                    }
                }
                .font(.subheadline)
                .frame(minHeight: 22)
                Button("Cancel") {
                    code = ""
                    link.cancelPairing()
                }
                .font(.body.weight(.medium))
                .padding(.top, 2)
            }
        }
    }
}

// MARK: - Pieces

/// The app's icon, drawn in the view: the same gradient and controller as the home screen icon.
struct AppGlyph: View {
    var body: some View {
        GeometryReader { g in
            let s = g.size.width
            ZStack {
                RoundedRectangle(cornerRadius: s * 0.225, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.49, green: 0.30, blue: 1.0), Color(red: 0.69, green: 0.30, blue: 0.94), Color(red: 1.0, green: 0.44, blue: 0.38)],
                                         startPoint: .bottomLeading, endPoint: .topTrailing))
                RoundedRectangle(cornerRadius: s * 0.225, style: .continuous)
                    .fill(RadialGradient(colors: [.white.opacity(0.35), .clear], center: .topLeading, startRadius: 0, endRadius: s * 0.9))
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: s * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: s * 0.04, y: s * 0.03)
                RoundedRectangle(cornerRadius: s * 0.225, style: .continuous)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 1)
            }
            .shadow(color: Color(red: 0.4, green: 0.2, blue: 0.9).opacity(0.45), radius: s * 0.18, y: s * 0.08)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// A row of Apple's welcome screens: a coloured symbol, a short title and one line under it.
struct Feature: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The big button at the bottom of a welcome screen.
struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var busy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(.white) } else if let s = systemImage { Image(systemName: s) }
                Text(title)
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 34)
        }
        .prominentStyle()
        .disabled(busy)
    }
}

/// Six boxes for the code, like the iPhone's own verification codes. One hidden text field takes the typing (and the
/// number pad); the boxes only show it.
struct CodeField: View {
    @Binding var code: String
    var disabled = false
    let done: (String) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .focused($focused)
                #if os(iOS)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                #endif
                .disabled(disabled)
                .opacity(0.02)
                .frame(width: 1, height: 1)
                .onChange(of: code) { v in
                    let digits = String(v.filter(\.isNumber).prefix(6))
                    if digits != v { code = digits }
                    if digits.count == 6 { done(digits) }
                }
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { i in
                    box(i)
                    if i == 2 { Capsule().fill(.secondary).frame(width: 10, height: 3).padding(.horizontal, 2) }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
        }
        .task {
            try? await Task.sleep(nanoseconds: 350_000_000)                 // after the screen has slid in
            focused = true
        }
    }

    private func box(_ i: Int) -> some View {
        let chars = Array(code)
        let active = focused && i == min(chars.count, 5) && !disabled
        return ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(active ? 0.16 : 0.09))
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(active ? Color.accentColor : Color.white.opacity(0.12), lineWidth: active ? 2 : 1)
            Text(i < chars.count ? String(chars[i]) : "")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(width: 46, height: 58)
        .animation(.easeOut(duration: 0.15), value: code)
    }
}

/// A sideways shake, as the iPhone does for a wrong passcode.
struct Shake: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(amount * .pi * 4), y: 0))
    }
}

/// Black, with soft colour drifting behind, like Apple Arcade's welcome.
struct Backdrop: View {
    @State private var drift = false

    var body: some View {
        ZStack {
            Color.black
            glow(Color(red: 0.36, green: 0.25, blue: 0.95), 0.6).frame(width: 760, height: 760)
                .offset(x: drift ? -90 : -150, y: drift ? -260 : -200)
            glow(Color(red: 1.0, green: 0.42, blue: 0.4), 0.38).frame(width: 640, height: 640)
                .offset(x: drift ? 150 : 90, y: drift ? 280 : 340)
        }
        .ignoresSafeArea()
        .onAppear { withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) { drift = true } }
    }

    /// A soft light: a radial gradient rather than a blurred shape, so it costs nothing to draw.
    private func glow(_ c: Color, _ strength: Double) -> some View {
        Circle().fill(RadialGradient(colors: [c.opacity(strength), c.opacity(strength * 0.35), .clear], center: .center, startRadius: 0, endRadius: 380))
    }
}

extension View {
    /// Liquid Glass on iOS 26, Apple's thin material before it.
    @ViewBuilder func glassCard(radius: CGFloat) -> some View {
        #if compiler(>=6.2) && os(iOS)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        #else
        self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        #endif
    }

    /// The prominent glass button on iOS 26, the filled capsule before it.
    @ViewBuilder func prominentStyle() -> some View {
        #if compiler(>=6.2) && os(iOS)
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent).controlSize(.large)
        } else {
            self.buttonStyle(.borderedProminent).controlSize(.large).buttonBorderShape(.capsule)
        }
        #else
        self.buttonStyle(.borderedProminent).controlSize(.large)
        #endif
    }
}
