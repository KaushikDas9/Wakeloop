import Foundation

public struct FileStamp: Equatable {
    public var path: String
    public var modified: Date
    public init(path: String, modified: Date) { self.path = path; self.modified = modified }
}

/// Fallback for agents without hooks: a transcript file written to in the last few seconds means a session is active.
/// Reads modification times only, never file contents.
public enum SessionFiles {
    public static func recentlyActive(_ stamps: [FileStamp], now: Date = Date(), window: TimeInterval = 20) -> [FileStamp] {
        stamps.filter { now.timeIntervalSince($0.modified) <= window && $0.modified <= now.addingTimeInterval(5) }
    }

    /// Claude Code: ~/.claude/projects/<project>/<session>.jsonl.
    /// Codex: ~/.codex/sessions/YYYY/MM/DD/*.jsonl, today and yesterday only so a midnight rollover is covered.
    /// Bounded on purpose: this runs every few seconds.
    public static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser, now: Date = Date()) -> [FileStamp] {
        var out: [FileStamp] = []
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]

        func collect(_ dir: URL) {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return }
            for url in items where url.pathExtension == "jsonl" {
                if let m = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                    out.append(FileStamp(path: url.path, modified: m))
                }
            }
        }

        let projects = home.appendingPathComponent(".claude/projects")
        if let dirs = try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) {
            for d in dirs where (try? d.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { collect(d) }
        }

        let cal = Calendar.current
        for offset in [0, -1] {
            guard let day = cal.date(byAdding: .day, value: offset, to: now) else { continue }
            let c = cal.dateComponents([.year, .month, .day], from: day)
            let dir = home.appendingPathComponent(".codex/sessions")
                .appendingPathComponent(String(format: "%04d/%02d/%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0))
            collect(dir)
        }
        return out
    }
}
