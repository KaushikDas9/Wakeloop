import Testing
import Foundation
@testable import WakeloopCore

struct SessionFilesTests {
    let now = Date(timeIntervalSince1970: 2_000_000)

    @Test func onlyRecentlyWrittenFilesCount() {
        let stamps = [
            FileStamp(path: "fresh", modified: now.addingTimeInterval(-5)),
            FileStamp(path: "stale", modified: now.addingTimeInterval(-300)),
        ]
        #expect(SessionFiles.recentlyActive(stamps, now: now).map(\.path) == ["fresh"])
    }

    @Test func futureTimestampsAreIgnored() {
        let stamps = [FileStamp(path: "odd", modified: now.addingTimeInterval(3600))]
        #expect(SessionFiles.recentlyActive(stamps, now: now).isEmpty)
    }

    @Test func scanFindsClaudeAndCodexTranscripts() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("wl-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let cal = Calendar.current
        let c = cal.dateComponents([.year, .month, .day], from: Date())
        let claudeDir = home.appendingPathComponent(".claude/projects/proj")
        let codexDir = home.appendingPathComponent(".codex/sessions").appendingPathComponent(String(format: "%04d/%02d/%02d", c.year!, c.month!, c.day!))
        for dir in [claudeDir, codexDir] { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        try Data().write(to: claudeDir.appendingPathComponent("a.jsonl"))
        try Data().write(to: codexDir.appendingPathComponent("b.jsonl"))
        try Data().write(to: claudeDir.appendingPathComponent("ignore.txt"))
        let found = SessionFiles.scan(home: home).map { URL(fileURLWithPath: $0.path).lastPathComponent }.sorted()
        #expect(found == ["a.jsonl", "b.jsonl"])
    }
}
