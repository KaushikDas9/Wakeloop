import Foundation

public struct ProcInfo: Equatable {
    public var pid: Int32
    public var ppid: Int32
    public var cpu: Double
    public var name: String   // basename of the executable
    public init(pid: Int32, ppid: Int32, cpu: Double, name: String) {
        self.pid = pid; self.ppid = ppid; self.cpu = cpu; self.name = name
    }
}

/// Fallback signal for work the hooks cannot see: a long build, test run or background job
/// started by an agent. Looks for agent processes with busy descendants.
public enum ProcessTree {
    public static let agentNames: Set<String> = ["claude", "codex"]

    /// Parses `ps -axo pid=,ppid=,pcpu=,comm=`. The command may contain spaces, so only the first three fields are split.
    public static func parse(_ output: String) -> [ProcInfo] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = Int32(parts[0]), let ppid = Int32(parts[1]), let cpu = Double(parts[2]) else { return nil }
            let name = String(parts[3]).split(separator: "/").last.map(String.init) ?? String(parts[3])
            return ProcInfo(pid: pid, ppid: ppid, cpu: cpu, name: name)
        }
    }

    /// Descendants of any agent process that are using at least `cpuThreshold` percent CPU.
    /// Idle children (for example long-lived MCP servers) are ignored on purpose.
    public static func busyAgentDescendants(_ procs: [ProcInfo], cpuThreshold: Double = 3.0) -> [ProcInfo] {
        var children: [Int32: [ProcInfo]] = [:]
        for p in procs { children[p.ppid, default: []].append(p) }
        var busy: [ProcInfo] = []
        var seen = Set<Int32>()
        for agent in procs where agentNames.contains(agent.name.lowercased()) {
            var stack = children[agent.pid] ?? []
            while let p = stack.popLast() {
                guard seen.insert(p.pid).inserted else { continue }   // also guards against pid cycles
                if p.cpu >= cpuThreshold && !agentNames.contains(p.name.lowercased()) { busy.append(p) }
                stack.append(contentsOf: children[p.pid] ?? [])
            }
        }
        return busy
    }

    public static func snapshot() -> [ProcInfo] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "pid=,ppid=,pcpu=,comm="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return parse(String(decoding: data, as: UTF8.self))
    }
}
