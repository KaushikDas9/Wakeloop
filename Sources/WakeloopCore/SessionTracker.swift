import Foundation

public enum AgentState: Equatable {
    case working
    case waiting(since: Date)
    case idle
}

public enum AgentEvent: Equatable {
    case sessionStart, promptSubmit, stop, sessionEnd
    case needsInput          // permission_prompt, idle_prompt, agent_needs_input
    case subagentStart(id: String, type: String)
    case subagentStop(id: String)
    case other
}

/// One project's working state: its main session and the rows for its live sub-agents.
public struct WorkerGroup: Equatable {
    public let project: String
    public let mainWorking: Bool
    /// Each sub-agent type once ("Explore ×3" when repeated), capped; a final "… and N more" row when cut.
    public let subagents: [String]
    /// Live sub-agents across all rows, before collapsing and capping.
    public let subagentTotal: Int
}

/// Shortens `s` to at most `max` characters, ending with "…" when cut.
public func truncated(_ s: String, max: Int = 40) -> String {
    guard s.count > max else { return s }
    return max > 1 ? String(s.prefix(max - 1)) + "…" : "…"
}

/// Pure state engine: tracks per-session state and decides whether to hold the Mac awake.
public struct SessionTracker {
    public var gracePeriod: TimeInterval
    public private(set) var sessions: [String: AgentState] = [:]
    public private(set) var names: [String: String] = [:]
    private var transcripts: [String: String] = [:]
    /// Running sub-agents per session: agent id -> (type, started). They keep working after the parent's Stop.
    public private(set) var subagents: [String: [String: (type: String, since: Date)]] = [:]
    /// A SubagentStop that never arrives must not hold the Mac awake forever.
    public static let subagentExpiry: TimeInterval = 3600

    public init(gracePeriod: TimeInterval = 300) {
        self.gracePeriod = gracePeriod
    }

    public mutating func apply(_ event: AgentEvent, session: String, cwd: String? = nil, transcript: String? = nil, at now: Date = Date()) {
        if let transcript, !transcript.isEmpty { transcripts[session] = transcript }
        if let cwd, !cwd.isEmpty { names[session] = (cwd as NSString).lastPathComponent }
        switch event {
        case .sessionStart, .stop: sessions[session] = .idle
        case .promptSubmit: sessions[session] = .working
        case .needsInput: sessions[session] = .waiting(since: now)
        case .sessionEnd: sessions[session] = nil; names[session] = nil; subagents[session] = nil; transcripts[session] = nil
        case .subagentStart(let id, let type): subagents[session, default: [:]][id] = (type, now)
        case .subagentStop(let id):
            subagents[session]?[id] = nil
            if subagents[session]?.isEmpty == true { subagents[session] = nil }
        case .other: break
        }
    }

    /// Where Claude Code writes a sub-agent's transcript: next to the session transcript, under `<session>/subagents/`.
    func subagentTranscript(session: String, id: String) -> String? {
        guard let t = transcripts[session], t.hasSuffix(".jsonl") else { return nil }
        return String(t.dropLast(".jsonl".count)) + "/subagents/agent-\(id).jsonl"
    }

    /// Drops sub-agents whose transcript has not been written for `staleAfter` seconds. A killed sub-agent never
    /// sends SubagentStop. A missing file keeps the agent (the 1 hour expiry still applies).
    public mutating func pruneStaleSubagents(staleAfter: TimeInterval = 180, at now: Date = Date(), lastWrite: (String) -> Date?) {
        for (session, agents) in subagents {
            for id in agents.keys {
                guard let path = subagentTranscript(session: session, id: id), let written = lastWrite(path),
                      now.timeIntervalSince(written) > staleAfter else { continue }
                subagents[session]?[id] = nil
            }
            if subagents[session]?.isEmpty == true { subagents[session] = nil }
        }
    }

    private func liveSubagents(at now: Date) -> [(session: String, type: String)] {
        subagents.flatMap { session, agents in
            agents.values.filter { now.timeIntervalSince($0.since) < Self.subagentExpiry }.map { (session, $0.type) }
        }
    }

    public func shouldHold(at now: Date = Date()) -> Bool {
        if !liveSubagents(at: now).isEmpty { return true }
        return sessions.values.contains { state in
            switch state {
            case .working: return true
            case .waiting(let since): return now.timeIntervalSince(since) < gracePeriod
            case .idle: return false
            }
        }
    }

    /// Working sessions (between a prompt and its Stop) plus running sub-agents, each counted as a worker.
    public var workingCount: Int { workingNames.count }

    private func label(_ session: String) -> String { names[session] ?? String(session.prefix(8)) }

    /// Worker labels, sorted: project names, and "project > subagent (type)" for sub-agents.
    public var workingNames: [String] {
        let now = Date()
        let mains = sessions.filter { $0.value == .working }.map { label($0.key) }
        let subs = liveSubagents(at: now).map { "\(label($0.session)) > subagent (\($0.type))" }
        return (mains + subs).sorted()
    }

    public var workingGroups: [WorkerGroup] { groups() }

    /// One group per project label with a working main session or live sub-agents, sorted by project.
    public func groups(maxSubagentRows: Int = 10, at now: Date = Date()) -> [WorkerGroup] {
        var workingMains = Set<String>()
        for (session, state) in sessions where state == .working { workingMains.insert(truncated(label(session))) }
        var agents: [String: [String]] = [:]
        for sub in liveSubagents(at: now) {
            agents[truncated(label(sub.session)), default: []].append(truncated(sub.type))
        }
        return workingMains.union(agents.keys).sorted().map { project in
            let mine = agents[project] ?? []
            let kinds = mine.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }.sorted { $0.key < $1.key }
            var rows = kinds.prefix(Swift.max(0, maxSubagentRows)).map { $0.value > 1 ? "\($0.key) ×\($0.value)" : $0.key }
            let hidden = kinds.dropFirst(Swift.max(0, maxSubagentRows)).reduce(0) { $0 + $1.value }
            if hidden > 0 { rows.append("… and \(hidden) more") }
            return WorkerGroup(project: project, mainWorking: workingMains.contains(project), subagents: rows, subagentTotal: mine.count)
        }
    }

    /// Human-readable reason, for the future "why is my Mac awake" panel.
    public func reason(at now: Date = Date()) -> String {
        let working = workingCount
        if working > 0 { return "\(working) agent(s) working" }
        if shouldHold(at: now) { return "Waiting for you (will sleep soon)" }
        return "No active work"
    }
}
