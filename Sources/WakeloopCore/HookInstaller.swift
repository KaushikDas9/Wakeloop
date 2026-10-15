import Foundation

/// Adds and removes Wakeloop's hooks in an agent's hooks file: `~/.claude/settings.json` for Claude Code,
/// `~/.codex/hooks.json` for Codex. Other hooks and settings are kept, and their order is kept. A backup is written
/// before any change. Invalid JSON and read-only files are refused, never overwritten.
public struct HookInstaller {
    public enum Status: Equatable {
        case notInstalled
        case partial(installed: Int, total: Int)
        case installed
    }

    /// `.changed` carries the backup file written before the change.
    public enum Outcome: Equatable {
        case changed(backup: URL?)
        case unchanged
    }

    public enum Failure: Error, LocalizedError {
        case invalidJSON(path: String)
        case unexpectedShape(path: String)
        case readOnly(path: String)
        case readFailed(String)
        case writeFailed(String)

        public var errorDescription: String? {
            switch self {
            case .invalidJSON(let path):
                return "\(path) is not valid JSON, so Wakeloop left it alone. Fix or move the file, then try again."
            case .unexpectedShape(let path):
                return "\(path) has a hooks setting in a shape Wakeloop does not recognize, so it was left alone."
            case .readOnly(let path):
                return "\(path) is read-only, so Wakeloop cannot add or remove hooks. Make it writable and try again."
            case .readFailed(let detail), .writeFailed(let detail):
                return detail
            }
        }
    }

    public let settingsURL: URL
    /// The events Wakeloop manages in this file, and the timeout written to each entry.
    public let events: [String]
    public let timeout: Int
    private let now: () -> Date

    public init(settingsURL: URL = HookInstaller.defaultSettingsURL,
                events: [String] = HookSnippet.claudeEvents,
                timeout: Int = HookSnippet.claudeTimeout,
                now: @escaping () -> Date = { Date() }) {
        self.settingsURL = settingsURL
        self.events = events
        self.timeout = timeout
        self.now = now
    }

    /// The installer for Codex's `~/.codex/hooks.json`.
    public static func codex(settingsURL: URL = HookInstaller.defaultCodexURL, now: @escaping () -> Date = { Date() }) -> HookInstaller {
        HookInstaller(settingsURL: settingsURL, events: HookSnippet.codexEvents, timeout: HookSnippet.codexTimeout, now: now)
    }

