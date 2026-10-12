import Foundation

/// Retry transient power timeouts only after normal sleep has been confirmed.
/// Persist `fault`, but never persist permission to retry across a service restart.
public struct ControllerRecovery {
    public private(set) var fault: ControllerFault?
    public private(set) var retryPending = false
    private var consecutiveTimeouts = 0

    public init(restoring fault: ControllerFault? = nil) {
        self.fault = fault
    }

    public var permitsControl: Bool { fault == nil || retryPending }

    public func target(for decision: ModeDecision) -> Bool {
        decision.allowSleepOverride && permitsControl
    }

    public mutating func acknowledge(_ request: ModeRequest?) {
        if fault?.permitsRecovery(request: request) == true {
            fault = nil
            retryPending = false
            consecutiveTimeouts = 0
        }
    }

    public mutating func latch(_ fault: ControllerFault) {
        self.fault = fault
        retryPending = false
        consecutiveTimeouts = 0
    }

    public mutating func failed(isTimeout: Bool, sleepDisabled: Bool?, requestID: UUID?) {
        // An existing permanent fault must never become automatically recoverable.
        guard permitsControl else { return }
        consecutiveTimeouts += 1
        retryPending = isTimeout && sleepDisabled == false && consecutiveTimeouts <= 2
        fault = ControllerFault(
            reason: isTimeout ? "Sleep control timed out; turn OFF, then ON to retry"
                              : "Sleep control failed; turn OFF, then ON to retry",
            requestID: requestID)
    }

    /// Call only after a fresh observation confirms the latest policy's target.
    public mutating func confirmed() {
        if retryPending { fault = nil }
        retryPending = false
        consecutiveTimeouts = 0
    }
}
