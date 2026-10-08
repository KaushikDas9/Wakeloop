import AppKit
import Carbon.HIToolbox
import ServiceManagement
import UserNotifications
import WakeloopCore

enum Mode: String { case auto, on, off }

final class AppDelegate: NSObject, NSApplicationDelegate {
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
    private var server: HookServer?
    private let lock = NSLock()
    private var whyWindow: NSWindow?
    private var whyText: NSTextView?
    private let lid = LidManager()
    private var lidFailed = false
    private var lidEnabled: Bool {
        get { defaults.bool(forKey: "lidClosed") }
        set { defaults.set(newValue, forKey: "lidClosed") }
    }
    private var lastVerdict: GuardVerdict = .allowed
    private let canNotify = Bundle.main.bundleIdentifier != nil

    func applicationDidFinishLaunching(_ note: Notification) {
        tracker.gracePeriod = TimeInterval(graceMinutes * 60)
        if canNotify { UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in } }
        // Crash recovery: if a previous run left sleep disabled, restore it (only when we set it).
        if defaults.bool(forKey: "lidOwned"), lid.sleepDisabledNow() == true { lid.setSleepDisabled(false) }
        defaults.set(false, forKey: "lidOwned")
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
    }

    private func handle(_ msg: HookServer.Message) {
        lock.lock()
        switch msg {
        case .event(let session, let event): tracker.apply(event, session: session)
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
            defaults.set(false, forKey: "lidOwned")
            notify("Lid-closed mode needs one-time setup. Run: wakeloop lid-setup")
        }
    }

    @objc private func toggleLid() {
        lidEnabled.toggle()
        lidFailed = false
        refresh()
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
        let verdict = safety.evaluate(SystemPower.read())
        let holding = power.isHolding
        let paused = pausedUntil.map { $0 > Date() } ?? false
        let manual = manualUntil.map { $0 > Date() } ?? false
        lock.unlock()
        let power = SystemPower.read()
        var out = "Wakeloop is \(holding ? "HOLDING the Mac awake" : "allowing sleep")\n"
        out += "Lid-closed: \(lidEnabled ? (lid.isActive ? "on, active" : "on, idle") : "off")\nMode: \(mode.rawValue)   Paused: \(paused)   Manual hold: \(manual)   Grace: \(graceMinutes) min\n"
        out += "Battery: \(power.batteryPercent.map { "\($0)%" } ?? "none")  AC: \(power.onAC)  Hot: \(power.thermalHot)  Guard: \(verdict)\n\n"
        out += "Agent sessions (\(sessions.count)):\n"
        for (id, state) in sessions.sorted(by: { $0.key < $1.key }) { out += "  \(id.prefix(12))  \(state)\n" }
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

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            NSLog("Wakeloop: launch at login needs a signed .app bundle: \(error)")
        }
        refresh()
    }

    private func refresh() {
        // Sampled outside the lock: spawning ps is the slowest part of a refresh.
        let busyChildren = ProcessTree.busyAgentDescendants(ProcessTree.snapshot())
        let transcripts = SessionFiles.recentlyActive(SessionFiles.scan())
        lock.lock()
        let manual = manualUntil.map { $0 > Date() } ?? false
        let paused = pausedUntil.map { $0 > Date() } ?? false
        if !paused { pausedUntil = nil }
        let wantsHold: Bool
        var reason: String
        switch mode {
        case .off: wantsHold = false; reason = "Wakeloop is off"
        case .on: wantsHold = true; reason = "Always on"
        case .auto:
            let hooked = manual || tracker.shouldHold()
            wantsHold = hooked || !busyChildren.isEmpty || !transcripts.isEmpty
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
        let verdict = safety.evaluate(SystemPower.read())
        let hold = wantsHold && !paused && verdict == .allowed
        if verdict != lastVerdict {
            lastVerdict = verdict
            if wantsHold && verdict != .allowed {
                notify(verdict == .tooHot ? "Mac is too hot: letting it sleep" : "Battery low: letting it sleep")
            }
        }
        switch verdict {
        case .lowBattery: reason = "Battery low: sleep allowed"
        case .tooHot: reason = "Mac too hot: sleep allowed"
        case .allowed: break
        }
        lock.unlock()

        power.setHold(hold)
        applyLid(wanted: hold && lidEnabled)
        statusItem.button?.title = hold ? "● Wakeloop" : "○ Wakeloop"

        let menu = NSMenu()
        menu.addItem(withTitle: hold ? "Awake: \(reason)" : "Sleep allowed: \(reason)", action: nil, keyEquivalent: "")
        let why = NSMenuItem(title: "Why is my Mac awake…", action: #selector(showWhy), keyEquivalent: "")
        why.target = self
        menu.addItem(why)
        menu.addItem(.separator())

        for (title, m) in [("Auto", Mode.auto), ("Always on", .on), ("Off", .off)] {
            let item = NSMenuItem(title: title, action: #selector(setMode(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = m.rawValue
            item.state = mode == m ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())

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

        let graceMenu = NSMenu()
        for mins in [1, 5, 10, 15, 30] {
            let item = NSMenuItem(title: "\(mins) min", action: #selector(setGrace(_:)), keyEquivalent: "")
            item.target = self; item.tag = mins
            item.state = graceMinutes == mins ? .on : .off
            graceMenu.addItem(item)
        }
        let graceItem = NSMenuItem(title: "Waiting-for-you grace", action: nil, keyEquivalent: "")
        graceItem.submenu = graceMenu
        menu.addItem(graceItem)

        let lidItem = NSMenuItem(title: lidFailed ? "Lid-closed (needs setup: wakeloop lid-setup)" : "Keep awake with lid closed",
                                 action: #selector(toggleLid), keyEquivalent: "")
        lidItem.target = self
        lidItem.state = lidEnabled ? .on : .off
        menu.addItem(lidItem)

        let login = NSMenuItem(title: "Launch at login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
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
