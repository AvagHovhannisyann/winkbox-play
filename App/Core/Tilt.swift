import Foundation
#if os(iOS)
import CoreMotion

/// Turns the phone into a steering wheel and a joystick: tilting it sideways (like a wheel) or forwards and back steers a game.
/// The pose when it is switched on is "straight"; the controller page asks for it with a Tilt button.
@MainActor
final class Tilt {
    private let motion = CMMotionManager()
    private var zeroAngle: Double?
    private var zeroPitch: Double?
    private var lastSent = (x: 9.0, y: 9.0)

    var isOn: Bool { motion.isDeviceMotionActive }

    func set(_ on: Bool, name: String, link: PlayLink) {
        motion.stopDeviceMotionUpdates()
        zeroAngle = nil
        zeroPitch = nil
        if !on {
            link.sendInput(["t": "in", "k": "a", "n": name, "x": 0, "y": 0])
            return
        }
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self, weak link] data, _ in
            guard let self, let link, let g = data?.gravity else { return }
            // Steering: how far the phone is turned about the axis out of its screen, from where it was when switched on.
            let angle = atan2(g.y, g.x)
            let pitch = asin(max(-1, min(1, g.z)))
            if self.zeroAngle == nil { self.zeroAngle = angle; self.zeroPitch = pitch }
            var d = angle - (self.zeroAngle ?? angle)
            while d > .pi { d -= 2 * .pi }
            while d < -.pi { d += 2 * .pi }
            let x = max(-1, min(1, d / (35 * .pi / 180)))
            let y = max(-1, min(1, (pitch - (self.zeroPitch ?? pitch)) / (30 * .pi / 180)))
            let rx = (x * 100).rounded() / 100, ry = (y * 100).rounded() / 100
            if abs(rx - self.lastSent.x) < 0.01 && abs(ry - self.lastSent.y) < 0.01 { return }
            self.lastSent = (rx, ry)
            link.sendInput(["t": "in", "k": "a", "n": name, "x": rx, "y": ry])
        }
    }
}
#endif
