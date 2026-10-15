import Foundation
import IOKit.ps

public struct PowerStatus: Equatable {
    public var batteryPercent: Int?   // nil on desktops
    public var onAC: Bool
    public var thermalHot: Bool
    public init(batteryPercent: Int?, onAC: Bool, thermalHot: Bool) {
        self.batteryPercent = batteryPercent; self.onAC = onAC; self.thermalHot = thermalHot
    }
}

public enum GuardVerdict: Equatable {
    case allowed
    case lowBattery
    case tooHot
    case holdTimedOut
}

/// Maximum time an automatic hold may last without agent activity. Any hook event or transcript write restarts
/// the timer. Once it trips, the hold stays released until new activity arrives, so a stuck agent cannot re-engage it.
public struct HoldCap {
    /// nil means Off.
    public var limit: TimeInterval?
    private var quietSince: Date
    private var tripped = false

    public init(limit: TimeInterval? = 8 * 3600, since now: Date = Date()) {
        self.limit = limit
        self.quietSince = now
    }

    /// Call on every hook event and on every transcript write seen by the app.
    public mutating func activity(at now: Date = Date()) {
        quietSince = now
        tripped = false
    }

    /// True when the hold must be released. The quiet timer only runs while `holding` is true, so it starts when a hold starts.
    public mutating func tripped(holding: Bool, at now: Date = Date()) -> Bool {
        guard let limit else { tripped = false; return false }
        if !holding {
            if !tripped { quietSince = now }
            return false
        }
        if !tripped && now.timeIntervalSince(quietSince) >= limit { tripped = true }
        return tripped
    }
}

/// Safety cutoffs: always allow sleep on low battery (with hysteresis) or high heat.
public struct SafetyGuard {
    public var batteryFloor: Int
    public var batteryResume: Int
    private var batteryTripped = false

    public init(batteryFloor: Int = 20, batteryResume: Int = 25) {
        self.batteryFloor = batteryFloor
        self.batteryResume = batteryResume
    }

    public mutating func evaluate(_ s: PowerStatus) -> GuardVerdict {
        if s.thermalHot { return .tooHot }
        guard !s.onAC, let level = s.batteryPercent else {
            batteryTripped = false
            return .allowed
        }
        if level <= batteryFloor { batteryTripped = true }
        else if batteryTripped && level >= batteryResume { batteryTripped = false }
        return batteryTripped ? .lowBattery : .allowed
    }
}

/// Extra rule for lid-closed mode, the riskiest case: charger only, unless the user allows battery, and then
/// only above a higher floor than the general battery guard.
public struct LidGuard {
    public var batteryFloor: Int
    public var batteryResume: Int
    private var tripped = false

    public init(batteryFloor: Int = 30, batteryResume: Int = 35) {
        self.batteryFloor = batteryFloor
        self.batteryResume = batteryResume
    }

    /// True when lid-closed mode may stay on.
    public mutating func allows(_ s: PowerStatus, batteryAllowed: Bool) -> Bool {
        guard !s.onAC, let level = s.batteryPercent else { tripped = false; return true }
        guard batteryAllowed else { return false }
        if level <= batteryFloor { tripped = true }
        else if tripped && level >= batteryResume { tripped = false }
        return !tripped
    }
}

public enum SystemPower {
    public static func read() -> PowerStatus {
        var percent: Int?
        var onAC = true
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for ps in list {
                guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                      d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
                percent = d[kIOPSCurrentCapacityKey] as? Int
                onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            }
        }
        let state = ProcessInfo.processInfo.thermalState
        return PowerStatus(batteryPercent: percent, onAC: onAC, thermalHot: state == .serious || state == .critical)
    }
}
