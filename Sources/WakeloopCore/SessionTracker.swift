import Foundation

public enum AgentState: Equatable {
    case working
    case waiting(since: Date)
    case idle
}

public enum AgentEvent: Equatable {
    case sessionStart, promptSubmit, stop, sessionEnd
    case needsInput          // permission_prompt, idle_prompt, agent_needs_input
    case other
}

/// Pure state engine: tracks per-session state and decides whether to hold the Mac awake.
public struct SessionTracker {
    public var gracePeriod: TimeInterval
    public private(set) var sessions: [String: AgentState] = [:]

    public init(gracePeriod: TimeInterval = 300) {
        self.gracePeriod = gracePeriod
    }

    public mutating func apply(_ event: AgentEvent, session: String, at now: Date = Date()) {
        switch event {
        case .sessionStart, .stop: sessions[session] = .idle
        case .promptSubmit: sessions[session] = .working
        case .needsInput: sessions[session] = .waiting(since: now)
        case .sessionEnd: sessions[session] = nil
        case .other: break
        }
    }

    public func shouldHold(at now: Date = Date()) -> Bool {
        sessions.values.contains { state in
            switch state {
            case .working: return true
            case .waiting(let since): return now.timeIntervalSince(since) < gracePeriod
            case .idle: return false
            }
        }
    }

    /// Sessions currently between a prompt and its Stop.
    public var workingCount: Int { sessions.values.filter { $0 == .working }.count }

    /// Human-readable reason, for the future "why is my Mac awake" panel.
    public func reason(at now: Date = Date()) -> String {
        let working = workingCount
        if working > 0 { return "\(working) agent session(s) working" }
        if shouldHold(at: now) { return "Waiting for you (grace period)" }
        return "No active work"
    }
}
