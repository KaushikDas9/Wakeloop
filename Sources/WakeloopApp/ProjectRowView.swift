import AppKit

/// Project row with sub-agents in the status menu. A custom view means a click runs `onClick` and the menu stays open.
final class ProjectRowView: NSView {
    var onClick: (() -> Void)?
    var collapsed: Bool { didSet { updateText() } }
    private let title: String
    private let label = NSTextField(labelWithString: "")
    private var hovered = false {
        didSet {
            guard hovered != oldValue else { return }
            label.textColor = hovered ? .selectedMenuItemTextColor : .labelColor
            needsDisplay = true
        }
    }

    init(title: String, collapsed: Bool) {
        self.title = title
        self.collapsed = collapsed
        super.init(frame: NSRect(x: 0, y: 0, width: 220, height: 22))
        autoresizingMask = [.width]
        label.font = .menuFont(ofSize: 0)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        updateText()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func updateText() {
        label.stringValue = "\(collapsed ? "▸" : "▾") \(title)"
        label.sizeToFit()
        setFrameSize(NSSize(width: max(220, ceil(label.frame.width) + 28), height: 22))
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovered {
            NSColor.selectedContentBackgroundColor.setFill()
            bounds.fill()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }

    override func mouseExited(with event: NSEvent) { hovered = false }

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
}
