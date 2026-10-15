import AppKit

/// The menu bar icon: a calm ring when idle; while holding, a core beats and soft rings spread out from it.
enum StatusIcon {
    private static let size = NSSize(width: 18, height: 18)
    private static let center = CGPoint(x: 9, y: 9)
    private static let ringRadius: CGFloat = 6.5
    private static let stroke: CGFloat = 1.5
    /// Outer edge of a spreading ring stays 1.5 pt inside the canvas.
    private static let spreadRadius: CGFloat = 6.9

    static func image(holding: Bool, phase: CGFloat) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            if holding {
                ring(radius: ringRadius, width: stroke, alpha: 1)
                // Eases between the resting and peak core sizes once per cycle.
                dot(radius: 1.6 + 0.6 * (1 - cos(2 * .pi * phase)) / 2)
                for offset: CGFloat in [0, 0.5] {
                    let p = (phase + offset).truncatingRemainder(dividingBy: 1)
                    // Fades in from the core, so the resting icon shows no halo.
                    let fadeIn = min(1, p / 0.12)
                    ring(radius: 3 + (spreadRadius - 3) * p, width: 1.2, alpha: 0.9 * (1 - p) * fadeIn)
                }
            } else {
                ring(radius: ringRadius, width: stroke, alpha: 0.55)
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func ring(radius: CGFloat, width: CGFloat, alpha: CGFloat) {
        let path = NSBezierPath(ovalIn: circle(radius))
        path.lineWidth = width
        NSColor.black.withAlphaComponent(alpha).setStroke()
        path.stroke()
    }

    private static func dot(radius: CGFloat) {
        NSColor.black.setFill()
        NSBezierPath(ovalIn: circle(radius)).fill()
    }

    private static func circle(_ radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}