    public static var defaultSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    public static var defaultCodexURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/hooks.json")
    }

    public func status() throws -> Status {
        let (root, _) = try readSettings()
        let hooks = try hooksDictionary(root)
        var installed = 0
        for event in events where try groups(in: hooks, event: event).contains(where: Self.containsOurs) {
            installed += 1
        }
        let total = events.count
        if installed == 0 { return .notInstalled }
        return installed == total ? .installed : .partial(installed: installed, total: total)
    }

    /// Adds Wakeloop's group to each event that lacks it. Running it again changes nothing.
    @discardableResult
    public func install() throws -> Outcome {
        let (original, data) = try readSettingsWithData()
        var root = original
        var hooks = try hooksDictionary(root)
        var changed = false
        for event in events {
            var groups = try groups(in: hooks, event: event)
            if groups.contains(where: Self.containsOurs) { continue }
            groups.append(HookSnippet.group(timeout: timeout))
            hooks[event] = groups
            changed = true
        }
        guard changed else { return .unchanged }
        root["hooks"] = hooks
        return .changed(backup: try write(root, original: data))
    }

    /// Removes only Wakeloop's hook entries. A group that also holds other hooks keeps them.
    @discardableResult
    public func remove() throws -> Outcome {
        let (original, data) = try readSettingsWithData()
        var root = original
        var hooks = try hooksDictionary(root)
        var changed = false
        for event in events {
            let groups = try groups(in: hooks, event: event)
            guard groups.contains(where: Self.containsOurs) else { continue }
            changed = true
            let kept = groups.compactMap(Self.removingOurs)
            if kept.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = kept }
        }
        guard changed else { return .unchanged }
        if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        return .changed(backup: try write(root, original: data))
    }

    // MARK: - Reading

    /// The parsed settings and the raw bytes. A missing file is an empty object with no bytes; a blank file is an
    /// empty object whose bytes are still backed up before a change.
    private func readSettingsWithData() throws -> ([String: Any], Data?) {
        let path = settingsURL.path
        guard FileManager.default.fileExists(atPath: path) else { return ([:], nil) }
        let data: Data
        do {
            data = try Data(contentsOf: settingsURL)
        } catch {
            throw Failure.readFailed("Could not read \(path): \(error.localizedDescription)")
        }
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D }) { return ([:], data) }
        guard let parsed = try? JSONSerialization.jsonObject(with: data) else { throw Failure.invalidJSON(path: path) }
        guard let root = parsed as? [String: Any] else { throw Failure.unexpectedShape(path: path) }
        return (root, data)
    }

    private func readSettings() throws -> ([String: Any], Data?) { try readSettingsWithData() }

    private func hooksDictionary(_ root: [String: Any]) throws -> [String: Any] {
        guard let value = root["hooks"] else { return [:] }
        guard let hooks = value as? [String: Any] else { throw Failure.unexpectedShape(path: settingsURL.path) }
        return hooks
    }

    private func groups(in hooks: [String: Any], event: String) throws -> [Any] {
        guard let value = hooks[event] else { return [] }
        guard let groups = value as? [Any] else { throw Failure.unexpectedShape(path: settingsURL.path) }
        return groups
    }

    // MARK: - Matching our entries

    private static func isOurHook(_ hook: Any) -> Bool {
        (hook as? [String: Any])?["command"] as? String == HookSnippet.command
    }

    private static func containsOurs(_ group: Any) -> Bool {
        ((group as? [String: Any])?["hooks"] as? [Any])?.contains(where: isOurHook) ?? false
    }

    /// The group without Wakeloop's hook, or nil when nothing else is left in it.
    private static func removingOurs(_ group: Any) -> Any? {
        guard containsOurs(group), var dict = group as? [String: Any], let inner = dict["hooks"] as? [Any] else { return group }
        let rest = inner.filter { !isOurHook($0) }
        if rest.isEmpty { return nil }
        dict["hooks"] = rest
        return dict
    }

    // MARK: - Writing

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    /// Backs up the original bytes, then replaces the file atomically. Keeps the file's permissions.
    private func write(_ root: [String: Any], original: Data?) throws -> URL? {
        let target = settingsURL.resolvingSymlinksInPath()
        let fm = FileManager.default
        let attributes = try? fm.attributesOfItem(atPath: target.path)
        if fm.fileExists(atPath: target.path), !fm.isWritableFile(atPath: target.path) {
            throw Failure.readOnly(path: settingsURL.path)
        }
        var backup: URL?
        do {
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let original {
                let url = backupURL(for: target)
                try original.write(to: url, options: .withoutOverwriting)
                backup = url
            }
            var data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .withoutEscapingSlashes])
            data.append(0x0A)
            try data.write(to: target, options: .atomic)
            if let permissions = attributes?[.posixPermissions] {
                try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path)
            }
        } catch {
            throw Failure.writeFailed("Could not update \(settingsURL.path): \(error.localizedDescription)")
        }
        return backup
    }

    /// settings.json.wakeloop-backup-20261015-143022, with a numbered suffix if that name is taken.
    private func backupURL(for file: URL) -> URL {
        let stamp = Self.stampFormatter.string(from: now())
        let base = file.deletingLastPathComponent()
        var candidate = base.appendingPathComponent("\(file.lastPathComponent).wakeloop-backup-\(stamp)")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = base.appendingPathComponent("\(file.lastPathComponent).wakeloop-backup-\(stamp)-\(n)")
            n += 1
        }
        return candidate
    }
}
