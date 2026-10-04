import Foundation

/// Safety trips latch until a NEW explicit request. Cooling down alone never re-arms.
public struct SafetyPolicy {
    private var seenRequest: UUID?
    private var latchedReason: String?

    public init(restoring trip: GuardTrip? = nil) {
        seenRequest = trip?.requestID
        latchedReason = trip?.reason
    }

    public var guardTrip: GuardTrip? {
        guard let id = seenRequest, let reason = latchedReason else { return nil }
        return GuardTrip(requestID: id, reason: reason)
    }

    /// Legacy callers may omit boot observations; the privileged service must require them.
    public mutating func evaluate(request: ModeRequest?, sample: SafetySample,
                                  currentBootSessionID: String? = nil,
                                  currentUptime: TimeInterval? = nil,
                                  requireBootSession: Bool = false) -> ModeDecision {
        guard let request else {
            // A transient unreadable file releases power but must not erase a trip.
            return ModeDecision(allowSleepOverride: false, phase: .off, reason: "ROA is off: no valid request")
        }
        guard request.isSupported else {
            return ModeDecision(allowSleepOverride: false, phase: request.enabled ? .blocked : .off,
                                reason: "Request version is unsupported; turn OFF, then ON using current ROA")
        }
        if request.id != seenRequest {
            seenRequest = request.id
            latchedReason = nil
        }
        guard request.enabled else {
            latchedReason = nil
            return ModeDecision(allowSleepOverride: false, phase: .off, reason: "ROA is off")
        }
        // Boot, timer and AC-only stops also apply while the owner is logged out.
        if latchedReason == nil {
            if requireBootSession || currentBootSessionID != nil || currentUptime != nil {
                if currentBootSessionID == nil || currentBootSessionID?.isEmpty == true {
                    latchedReason = "Boot session is unavailable; turn ON to start a new session"
                } else if request.bootSessionID == nil || request.bootSessionID != currentBootSessionID {
                    latchedReason = "Session ended: restart requires an explicit ON request"
                } else if let now = currentUptime, let start = request.startedAtUptime,
                          now.isFinite, start.isFinite, start >= 0, now >= start {
                    // The request is bound to the current boot and a valid monotonic start.
                } else {
                    latchedReason = "Session timing is unavailable or invalid; turn ON to retry"
                }
            }
            if latchedReason == nil, let duration = request.duration {
                if !ModeRequest.isValidDuration(duration) {
                    latchedReason = "Session duration is invalid"
                } else if let now = currentUptime, let start = request.startedAtUptime,
                          now.isFinite, start.isFinite, start >= 0, now >= start {
                    if now - start >= duration { latchedReason = "Session ended" }
                } else {
                    latchedReason = "Session timing is unavailable or invalid; turn ON to retry"
                }
            }
            if latchedReason == nil && request.chargingOnly {
                if sample.onBattery == true {
                    latchedReason = "Charging-only stop: external power disconnected"
                } else if sample.onBattery == nil {
                    latchedReason = "Charging-only stop: external power information is unavailable"
                }
            }
        }
        if let reason = latchedReason {
            return ModeDecision(allowSleepOverride: false, phase: .blocked, reason: reason)
        }
        // Logout / fast user switching pauses a valid session without resetting its timer.
        guard sample.ownerAtConsole else {
            return ModeDecision(allowSleepOverride: false, phase: .blocked, reason: "Paused: installing account is not active")
        }
        if latchedReason == nil {
            if !(0...3).contains(sample.thermal) {
                latchedReason = "Thermal information is invalid"
            } else if sample.thermal >= 2 {
                latchedReason = "Safety stop: high thermal pressure"
            } else if sample.onBattery == nil || sample.batteryPercent == nil {
                latchedReason = "Battery information is unavailable"
            } else if let percent = sample.batteryPercent, !(0...100).contains(percent) {
                latchedReason = "Battery information is invalid"
            } else if sample.onBattery == true, let percent = sample.batteryPercent,
                      percent <= ROAConstants.batteryFloor {
                latchedReason = "Safety stop: battery is at \(ROAConstants.batteryFloor)% or lower"
            }
        }
        if let reason = latchedReason {
            return ModeDecision(allowSleepOverride: false, phase: .blocked, reason: reason)
        }
        return ModeDecision(allowSleepOverride: true, phase: .active, reason: "ROA is active")
    }
}
