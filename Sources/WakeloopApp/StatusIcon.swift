import AppKit

/// The menu bar icon: a ring, with a dot that orbits it while Wakeloop holds the Mac awake.
enum StatusIcon {
    private static let size = NSSize(width: 18, height: 18)
    private static let center = CGPoint(x: 9, y: 9)
    private static let ringRadius: CGFloat = 6.5
    private static let stroke: CGFloat = 1.5

    /// Point on a circle at `phase` (fraction of a turn), clockwise from 12 o'clock.
    static func dotPosition(phase: CGFloat, center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = phase * 2 * .pi
        return CGPoint(x: center.x + radius * sin(angle), y: center.y + radius * cos(angle))
    }

    static func image(holding: Bool, phase: CGFloat) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setStroke()
            let ring = NSBezierPath(ovalIn: square(center, ringRadius))
            ring.lineWidth = stroke
            ring.stroke()

            if holding {
                dot(center, radius: 2.2, alpha: 1)
                // Tail trails the head: smaller and fainter the further behind it sits.
                for (lag, radius, alpha) in [(0.05, 1.4, 0.5), (0.10, 1.2, 0.3), (0.15, 1.0, 0.15)] as [(CGFloat, CGFloat, CGFloat)] {
                    dot(dotPosition(phase: phase - lag, center: center, radius: ringRadius), radius: radius, alpha: alpha)
                }
                dot(dotPosition(phase: phase, center: center, radius: ringRadius), radius: 1.8, alpha: 1)
            } else {
                dot(dotPosition(phase: 0, center: center, radius: ringRadius), radius: 1.6, alpha: 0.55)
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func dot(_ point: CGPoint, radius: CGFloat, alpha: CGFloat) {
        NSColor.black.withAlphaComponent(alpha).setFill()
        NSBezierPath(ovalIn: square(point, radius)).fill()
    }

    private static func square(_ point: CGPoint, _ radius: CGFloat) -> CGRect {
        CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
    }
}
