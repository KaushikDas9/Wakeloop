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

/// Pure state engine: tracks per-session state and decides whether to hold the Mac awake.
public struct SessionTracker {
    public var gracePeriod: TimeInterval
    public private(set) var sessions: [String: AgentState] = [:]
    public private(set) var names: [String: String] = [:]
    /// Running sub-agents per session: agent id -> (type, started). They keep working after the parent's Stop.
    public private(set) var subagents: [String: [String: (type: String, since: Date)]] = [:]
    /// A SubagentStop that never arrives must not hold the Mac awake forever.
    public static let subagentExpiry: TimeInterval = 3600

    public init(gracePeriod: TimeInterval = 300) {
        self.gracePeriod = gracePeriod
    }

    public mutating func apply(_ event: AgentEvent, session: String, cwd: String? = nil, at now: Date = Date()) {
        if let cwd, !cwd.isEmpty { names[session] = (cwd as NSString).lastPathComponent }
        switch event {
        case .sessionStart, .stop: sessions[session] = .idle
        case .promptSubmit: sessions[session] = .working
        case .needsInput: sessions[session] = .waiting(since: now)
        case .sessionEnd: sessions[session] = nil; names[session] = nil; subagents[session] = nil
        case .subagentStart(let id, let type): subagents[session, default: [:]][id] = (type, now)
        case .subagentStop(let id):
            subagents[session]?[id] = nil
            if subagents[session]?.isEmpty == true { subagents[session] = nil }
        case .other: break
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

    /// Human-readable reason, for the future "why is my Mac awake" panel.
    public func reason(at now: Date = Date()) -> String {
        let working = workingCount
        if working > 0 { return "\(working) agent(s) working" }
        if shouldHold(at: now) { return "Waiting for you (grace period)" }
        return "No active work"
    }
}
