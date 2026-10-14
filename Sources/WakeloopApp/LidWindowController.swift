import AppKit

/// What the lid-closed window needs from the app. AppDelegate keeps the state and runs the setup and removal flows.
protocol LidHost: AnyObject {
    var lidSetUp: Bool { get }
    var lidEnabled: Bool { get }
    var lidOnBattery: Bool { get }
    func setupLid()
    func removeLidSetup()
    func toggleLid()
    func toggleLidOnBattery()
}

/// Window for Settings > Lid-closed mode. It re-reads the app state each time it is shown or changed.
final class LidWindowController: NSObject {
    private unowned let host: LidHost
    private let window: NSWindow
    private let root = NSStackView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let setUpButton = NSButton(title: "Set up…", target: nil, action: nil)
    private let keepAwake = NSButton(checkboxWithTitle: "Keep awake with lid closed", target: nil, action: nil)
    private let chargerOnly = NSButton(radioButtonWithTitle: "Charger only (default)", target: nil, action: nil)
    private let withBattery = NSButton(radioButtonWithTitle: "Charger or battery (stops at 30%)", target: nil, action: nil)
    private let removeButton = NSButton(title: "Remove setup…", target: nil, action: nil)
    private var notSetUpRows: [NSView] = []
    private var setUpRows: [NSView] = []

    init(host: LidHost) {
        self.host = host
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 200),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()

        statusLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        let explain = NSTextField(wrappingLabelWithString: "Keeps your Mac awake with the lid closed while an agent is working.")
        explain.preferredMaxLayoutWidth = 340
        let powerLabel = NSTextField(labelWithString: "Power source")
        powerLabel.textColor = .secondaryLabelColor
        let power = NSStackView(views: [powerLabel, chargerOnly, withBattery])
        power.orientation = .vertical
        power.alignment = .leading
        power.spacing = 6
        power.edgeInsets = NSEdgeInsets(top: 0, left: 18, bottom: 0, right: 0)
        let caption = NSTextField(labelWithString: "Never put a working Mac in a closed bag.")
        caption.font = .systemFont(ofSize: 11)
        caption.textColor = .secondaryLabelColor

        for button in [setUpButton, keepAwake, chargerOnly, withBattery, removeButton] { button.target = self }
        setUpButton.action = #selector(setUp)
        keepAwake.action = #selector(toggleKeepAwake)
        chargerOnly.action = #selector(choosePower(_:))
        withBattery.action = #selector(choosePower(_:))
        removeButton.action = #selector(remove)

        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        for view in [statusLabel, explain, setUpButton, keepAwake, power, caption, removeButton] {
            root.addArrangedSubview(view)
        }
        notSetUpRows = [setUpButton]
        setUpRows = [keepAwake, power, caption, removeButton]

        window.title = "Lid-closed mode"
        window.isReleasedWhenClosed = false
        window.contentView = root
        window.center()
    }

    func show() {
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func refresh() {
        let setUp = host.lidSetUp
        let enabled = host.lidEnabled
        statusLabel.stringValue = setUp ? "Set up" : "Not set up"
        notSetUpRows.forEach { $0.isHidden = setUp }
        setUpRows.forEach { $0.isHidden = !setUp }
        keepAwake.state = enabled ? .on : .off
        chargerOnly.state = host.lidOnBattery ? .off : .on
        withBattery.state = host.lidOnBattery ? .on : .off
        chargerOnly.isEnabled = enabled
        withBattery.isEnabled = enabled
        window.setContentSize(NSSize(width: 380, height: root.fittingSize.height))
    }

    @objc private func setUp() {
        host.setupLid()
        refresh()
    }

    @objc private func remove() {
        host.removeLidSetup()
        refresh()
    }

    @objc private func toggleKeepAwake() {
        host.toggleLid()
        refresh()
    }

    @objc private func choosePower(_ sender: NSButton) {
        if (sender === withBattery) != host.lidOnBattery { host.toggleLidOnBattery() }
        refresh()
    }
}
