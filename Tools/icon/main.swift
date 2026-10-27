// Draws the app icon (1024 px): a friendly game controller on a violet-to-coral gradient. usage: icon <out.png>
import AppKit

let px = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let s = CGFloat(px)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
func gradient(_ stops: [(UInt32, CGFloat, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: stops.map { color($0.0, $0.1) } as CFArray, locations: stops.map { $0.2 })!
}

// Background.
ctx.drawLinearGradient(gradient([(0x7C4DFF, 1, 0), (0xB04CF0, 1, 0.5), (0xFF6F61, 1, 1)]),
                       start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])
ctx.drawRadialGradient(gradient([(0xFFFFFF, 0.28, 0), (0xFFFFFF, 0, 1)]),
                       startCenter: CGPoint(x: s * 0.25, y: s * 0.85), startRadius: 0,
                       endCenter: CGPoint(x: s * 0.25, y: s * 0.85), endRadius: s * 0.6, options: [])

func roundedRect(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// The controller: a wide body and two grips, drawn as one white shape with a soft shadow under it.
let body = CGMutablePath()
body.addPath(roundedRect(CGRect(x: s * 0.15, y: s * 0.40, width: s * 0.70, height: s * 0.30), s * 0.15))
var left = CGAffineTransform(translationX: s * 0.31, y: s * 0.33).rotated(by: .pi / 14)
body.addPath(roundedRect(CGRect(x: -s * 0.10, y: -s * 0.17, width: s * 0.20, height: s * 0.34), s * 0.10), transform: left)
var right = CGAffineTransform(translationX: s * 0.69, y: s * 0.33).rotated(by: -.pi / 14)
body.addPath(roundedRect(CGRect(x: -s * 0.10, y: -s * 0.17, width: s * 0.20, height: s * 0.34), s * 0.10), transform: right)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.03), blur: s * 0.06, color: color(0x2A0E6B, 0.55))
ctx.setFillColor(color(0xFFFFFF))
ctx.addPath(body)
ctx.fillPath()
ctx.restoreGState()

// D-pad on the left.
ctx.setFillColor(color(0x5B3DF5))
ctx.addPath(roundedRect(CGRect(x: s * 0.265, y: s * 0.475, width: s * 0.17, height: s * 0.055), s * 0.02))
ctx.addPath(roundedRect(CGRect(x: s * 0.3225, y: s * 0.4175, width: s * 0.055, height: s * 0.17), s * 0.02))
ctx.fillPath()

// Buttons on the right.
for (cx, cy, hex) in [(0.655, 0.445, 0xFF6F61), (0.735, 0.525, 0xFFC233)] as [(CGFloat, CGFloat, UInt32)] {
    ctx.setFillColor(color(hex))
    ctx.fillEllipse(in: CGRect(x: s * cx - s * 0.05, y: s * cy - s * 0.05, width: s * 0.10, height: s * 0.10))
}

// A little sparkle.
ctx.setFillColor(color(0xFFFFFF, 0.95))
let sp = CGPoint(x: s * 0.77, y: s * 0.82)
let spark = CGMutablePath()
spark.move(to: CGPoint(x: sp.x, y: sp.y + s * 0.07))
spark.addQuadCurve(to: CGPoint(x: sp.x + s * 0.07, y: sp.y), control: CGPoint(x: sp.x + s * 0.012, y: sp.y + s * 0.012))
spark.addQuadCurve(to: CGPoint(x: sp.x, y: sp.y - s * 0.07), control: CGPoint(x: sp.x + s * 0.012, y: sp.y - s * 0.012))
spark.addQuadCurve(to: CGPoint(x: sp.x - s * 0.07, y: sp.y), control: CGPoint(x: sp.x - s * 0.012, y: sp.y - s * 0.012))
spark.addQuadCurve(to: CGPoint(x: sp.x, y: sp.y + s * 0.07), control: CGPoint(x: sp.x - s * 0.012, y: sp.y + s * 0.012))
ctx.addPath(spark)
ctx.fillPath()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
