import AppKit
import Carbon.HIToolbox
import ServiceManagement
import UserNotifications
import WakeloopCore

enum Mode: String { case auto, on, off }

/// One agent's hooks file, as the setup, remove and guide flows see it.
struct AgentHookSetup {
    let name: String
    let installer: HookInstaller
    let events: [String]
    /// Shown in the confirmation and after a successful setup. Nil when the agent needs nothing more.
    let trustNote: String?
    let menuHint: String

    static let claude = AgentHookSetup(
        name: "Claude Code", installer: HookInstaller(), events: HookSnippet.claudeEvents, trustNote: nil,
        menuHint: "Adds Wakeloop's hooks to ~/.claude/settings.json and keeps your other hooks. Remove them the same way.")

    static let codex = AgentHookSetup(
        name: "Codex", installer: HookInstaller.codex(), events: HookSnippet.codexEvents,
        trustNote: "Codex also needs you to trust the hooks once. Open Codex, run /hooks, and trust Wakeloop's entries. Until you do, Codex skips them.",
        menuHint: "Adds Wakeloop's hooks to ~/.codex/hooks.json and keeps your other hooks. Then trust them with /hooks in Codex.")
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, LidHost, SetupGuideHost {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let power = PowerManager()
    private var tracker = SessionTracker()
    private var safety = SafetyGuard()
    private var manualUntil: Date?
    private var pausedUntil: Date?
    private let defaults = UserDefaults.standard
    private var mode: Mode {
        get { Mode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .auto }
        set { defaults.set(newValue.rawValue, forKey: "mode") }
    }
    private var graceMinutes: Int {
        get { defaults.object(forKey: "graceMinutes") as? Int ?? 5 }
        set { defaults.set(newValue, forKey: "graceMinutes") }
    }
    // Hours an automatic hold may last without agent activity; 0 is Off.
    private var maxHoldHours: Int {
        get { defaults.object(forKey: "maxHoldHours") as? Int ?? 8 }
        set { defaults.set(newValue, forKey: "maxHoldHours") }
    }
    private var holdCap = HoldCap()
    private var server: HookServer?
    private let lock = NSLock()
    private var whyWindow: NSWindow?
    private var whyText: NSTextView?
    private lazy var lidWindow = LidWindowController(host: self)
    private let claudeSetup = AgentHookSetup.claude
    private let codexSetup = AgentHookSetup.codex
    // Results of the last read of each agent's hooks file, taken on each refresh.
    private(set) var claudeHooks: Result<HookInstaller.Status, Error> = .success(.notInstalled)
    private(set) var codexHooks: Result<HookInstaller.Status, Error> = .success(.notInstalled)
    private lazy var setupGuide = SetupGuideWindowController(host: self)
    private let lid = LidManager()
    private var lidFailed = false
    // Whether the sudoers rule is installed; checked at launch and after setup or removal (spawns sudo).
    var lidSetUp = false
    private var lidGuard = LidGuard()
    private var lastLidAllowed = true
    var lidOnBattery: Bool {
        get { defaults.bool(forKey: "lidOnBattery") }
        set { defaults.set(newValue, forKey: "lidOnBattery") }
    }
    var lidEnabled: Bool {
        get { defaults.bool(forKey: "lidClosed") }
        set { defaults.set(newValue, forKey: "lidClosed") }
    }
    private var lastVerdict: GuardVerdict = .allowed
    private var collapsedProjects = Set<String>()
    // Sub-agent rows per project in the current menu; the rows are inserted or removed in place on toggle.
    private var projectRows: [String: (item: NSMenuItem, subs: [NSMenuItem])] = [:]
    private var menuIsOpen = false
    // The breathing icon runs only while holding; iconHolding is the state the timer reads.
    private var iconHolding = false
    private var iconTimer: Timer?
    private var iconStart = Date()
    // One breathing cycle of the menu bar icon, in seconds.
    private let iconCycle: TimeInterval = 2.4
    private let canNotify = Bundle.main.bundleIdentifier != nil

    func applicationDidFinishLaunching(_ note: Notification) {
        tracker.gracePeriod = TimeInterval(graceMinutes * 60)
        holdCap.limit = Self.holdLimit(hours: maxHoldHours)
        if canNotify { UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in } }
        // Crash recovery: if a previous run left sleep disabled, restore it (only when we set it).
        if defaults.bool(forKey: "lidOwned"), lid.sleepDisabledNow() == true { lid.setSleepDisabled(false) }
        defaults.set(false, forKey: "lidOwned")
        lidSetUp = lid.isSetUp()
        refresh()
        // Ctrl+Opt+Cmd+P pauses for 30 min (or resumes); Ctrl+Opt+Cmd+M cycles Auto / Always on / Off.
        HotKeys.register(keyCode: kVK_ANSI_P, id: 1) { [weak self] in self?.togglePause() }
        HotKeys.register(keyCode: kVK_ANSI_M, id: 2) { [weak self] in self?.cycleMode() }
        do {
            server = try HookServer { [weak self] msg in self?.handle(msg) }
            server?.start()
        } catch {
            NSLog("Wakeloop: cannot start hook server: \(error)")
        }
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refresh() }
        // The setup guide opens once, on first launch. Settings, "Show setup guide…" reopens it.
        if !defaults.bool(forKey: "setupGuideShown") {
            defaults.set(true, forKey: "setupGuideShown")
            showSetupGuide()
        }
    }

    // MARK: - Setup guide host

    var hookServerListening: Bool { server?.isListening ?? false }

    /// Agents whose hook events have reached the server, by display name. Set by the first event from each agent.
    /// An event with no transcript path is taken to be Claude Code, as before Codex support.
    var connectedAgents: [String] {
        var names: [String] = []
        if defaults.bool(forKey: "claudeEventSeen") { names.append(claudeSetup.name) }
        if defaults.bool(forKey: "codexEventSeen") { names.append(codexSetup.name) }
        return names
    }

    func readClaudeHooks() -> Result<HookInstaller.Status, Error> {
        Result { try claudeSetup.installer.status() }
    }

    func readCodexHooks() -> Result<HookInstaller.Status, Error> {
        Result { try codexSetup.installer.status() }
    }

    func openLidWindow() {
        lidWindow.show()
    }

    @objc private func showSetupGuide() {
        setupGuide.show()
    }

    private func handle(_ msg: HookServer.Message) {
        lock.lock()
        switch msg {
        case .event(let session, let event, let cwd, let transcript):
            tracker.apply(event, session: session, cwd: cwd, transcript: transcript)
            holdCap.activity()
            let agent = HookPayload.agent(transcript: transcript) ?? "claude"
            defaults.set(true, forKey: "\(agent)EventSeen")
        case .hold(let secs): manualUntil = Date().addingTimeInterval(secs)
        case .done: manualUntil = nil
        }
        lock.unlock()
        DispatchQueue.main.async { self.refresh() }
    }

    func applicationWillTerminate(_ note: Notification) {
        if lid.isActive { lid.setSleepDisabled(false); defaults.set(false, forKey: "lidOwned") }
    }

    private func applyLid(wanted: Bool) {
        guard wanted != lid.isActive, !(wanted && lidFailed) else { return }
        if wanted { defaults.set(true, forKey: "lidOwned") }
        if lid.setSleepDisabled(wanted) {
            if !wanted { defaults.set(false, forKey: "lidOwned") }
        } else if wanted {
            lidFailed = true
            lidSetUp = false
            defaults.set(false, forKey: "lidOwned")
            notify("Lid-closed mode needs setup. Open the Wakeloop menu, Settings, Lid-closed mode.")
        }
    }

    /// Runs `shell` as root behind the standard macOS password dialog. nil on success or when the user cancels.
    private func runPrivileged(_ shell: String, prompt: String) -> String? {
        var error: NSDictionary?
        NSAppleScript(source: LidManager.appleScript(running: shell, prompt: prompt))?.executeAndReturnError(&error)
        guard let error else { return nil }
        if (error[NSAppleScript.errorNumber] as? Int) == -128 { return nil }
        return error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
    }

    private func confirm(_ title: String, _ detail: String, button: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func inform(_ title: String, _ detail: String = "") {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
    }

    private func showError(_ text: String) {
        inform("Wakeloop", text)
    }

    /// Confirms, then merges Wakeloop's hooks into the agent's hooks file. Returns true when they are in place.
    @discardableResult
    func setupHooks(_ agent: AgentHookSetup) -> Bool {
        guard confirm("Set up \(agent.name) hooks",
                      "Wakeloop will add its hooks to \(agent.installer.settingsURL.path) for these events: \(agent.events.joined(separator: ", ")).\n\nYour other hooks and settings stay as they are. Wakeloop saves a backup of the file next to it first." + (agent.trustNote.map { "\n\n" + $0 } ?? ""),
                      button: "Set up") else { return false }
        defer { refresh() }
        do {
            switch try agent.installer.install() {
            case .changed(let backup):
                let backupNote = backup.map { "A backup was saved as \($0.lastPathComponent)." } ?? ""
                inform("\(agent.name) hooks are set up.", [backupNote, agent.trustNote ?? ""].filter { !$0.isEmpty }.joined(separator: "\n\n"))
            case .unchanged:
                inform("\(agent.name) hooks are already set up.")
            }
            return true
        } catch {
            showError(error.localizedDescription)
            return false
        }
    }

    /// Confirms, then removes only Wakeloop's hook entries. Returns true when none are left.
    @discardableResult
    func removeHooks(_ agent: AgentHookSetup) -> Bool {
        guard confirm("Remove \(agent.name) hooks",
                      "Wakeloop will remove its hook entries from \(agent.installer.settingsURL.path). Your other hooks stay as they are. Wakeloop saves a backup of the file first.\n\nWithout the hooks, Wakeloop still watches transcripts and busy processes, but it sees \(agent.name) sessions later and less reliably.",
                      button: "Remove") else { return false }
        defer { refresh() }
        do {
            switch try agent.installer.remove() {
            case .changed(let backup):
                inform("\(agent.name) hooks are removed.", backup.map { "A backup was saved as \($0.lastPathComponent)." } ?? "")
            case .unchanged:
                inform("No Wakeloop hooks were found.")
            }
            return true
        } catch {
            showError(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func setupClaudeHooks() -> Bool { setupHooks(claudeSetup) }

    @discardableResult
    func setupCodexHooks() -> Bool { setupHooks(codexSetup) }

    @objc private func toggleClaudeHooks() { toggleHooks(claudeSetup, claudeHooks) }

    @objc private func toggleCodexHooks() { toggleHooks(codexSetup, codexHooks) }

    private func toggleHooks(_ agent: AgentHookSetup, _ status: Result<HookInstaller.Status, Error>) {
        if case .success(.installed) = status {
            removeHooks(agent)
        } else {
            setupHooks(agent)
        }
    }

    /// A Settings item that sets up or removes one agent's hooks, with the current state as its subtitle.
    private func hooksMenuItem(_ agent: AgentHookSetup, status: Result<HookInstaller.Status, Error>, action: Selector) -> NSMenuItem {
        let installed: Bool = { if case .success(.installed) = status { return true } else { return false } }()
        let item = NSMenuItem(title: installed ? "Remove \(agent.name) hooks…" : "Set up \(agent.name) hooks…",
                              action: action, keyEquivalent: "")
        item.target = self
        hint(item, subtitle: Self.hookSubtitle(agent, status), fallback: agent.menuHint)
        return item
    }

    static func hookSubtitle(_ agent: AgentHookSetup, _ status: Result<HookInstaller.Status, Error>) -> String {
        switch status {
        case .success(.installed): return agent.trustNote == nil ? "Installed" : "Installed. Trust it with /hooks in \(agent.name)."
        case .success(.partial(let installed, let total)): return "Partly installed (\(installed) of \(total))"
        case .success(.notInstalled): return "Not installed"
        case .failure: return "Settings file needs attention"
        }
    }

    func setupLid() {
        guard confirm("Set up lid-closed mode",
                      "macOS needs your permission once. Wakeloop will allow itself to run only two commands as administrator: turning sleep prevention on and off.\n\nYou can remove this any time from the Wakeloop menu. Never put a working Mac in a closed bag.",
                      button: "Continue") else { return }
        guard let script = LidManager.installScript(user: NSUserName()) else {
            showError("This account name can't be used for setup.")
            return
        }
        if let message = runPrivileged(script, prompt: "Wakeloop needs permission to keep your Mac awake with the lid closed.") {
            showError("Setup failed: \(message)")
        }
        lidSetUp = lid.isSetUp()
        if lidSetUp {
            lidEnabled = true
            lidFailed = false
            notify("Lid-closed mode is set up and on.")
        }
        refresh()
    }

    func removeLidSetup() {
        guard confirm("Remove lid-closed setup", "Wakeloop will no longer be able to keep your Mac awake with the lid closed.", button: "Remove") else { return }
        if lid.isActive { lid.setSleepDisabled(false) }
        defaults.set(false, forKey: "lidOwned")
        if let message = runPrivileged(LidManager.removeScript, prompt: "Wakeloop needs permission to remove its lid-closed setup.") {
            showError("Removal failed: \(message)")
        }
        lidSetUp = lid.isSetUp()
        if !lidSetUp { lidEnabled = false }
        refresh()
    }

    func toggleLidOnBattery() {
        if !lidOnBattery {
            guard confirm("Allow lid-closed mode on battery?",
                          "By default lid-closed mode only works while the charger is connected. If you allow battery, Wakeloop keeps the Mac awake with the lid closed until the battery reaches 30%, then lets it sleep.\n\nA closed Mac has less airflow. Never put a working Mac in a closed bag.",
                          button: "Allow") else { return }
        }
        lidOnBattery.toggle()
        refresh()
    }

    func toggleLid() {
        lidEnabled.toggle()
        lidFailed = false
        refresh()
    }

    private static func holdLimit(hours: Int) -> TimeInterval? { hours > 0 ? TimeInterval(hours * 3600) : nil }

    /// Notification text for a guard that has just started releasing the hold.
    private static func guardNotice(_ verdict: GuardVerdict) -> String {
        switch verdict {
        case .tooHot: return "Mac is too hot: letting it sleep"
        case .holdTimedOut: return "Max hold reached with no agent activity: letting it sleep"
        case .lowBattery, .allowed: return "Battery low: letting it sleep"
        }
    }

    private func notify(_ text: String) {
        guard canNotify else { return }
        let content = UNMutableNotificationContent()
        content.title = "Wakeloop"
        content.body = text
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    @objc private func setMode(_ sender: NSMenuItem) {
        mode = Mode(rawValue: sender.representedObject as? String ?? "") ?? .auto
        refresh()
    }

    private func togglePause() {
        lock.lock()
        pausedUntil = (pausedUntil.map { $0 > Date() } ?? false) ? nil : Date().addingTimeInterval(30 * 60)
        lock.unlock()
        refresh()
    }

    private func cycleMode() {
        let order: [Mode] = [.auto, .on, .off]
        mode = order[((order.firstIndex(of: mode) ?? 0) + 1) % order.count]
        refresh()
    }

    private func toggleProject(_ name: String) {
        guard let row = projectRows[name], let menu = row.item.menu else { return }
        if collapsedProjects.insert(name).inserted {
            row.subs.forEach { menu.removeItem($0) }
        } else {
            collapsedProjects.remove(name)
            var index = menu.index(of: row.item) + 1
            for sub in row.subs { menu.insertItem(sub, at: index); index += 1 }
        }
        (row.item.view as? ProjectRowView)?.collapsed = collapsedProjects.contains(name)
    }

    func menuWillOpen(_ menu: NSMenu) { menuIsOpen = true }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        refresh()
    }

    @objc private func showLidWindow() {
        openLidWindow()
    }

    @objc private func showWhy() {
        if whyWindow == nil {
            let scroll = NSTextView.scrollableTextView()
            let text = scroll.documentView as! NSTextView
            text.isEditable = false
            text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            text.textContainerInset = NSSize(width: 10, height: 10)
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 460),
                               styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            win.title = "Why is my Mac awake"
            win.contentView = scroll
            win.isReleasedWhenClosed = false
            win.center()
            whyWindow = win; whyText = text
        }
        whyText?.string = whyReport()
        NSApp.activate(ignoringOtherApps: true)
        whyWindow?.makeKeyAndOrderFront(nil)
    }

    private func whyReport() -> String {
        lock.lock()
        let sessions = tracker.sessions
        let subagents = tracker.subagents
        let verdict = safety.evaluate(SystemPower.read())
        let holding = power.isHolding
        let paused = pausedUntil.map { $0 > Date() } ?? false
        let manual = manualUntil.map { $0 > Date() } ?? false
        lock.unlock()
        let power = SystemPower.read()
        var out = "Wakeloop is \(holding ? "HOLDING the Mac awake" : "allowing sleep")\n"
        out += "Lid-closed: \(lidEnabled ? (lid.isActive ? "on, active" : "on, idle") : "off")\nMode: \(mode.rawValue)   Paused: \(paused)   Manual hold: \(manual)   Grace: \(graceMinutes) min   Max hold: \(maxHoldHours == 0 ? "off" : "\(maxHoldHours) h")\n"
        out += "Battery: \(power.batteryPercent.map { "\($0)%" } ?? "none")  AC: \(power.onAC)  Hot: \(power.thermalHot)  Guard: \(verdict)\n\n"
        out += "Agent sessions (\(sessions.count)):\n"
        for (id, state) in sessions.sorted(by: { $0.key < $1.key }) {
            let subs = subagents[id].map { $0.values.map(\.type).sorted() } ?? []
            out += "  \(id.prefix(12))  \(state)" + (subs.isEmpty ? "" : "  + \(subs.count) subagent(s): \(subs.joined(separator: ", "))") + "\n"
        }
        // Sub-agents of a session that never reported its own state (e.g. hooks loaded mid-run).
        for (id, agents) in subagents.sorted(by: { $0.key < $1.key }) where sessions[id] == nil {
            out += "  \(id.prefix(12))  (no session state)  + \(agents.count) subagent(s): \(agents.values.map(\.type).sorted().joined(separator: ", "))\n"
        }
        if sessions.isEmpty { out += "  none reported by hooks\n" }
        let busy = ProcessTree.busyAgentDescendants(ProcessTree.snapshot())
        out += "\nBusy processes under agents (\(busy.count)):\n"
        for p in busy { out += "  pid \(p.pid)  \(p.name)  \(p.cpu)% CPU\n" }
        if busy.isEmpty { out += "  none\n" }
        out += "\nAll sleep assertions on this Mac (pmset -g assertions):\n" + Self.pmsetAssertions()
        return out
    }

    private static func pmsetAssertions() -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["-g", "assertions"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return "  unavailable\n" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    @objc private func pause(_ sender: NSMenuItem) {
        lock.lock()
        if sender.tag > 0 {
            pausedUntil = Date().addingTimeInterval(TimeInterval(sender.tag * 60))
        } else {
            pausedUntil = Calendar.current.nextDate(after: Date(), matching: DateComponents(hour: 6), matchingPolicy: .nextTime)
        }
        lock.unlock()
        refresh()
    }

    @objc private func resume() {
        lock.lock(); pausedUntil = nil; lock.unlock()
        refresh()
    }

    @objc private func setGrace(_ sender: NSMenuItem) {
        graceMinutes = sender.tag
        lock.lock(); tracker.gracePeriod = TimeInterval(sender.tag * 60); lock.unlock()
        refresh()
    }

    @objc private func setMaxHold(_ sender: NSMenuItem) {
        maxHoldHours = sender.tag
        lock.lock(); holdCap.limit = Self.holdLimit(hours: sender.tag); lock.unlock()
        refresh()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            NSLog("Wakeloop: launch at login needs a signed .app bundle: \(error)")
        }
        refresh()
    }

    private func setStatusTitle(hold: Bool, workingCount: Int) {
        guard let button = statusItem.button else { return }
        button.toolTip = nil
        button.setAccessibilityLabel("Wakeloop")
        let workingCount = hold ? workingCount : 0   // a count beside the idle ring (sleep allowed) would mislead
        let count = workingCount > 0 ? " \(workingCount)" : ""
        iconHolding = hold
        updateIconTimer()
        button.image = StatusIcon.image(holding: hold, phase: iconPhase())
        button.imagePosition = count.isEmpty ? .imageOnly : .imageLeft
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .bold)
        button.attributedTitle = NSAttributedString(string: count, attributes: [.font: font])
    }

    /// Runs only while holding and not under Reduce Motion; otherwise the icon rests in its still state.
    private func updateIconTimer() {
        let animate = iconHolding && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if animate {
            guard iconTimer == nil else { return }
            iconStart = Date()
            let timer = Timer(timeInterval: 0.083, repeats: true) { [weak self] _ in self?.tickIcon() }
            RunLoop.main.add(timer, forMode: .common)
            iconTimer = timer
        } else {
            iconTimer?.invalidate()
            iconTimer = nil
        }
    }

    private func tickIcon() {
        guard iconHolding else { return }
        statusItem.button?.image = StatusIcon.image(holding: true, phase: iconPhase())
    }

    private func iconPhase() -> CGFloat {
        guard iconHolding, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return 0 }
        return CGFloat(Date().timeIntervalSince(iconStart).truncatingRemainder(dividingBy: iconCycle) / iconCycle)
    }

    /// Grey subtitle on macOS 14.4+; older systems show the tooltip instead.
    private func hint(_ item: NSMenuItem, subtitle: String, fallback: String) {
        if #available(macOS 14.4, *) { item.subtitle = subtitle } else { item.toolTip = fallback }
    }

    private func refresh() {
        // Sampled outside the lock: spawning ps is the slowest part of a refresh.
        let busyChildren = ProcessTree.busyAgentDescendants(ProcessTree.snapshot())
        let transcripts = SessionFiles.recentlyActive(SessionFiles.scan())
        lock.lock()
        claudeHooks = readClaudeHooks()
        codexHooks = readCodexHooks()
        let lastWrite: (String) -> Date? = { path in
            (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        }
        tracker.pruneStaleSubagents(at: Date(), lastWrite: lastWrite)
        tracker.pruneCrashedSessions(at: Date(), lastWrite: lastWrite)
        if !transcripts.isEmpty { holdCap.activity() }
        let manual = manualUntil.map { $0 > Date() } ?? false
        let paused = pausedUntil.map { $0 > Date() } ?? false
        if !paused { pausedUntil = nil }
        let wantsHold: Bool
        var reason: String
        let workingCount = tracker.workingCount
        let workerGroups = tracker.workingGroups
        switch mode {
        case .off: wantsHold = false; reason = "Wakeloop is off"
        case .on: wantsHold = true; reason = "Always on"
        case .auto:
            let hooked = manual || tracker.shouldHold()
            wantsHold = manual || tracker.wantsHold(busyChildren: busyChildren, activeTranscripts: transcripts)
            reason = manual ? "Manual hold" : tracker.reason()
            if !hooked, let top = busyChildren.max(by: { $0.cpu < $1.cpu }) {
                reason = "Background work: \(top.name) running under an agent"
            } else if !hooked, !transcripts.isEmpty {
                reason = "Agent transcript was just written to"
            }
        }
        if paused, let until = pausedUntil {
            reason = "Paused until \(until.formatted(date: .omitted, time: .shortened))"
        }
        let status = SystemPower.read()
        // The cap applies to automatic holds only. Always on and manual holds are explicit choices.
        let capped = holdCap.tripped(holding: mode == .auto && !manual && wantsHold)
        let batteryOrHeat = safety.evaluate(status)
        let verdict = batteryOrHeat == .allowed && capped ? GuardVerdict.holdTimedOut : batteryOrHeat
        let hold = wantsHold && !paused && verdict == .allowed
        let lidAllowed = lidGuard.allows(status, batteryAllowed: lidOnBattery)
        if lidAllowed != lastLidAllowed {
            lastLidAllowed = lidAllowed
            if hold && lidEnabled && lidSetUp && !lidAllowed {
                notify(lidOnBattery ? "Lid-closed mode paused: battery is at 30% or lower" : "Lid-closed mode paused: connect the charger")
            }
        }
        if verdict != lastVerdict {
            lastVerdict = verdict
            if wantsHold && verdict != .allowed {
                notify(Self.guardNotice(verdict))
            }
        }
        switch verdict {
        case .lowBattery: reason = "Battery low: sleep allowed"
        case .tooHot: reason = "Mac too hot: sleep allowed"
        case .holdTimedOut: reason = "Max hold reached: sleep allowed until agent activity"
        case .allowed: break
        }
        lock.unlock()

        power.setHold(hold)
        applyLid(wanted: hold && lidEnabled && lidSetUp && lidAllowed)
        setStatusTitle(hold: hold, workingCount: workingCount)
        // An open menu is left alone; it is rebuilt when it closes.
        guard !menuIsOpen else { return }

        projectRows = [:]
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: hold ? "Awake: \(reason)" : "Sleep allowed: \(reason)", action: nil, keyEquivalent: "")
        if !workerGroups.isEmpty {
            menu.addItem(.separator())
            menu.addItem(withTitle: "Working now (\(workingCount))", action: nil, keyEquivalent: "")
            for group in workerGroups.prefix(12) {
                let subs = group.subagentTotal
                var hints: [String] = []
                if group.mainWorking { hints.append("working") }
                if subs > 0 { hints.append("\(subs) subagent\(subs == 1 ? "" : "s")") }
                let text = "\(group.project) (\(hints.joined(separator: ", ")))"
                if subs == 0 {
                    menu.addItem(withTitle: "   \(text)", action: nil, keyEquivalent: "")
                    continue
                }
                let collapsed = collapsedProjects.contains(group.project)
                let item = NSMenuItem()
                let row = ProjectRowView(title: text, collapsed: collapsed)
                row.onClick = { [weak self] in self?.toggleProject(group.project) }
                item.view = row
                let subItems = group.subagents.enumerated().map { (i, name) in
                    NSMenuItem(title: "      \(i == group.subagents.count - 1 ? "└ " : "├ ")\(name)", action: nil, keyEquivalent: "")
                }
                projectRows[group.project] = (item, subItems)
                menu.addItem(item)
                if !collapsed { subItems.forEach { menu.addItem($0) } }
            }
            if workerGroups.count > 12 {
                menu.addItem(withTitle: "   … and \(workerGroups.count - 12) more projects", action: nil, keyEquivalent: "")
            }
        }
        menu.addItem(.separator())

        let modeMenu = NSMenu()
        let modes: [(title: String, mode: Mode)] = [
            ("Auto", .auto),
            ("Always on (e.g. Remote Control)", .on),
            ("Off", .off),
        ]
        for m in modes {
            let item = NSMenuItem(title: m.title, action: #selector(setMode(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = m.mode.rawValue
            item.state = mode == m.mode ? .on : .off
            if m.mode == .on {
                hint(item, subtitle: "Keeps your Mac awake until you change it",
                     fallback: "Keeps your Mac awake all the time until you change this. Use it so Remote Control keeps working.")
            }
            modeMenu.addItem(item)
        }
        modeMenu.addItem(.separator())
        modeMenu.addItem(withTitle: "Always on keeps the Mac awake until you change it.", action: nil, keyEquivalent: "")
        let modeItem = NSMenuItem(title: "Mode: \(mode == .auto ? "Auto" : mode == .on ? "Always on" : "Off")", action: nil, keyEquivalent: "")
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        let pauseMenu = NSMenu()
        for (title, mins) in [("30 minutes", 30), ("1 hour", 60), ("Until tomorrow", -1)] {
            let item = NSMenuItem(title: title, action: #selector(pause(_:)), keyEquivalent: "")
            item.target = self; item.tag = mins
            pauseMenu.addItem(item)
        }
        if paused {
            pauseMenu.addItem(.separator())
            let resume = NSMenuItem(title: "Resume now", action: #selector(resume), keyEquivalent: "")
            resume.target = self
            pauseMenu.addItem(resume)
        }
        let pauseItem = NSMenuItem(title: "Pause", action: nil, keyEquivalent: "")
        pauseItem.submenu = pauseMenu
        menu.addItem(pauseItem)
        menu.addItem(.separator())

        let why = NSMenuItem(title: "Why is my Mac awake…", action: #selector(showWhy), keyEquivalent: "")
        why.target = self
        menu.addItem(why)
        menu.addItem(.separator())

        let graceMenu = NSMenu()
        graceMenu.addItem(withTitle: "When an agent is waiting for you, sleep after:", action: nil, keyEquivalent: "")
        graceMenu.addItem(.separator())
        for mins in [1, 5, 10, 15, 30] {
            let item = NSMenuItem(title: "\(mins) min", action: #selector(setGrace(_:)), keyEquivalent: "")
            item.target = self; item.tag = mins
            item.state = graceMinutes == mins ? .on : .off
            graceMenu.addItem(item)
        }
        let graceItem = NSMenuItem(title: "Sleep after: \(graceMinutes) min", action: nil, keyEquivalent: "")
        graceItem.submenu = graceMenu
        hint(graceItem, subtitle: "When an agent is waiting for you",
             fallback: "When Claude (or another agent) stops to ask you something, Wakeloop keeps your Mac awake this long. If you do not answer in time, your Mac is allowed to sleep.")

        let settingsMenu = NSMenu()
        let guideItem = NSMenuItem(title: "Show setup guide…", action: #selector(showSetupGuide), keyEquivalent: "")
        guideItem.target = self
        settingsMenu.addItem(guideItem)
        settingsMenu.addItem(.separator())
        settingsMenu.addItem(graceItem)

        let maxHoldMenu = NSMenu()
        maxHoldMenu.addItem(withTitle: "Release a hold after this long with no agent activity:", action: nil, keyEquivalent: "")
        maxHoldMenu.addItem(.separator())
        for hours in [4, 8, 12, 0] {
            let item = NSMenuItem(title: hours == 0 ? "Off" : "\(hours) hours", action: #selector(setMaxHold(_:)), keyEquivalent: "")
            item.target = self; item.tag = hours
            item.state = maxHoldHours == hours ? .on : .off
            maxHoldMenu.addItem(item)
        }
        let maxHoldItem = NSMenuItem(title: "Max hold: \(maxHoldHours == 0 ? "Off" : "\(maxHoldHours) hours")", action: nil, keyEquivalent: "")
        maxHoldItem.submenu = maxHoldMenu
        hint(maxHoldItem, subtitle: "Releases a hold no agent has touched for a long time",
             fallback: "Releases the Mac's hold when no agent event or transcript write has come for this long, so a stuck agent cannot keep the Mac awake all night. A new agent event brings the hold back.")
        settingsMenu.addItem(maxHoldItem)

        settingsMenu.addItem(hooksMenuItem(claudeSetup, status: claudeHooks, action: #selector(toggleClaudeHooks)))
        settingsMenu.addItem(hooksMenuItem(codexSetup, status: codexHooks, action: #selector(toggleCodexHooks)))

        let login = NSMenuItem(title: "Launch at login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        settingsMenu.addItem(login)
        let lidItem = NSMenuItem(title: "Lid-closed mode…", action: #selector(showLidWindow), keyEquivalent: "")
        lidItem.target = self
        hint(lidItem, subtitle: "Keep your Mac awake with the lid closed",
             fallback: "Keeps your Mac awake with the lid closed while an agent works. Needs a one-time setup.")
        settingsMenu.addItem(lidItem)
        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingsItem.submenu = settingsMenu
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Wakeloop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
