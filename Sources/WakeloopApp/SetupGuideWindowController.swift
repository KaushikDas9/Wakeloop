import AppKit
import WakeloopCore

/// What the setup guide needs from the app. AppDelegate keeps the state and runs the setup flows.
protocol SetupGuideHost: AnyObject {
    var lidSetUp: Bool { get }
    var hookServerListening: Bool { get }
    var claudeConnected: Bool { get }
    func readClaudeHooks() -> Result<HookInstaller.Status, Error>
    @discardableResult func setupClaudeHooks() -> Bool
    func openLidWindow()
}

/// Setup guide: shown once on first launch and reopened from Settings. Re-reads the status every two seconds while open.
final class SetupGuideWindowController: NSObject, NSWindowDelegate {
    private unowned let host: SetupGuideHost
    private let window: NSWindow
    private let hooksIcon = NSImageView()
    private let hooksStatus = NSTextField(labelWithString: "")
    private let hooksButton = NSButton(title: "Set up…", target: nil, action: nil)
    private let lidIcon = NSImageView()
    private let lidStatus = NSTextField(labelWithString: "")
    private let serverIcon = NSImageView()
    private let serverStatus = NSTextField(labelWithString: "")
    private let connectedIcon = NSImageView()
    private let connectedStatus = NSTextField(labelWithString: "")
    private var timer: Timer?

    init(host: SetupGuideHost) {
        self.host = host
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 400),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()

        let heading = NSTextField(labelWithString: "Set up Wakeloop")
        heading.font = .boldSystemFont(ofSize: 18)
        let intro = wrapping("Three steps. The status updates as you go.", size: 12, color: .secondaryLabelColor)

        hooksButton.target = self
        hooksButton.action = #selector(setUpHooks)
        let lidButton = NSButton(title: "Open lid-closed setup…", target: self, action: #selector(openLid))
        let done = NSButton(title: "Done", target: self, action: #selector(closeGuide))
        done.keyEquivalent = "\r"

        let step1 = step(1, title: "Claude Code hooks",
                         body: "Lets Wakeloop see when Claude Code starts, works and stops. Adds its entries to ~/.claude/settings.json and keeps your other hooks.",
                         rows: [statusRow(hooksIcon, hooksStatus), row([hooksButton])])
        let step2 = step(2, title: "Lid-closed mode (optional)",
                         body: "Keeps your Mac awake with the lid closed. Needs your administrator password once. Skip this if you never close the lid while an agent works.",
                         rows: [statusRow(lidIcon, lidStatus), row([lidButton])])
        let step3 = step(3, title: "Check",
                         body: "Confirms that Claude Code can reach Wakeloop.",
                         rows: [
                            statusRow(serverIcon, serverStatus),
                            statusRow(connectedIcon, connectedStatus),
                            wrapping("Send a prompt in Claude Code to test it.", size: 11, color: .secondaryLabelColor),
                         ])

        let root = NSStackView(views: [heading, intro, step1, step2, step3, row([done])])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 16
        root.edgeInsets = NSEdgeInsets(top: 20, left: 22, bottom: 20, right: 22)
        root.setCustomSpacing(4, after: heading)

        window.title = "Wakeloop setup"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = root
        window.center()
    }

    func show() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        switch host.readClaudeHooks() {
        case .success(.installed):
            mark(hooksIcon, hooksStatus, done: true, text: "Installed")
            hooksButton.isHidden = true
        case .success(.partial(let installed, let total)):
            mark(hooksIcon, hooksStatus, done: false, text: "Partly installed (\(installed) of \(total))")
            hooksButton.title = "Finish setup…"
            hooksButton.isHidden = false
        case .success(.notInstalled):
            mark(hooksIcon, hooksStatus, done: false, text: "Not installed")
            hooksButton.title = "Set up…"
            hooksButton.isHidden = false
        case .failure(let error):
            mark(hooksIcon, hooksStatus, done: false, text: error.localizedDescription)
            hooksButton.title = "Try again…"
            hooksButton.isHidden = false
        }

        let lidSetUp = host.lidSetUp
        mark(lidIcon, lidStatus, done: lidSetUp, text: lidSetUp ? "Set up" : "Not set up (optional)")

        let listening = host.hookServerListening
        mark(serverIcon, serverStatus, done: listening,
             text: listening ? "Hook server is listening on 127.0.0.1:\(wakeloopPort)"
                             : "Hook server is not listening. Another copy of Wakeloop may be running.")

        let connected = host.claudeConnected
        mark(connectedIcon, connectedStatus, done: connected,
             text: connected ? "Connected" : "Waiting for your first Claude Code prompt",
             color: connected ? .systemGreen : nil)
        window.setContentSize(NSSize(width: 460, height: window.contentView?.fittingSize.height ?? 400))
    }

    /// Icon and text for one status line. `color` overrides the text colour (green for Connected).
    private func mark(_ icon: NSImageView, _ label: NSTextField, done: Bool, text: String, color: NSColor? = nil) {
        let symbol = done ? "checkmark.circle.fill" : "circle"
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: done ? "Done" : "Not done")
        icon.contentTintColor = done ? .systemGreen : .secondaryLabelColor
        label.stringValue = text
        label.textColor = color ?? (done ? .labelColor : .secondaryLabelColor)
    }

    private func statusRow(_ icon: NSImageView, _ label: NSTextField) -> NSStackView {
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 18).isActive = true
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.preferredMaxLayoutWidth = 380
        return row([icon, label])
    }

    private func step(_ number: Int, title: String, body: String, rows: [NSView]) -> NSStackView {
        let heading = NSTextField(labelWithString: "\(number). \(title)")
        heading.font = .boldSystemFont(ofSize: 13)
        let text = wrapping(body, size: 12, color: .secondaryLabelColor)
        let stack = NSStackView(views: [heading, text] + rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        return stack
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    private func wrapping(_ text: String, size: CGFloat, color: NSColor) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: size)
        label.textColor = color
        label.preferredMaxLayoutWidth = 412
        return label
    }

    @objc private func setUpHooks() {
        host.setupClaudeHooks()
        refresh()
    }

    @objc private func openLid() {
        host.openLidWindow()
    }

    @objc private func closeGuide() {
        window.close()
    }
}
