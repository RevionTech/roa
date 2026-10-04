import Foundation
import ROACore

/// Notifications describe observed transitions, never historical startup state.
public struct NotificationPolicy {
    private var observedActive = false
    private var lastFreshActive: Date?
    private var lastEvent: Date?
    private var initialized = false
    private var seenRequest: UUID?

    public init() {}

    public mutating func observe(status: ServiceStatus?, request: ModeRequest?, at now: Date = Date()) -> String? {
        let newRequest = initialized && request?.id != seenRequest
        initialized = true
        seenRequest = request?.id
        // An explicit OFF wins over a still-fresh acknowledgement of the old ON.
        if request?.enabled == false {
            observedActive = false
            lastFreshActive = nil
            return nil
        }
        if newRequest, request?.enabled == true {
            observedActive = true
            lastFreshActive = now
        }
        let fresh = status?.isFresh(at: now) == true && status?.version == ROAConstants.version &&
            status?.requestID == request?.id
        if fresh, let status {
            if status.phase == .active && status.sleepDisabled == true {
                observedActive = true
                lastFreshActive = now
                return nil
            }
            guard observedActive else { return nil }
            if status.phase == .off || request?.enabled == false {
                observedActive = false
                lastFreshActive = nil
                return nil
            }
            // A user switch is a temporary pause, not a safety incident.
            if status.reason.hasPrefix("Paused:") { return nil }
            if status.phase == .blocked || status.phase == .error {
                observedActive = false
                lastFreshActive = nil
                return event("ROA stopped: \(status.reason)", at: now)
            }
            return nil
        }
        guard observedActive, let lastFreshActive, now.timeIntervalSince(lastFreshActive) > 8 else { return nil }
        observedActive = false
        self.lastFreshActive = nil
        return event("ROA service is unavailable. Sleep prevention could not be confirmed; check Status & Diagnostics.", at: now)
    }

    private mutating func event(_ message: String, at now: Date) -> String? {
        // A flapping service can recover without flooding either channel.
        if let lastEvent, now.timeIntervalSince(lastEvent) < 30 { return nil }
        lastEvent = now
        return message
    }
}
