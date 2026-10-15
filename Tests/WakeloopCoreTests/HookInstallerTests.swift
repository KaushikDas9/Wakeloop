import Testing
import Foundation
@testable import WakeloopCore

struct HookInstallerTests {
    private let dir: URL
    private let settings: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("wakeloop-hooks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        settings = dir.appendingPathComponent("settings.json")
    }

    private func installer(at second: TimeInterval = 0) -> HookInstaller {
        HookInstaller(settingsURL: settings, now: { Date(timeIntervalSince1970: 1_700_000_000 + second) })
    }

    private func write(_ text: String) throws {
        try text.write(to: settings, atomically: true, encoding: .utf8)
    }

    private func read() throws -> String {
        try String(contentsOf: settings, encoding: .utf8)
    }

    private func json() throws -> [String: Any] {
        let data = try Data(contentsOf: settings)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func groups(_ root: [String: Any], _ event: String) -> [[String: Any]] {
        ((root["hooks"] as? [String: Any])?[event] as? [[String: Any]]) ?? []
    }

    private func command(ofGroup group: [String: Any]) -> String? {
        ((group["hooks"] as? [[String: Any]])?.first)?["command"] as? String
    }

    private func backups() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains(".wakeloop-backup-") }
    }

    private enum Kind { case unexpectedShape, readOnly }

    private func isFailure(_ error: Error, _ expected: Kind) -> Bool {
        switch (error as? HookInstaller.Failure, expected) {
        case (.unexpectedShape?, .unexpectedShape), (.readOnly?, .readOnly): return true
        default: return false
        }
    }

    @Test func freshFileGetsAllEventsAndNoBackup() throws {
        #expect(try installer().status() == .notInstalled)
        #expect(try installer().install() == .changed(backup: nil))
        let root = try json()
        for event in HookSnippet.claudeEvents {
            let g = groups(root, event)
            #expect(g.count == 1, "\(event)")
            #expect(command(ofGroup: g.first ?? [:]) == HookSnippet.command)
        }
        #expect(try installer().status() == .installed)
        #expect(try backups().isEmpty)
    }

    @Test func mergeKeepsExistingHooksSettingsAndOrder() throws {
        try write("""
        {
          "model": "opus",
          "hooks": {
            "Stop": [{ "hooks": [{ "type": "command", "command": "say done", "timeout": 10 }] }],
            "PreToolUse": [{ "matcher": "Bash", "hooks": [{ "type": "command", "command": "guard.sh" }] }]
          }
        }
        """)
        try installer().install()
        let root = try json()
        #expect(root["model"] as? String == "opus")
        let pre = groups(root, "PreToolUse")
        #expect(pre.count == 1)
        #expect(pre.first?["matcher"] as? String == "Bash")
        let stop = groups(root, "Stop")
        #expect(stop.count == 2)
        // The user's Stop hook stays first; ours is appended after it.
        #expect(command(ofGroup: stop[0]) == "say done")
        #expect(command(ofGroup: stop[1]) == HookSnippet.command)
        #expect(try installer().status() == .installed)
    }

    @Test func installIsIdempotent() throws {
        try write("{\"hooks\": {}}")
        guard case .changed(let first?) = try installer(at: 0).install() else {
            Issue.record("expected a change with a backup"); return
        }
        #expect(first.lastPathComponent.hasPrefix("settings.json.wakeloop-backup-"))
        let afterFirst = try read()
        #expect(try installer(at: 1).install() == .unchanged)
        #expect(try read() == afterFirst)
        #expect(try backups().count == 1, "a second run must not write another backup")
    }

    @Test func backupHoldsOriginalBytesAndTimestampedName() throws {
        let original = "{\n  \"model\": \"opus\",\n  \"hooks\": {\"Stop\": [{\"hooks\": [{\"type\": \"command\", \"command\": \"say done\"}]}]}\n}\n"
        try write(original)
        guard case .changed(let backup?) = try installer(at: 42).install() else {
            Issue.record("expected a backup"); return
        }
        let name = backup.lastPathComponent
        #expect(name.range(of: #"^settings\.json\.wakeloop-backup-\d{8}-\d{6}$"#, options: .regularExpression) != nil)
        #expect(backup.deletingLastPathComponent().path == dir.path)
        #expect(try String(contentsOf: backup, encoding: .utf8) == original)
    }

    @Test func invalidJSONIsRefusedAndNotTouched() throws {
        let broken = "{ \"hooks\": { \"Stop\": [ "
        try write(broken)
        #expect(throws: HookInstaller.Failure.self) { try installer().install() }
        #expect(throws: HookInstaller.Failure.self) { try installer().remove() }
        #expect(throws: HookInstaller.Failure.self) { try installer().status() }
        #expect(try read() == broken)
        #expect(try backups().isEmpty)
    }

    @Test func topLevelArrayIsRefused() throws {
        try write("[1, 2]")
        do {
            try installer().install()
            Issue.record("expected a refusal")
        } catch {
            #expect(isFailure(error, .unexpectedShape))
        }
        #expect(try read() == "[1, 2]")
    }

    @Test func hooksOfWrongTypeIsRefused() throws {
        try write("{\"hooks\": [\"nope\"]}")
        #expect(throws: HookInstaller.Failure.self) { try installer().install() }
        #expect(try read() == "{\"hooks\": [\"nope\"]}")
    }

    @Test func emptyFileIsTreatedAsEmptySettingsAndBackedUp() throws {
        try write("")
        #expect(try installer().status() == .notInstalled)
        guard case .changed(let backup?) = try installer().install() else {
            Issue.record("expected a backup"); return
        }
        #expect(FileManager.default.fileExists(atPath: backup.path))
        #expect(try installer().status() == .installed)
    }

    @Test func readOnlyFileIsRefusedAndNotTouched() throws {
        let text = "{\"model\": \"opus\"}"
        try write(text)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: settings.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: settings.path) }
        do {
            try installer().install()
            Issue.record("expected a refusal")
        } catch {
            #expect(isFailure(error, .readOnly))
        }
        #expect(try read() == text)
        #expect(try backups().isEmpty)
    }

    @Test func removeDeletesOnlyWakeloopEntries() throws {
        try write("""
        {
          "model": "opus",
          "hooks": {
            "Stop": [{ "hooks": [{ "type": "command", "command": "say done", "timeout": 10 }] }],
            "PreToolUse": [{ "matcher": "Bash", "hooks": [{ "type": "command", "command": "guard.sh" }] }]
          }
        }
        """)
        try installer().install()
        #expect(try installer().status() == .installed)
        guard case .changed = try installer().remove() else {
            Issue.record("expected a change"); return
        }
        let root = try json()
        #expect(root["model"] as? String == "opus")
        #expect(groups(root, "PreToolUse").count == 1)
        let stop = groups(root, "Stop")
        #expect(stop.count == 1)
        #expect(command(ofGroup: stop.first ?? [:]) == "say done")
        #expect((root["hooks"] as? [String: Any])?["SessionStart"] == nil)
        #expect(try installer().status() == .notInstalled)
    }

    @Test func removeKeepsUserHookSharingAGroupWithOurs() throws {
        let group: [String: Any] = ["hooks": [
            ["type": "command", "command": "say done"],
            ["type": "command", "command": HookSnippet.command, "timeout": 5],
        ]]
        let data = try JSONSerialization.data(withJSONObject: ["hooks": ["Stop": [group]]])
        try data.write(to: settings)
        try installer().remove()
        let stop = groups(try json(), "Stop")
        #expect(stop.count == 1)
        #expect((stop.first?["hooks"] as? [[String: Any]])?.count == 1)
        #expect(command(ofGroup: stop.first ?? [:]) == "say done")
    }

    @Test func removeWithNothingInstalledChangesNothing() throws {
        #expect(try installer().remove() == .unchanged)
        #expect(!FileManager.default.fileExists(atPath: settings.path))
        let text = "{\"model\": \"opus\"}"
        try write(text)
        #expect(try installer().remove() == .unchanged)
        #expect(try read() == text)
        #expect(try backups().isEmpty)
    }

    @Test func partialInstallIsDetectedAndCompleted() throws {
        try installer().install()
        var root = try json()
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        hooks.removeValue(forKey: "Notification")
        hooks.removeValue(forKey: "Stop")
        root["hooks"] = hooks
        try JSONSerialization.data(withJSONObject: root).write(to: settings)
        #expect(try installer().status() == .partial(installed: 6, total: 8))
        try installer().install()
        #expect(try installer().status() == .installed)
    }
}
