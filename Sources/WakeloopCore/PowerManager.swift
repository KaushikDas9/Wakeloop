import Foundation
import IOKit.pwr_mgt

/// Holds an IOKit idle-sleep assertion. Does NOT keep a lid-closed Mac awake (see docs/architecture/lid-closed.md).
public final class PowerManager {
    private var assertionID: IOPMAssertionID = 0
    public private(set) var isHolding = false

    public init() {}

    public func setHold(_ hold: Bool, reason: String = "Wakeloop: agent working") {
        if hold && !isHolding {
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason as CFString,
                &assertionID)
            isHolding = (result == kIOReturnSuccess)
        } else if !hold && isHolding {
            IOPMAssertionRelease(assertionID)
            isHolding = false
        }
    }

    deinit { setHold(false) }
}
