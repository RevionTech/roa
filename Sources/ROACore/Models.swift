import Foundation

public enum ROAConstants {
    public static let version = "0.3.2"
    public static let batteryFloor = 20
    public static let dataRoot = "/var/db/net.reviontech.roa"
    public static let runtimeRoot = "/var/run/net.reviontech.roa"
}

/// New identifiers distinguish an explicit re-arm from a stale ON request.
public struct ModeRequest: Codable, Equatable {
    public let schema: Int
    public let id: UUID
    public let enabled: Bool
    public let duration: TimeInterval?
    private let storedChargingOnly: Bool?
    public var chargingOnly: Bool { storedChargingOnly ?? false }
    public let bootSessionID: String?
    /// Kernel continuous elapsed time at creation, including time spent asleep.
    public let startedAtUptime: TimeInterval?

    private enum CodingKeys: String, CodingKey {
        case schema, id, enabled, duration, bootSessionID, startedAtUptime
        case storedChargingOnly = "chargingOnly"
    }

    public init(enabled: Bool, id: UUID = UUID(), duration: TimeInterval? = nil,
                chargingOnly: Bool = false, bootSessionID: String? = nil,
                startedAtUptime: TimeInterval? = nil) {
        // Older services must reject ON rather than silently ignore its safety options.
        schema = 2
        self.id = id
        self.enabled = enabled
        self.duration = duration
        storedChargingOnly = chargingOnly
        self.bootSessionID = bootSessionID
        self.startedAtUptime = startedAtUptime
    }

    public static func isValidDuration(_ duration: TimeInterval) -> Bool {
        duration.isFinite && (60...86400).contains(duration)
    }

    /// Legacy OFF remains available for migration and emergency recovery.
    public var isSupported: Bool { schema == 2 || (schema == 1 && !enabled) }

    /// Only the service's current boot and monotonic observation confirm a timer.
    public func remainingSeconds(currentBootSessionID: String?, currentUptime: TimeInterval) -> TimeInterval? {
        guard isSupported, enabled, let duration, Self.isValidDuration(duration),
              let bootSessionID, !bootSessionID.isEmpty, bootSessionID == currentBootSessionID,
              let startedAtUptime, startedAtUptime.isFinite, startedAtUptime >= 0,
              currentUptime.isFinite, currentUptime >= startedAtUptime else { return nil }
        return max(0, duration - (currentUptime - startedAtUptime))
    }
}

public enum ModePhase: String, Codable {
    case off, active, blocked, error
}

public struct ServiceStatus: Codable {
    public let schema: Int
    public let version: String
    public let updatedAt: Date
    public let requestID: UUID?
    public let desired: Bool
    public let phase: ModePhase
    public let reason: String
    public let sleepDisabled: Bool?
    public let batteryPercent: Int?
    public let thermal: Int
    public let onBattery: Bool?
    public let remainingSeconds: TimeInterval?
    public let lastStopReason: String?

    public init(requestID: UUID?, desired: Bool, phase: ModePhase, reason: String,
                sleepDisabled: Bool?, batteryPercent: Int?, thermal: Int,
                onBattery: Bool? = nil, remainingSeconds: TimeInterval? = nil,
                lastStopReason: String? = nil) {
        schema = 1
        version = ROAConstants.version
        updatedAt = Date()
        self.requestID = requestID
        self.desired = desired
        self.phase = phase
        self.reason = reason
        self.sleepDisabled = sleepDisabled
        self.batteryPercent = batteryPercent
        self.thermal = thermal
        self.onBattery = onBattery
        self.remainingSeconds = remainingSeconds
        self.lastStopReason = lastStopReason
    }

    public func isFresh(at now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(updatedAt)
        return schema == 1 && age >= -2 && age <= 8
    }
}

public struct SafetySample {
    public let batteryPercent: Int?
    public let onBattery: Bool?
    public let thermal: Int
    public let ownerAtConsole: Bool

    public init(batteryPercent: Int?, onBattery: Bool?, thermal: Int, ownerAtConsole: Bool) {
        self.batteryPercent = batteryPercent
        self.onBattery = onBattery
        self.thermal = thermal
        self.ownerAtConsole = ownerAtConsole
    }
}

public struct ModeDecision: Equatable {
    public let allowSleepOverride: Bool
    public let phase: ModePhase
    public let reason: String
}

public struct GuardTrip: Codable, Equatable {
    public let requestID: UUID
    public let reason: String
}

/// A fault is acknowledged only by an OFF request made after the failure.
public struct ControllerFault: Codable, Equatable {
    public let reason: String
    public let requestID: UUID?

    public init(reason: String, requestID: UUID?) {
        self.reason = reason
        self.requestID = requestID
    }

    public func permitsRecovery(request: ModeRequest?) -> Bool {
        guard let request, request.isSupported, !request.enabled else { return false }
        return request.id != requestID
    }
}

public struct GuardRecord: Codable, Equatable {
    public let trip: GuardTrip?
    public let controllerFault: ControllerFault?
    public let lastStopReason: String?

    // Optional fault keeps existing guard records readable during upgrades.
    public init(trip: GuardTrip?, controllerFault: ControllerFault? = nil,
                lastStopReason: String? = nil) {
        self.trip = trip
        self.controllerFault = controllerFault
        self.lastStopReason = lastStopReason
    }
}
