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

    public mutating func evaluate(request: ModeRequest?, sample: SafetySample) -> ModeDecision {
        guard let request, request.schema == 1 else {
            // A transient unreadable file releases power but must not erase a trip.
            return ModeDecision(allowSleepOverride: false, phase: .off, reason: "ROA is off: no valid request")
        }
        if request.id != seenRequest {
            seenRequest = request.id
            latchedReason = nil
        }
        guard request.enabled else {
            latchedReason = nil
            return ModeDecision(allowSleepOverride: false, phase: .off, reason: "ROA is off")
        }
        // Logout / fast user switching pauses without consuming the user's choice.
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
