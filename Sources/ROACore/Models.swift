import Foundation

public enum ROAConstants {
    public static let version = "0.2.3"
    public static let batteryFloor = 20
    public static let dataRoot = "/var/db/net.reviontech.roa"
    public static let runtimeRoot = "/var/run/net.reviontech.roa"
}

/// New identifiers distinguish an explicit re-arm from a stale ON request.
public struct ModeRequest: Codable, Equatable {
    public let schema: Int
    public let id: UUID
    public let enabled: Bool

    public init(enabled: Bool, id: UUID = UUID()) {
        schema = 1
        self.id = id
        self.enabled = enabled
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

    public init(requestID: UUID?, desired: Bool, phase: ModePhase, reason: String,
                sleepDisabled: Bool?, batteryPercent: Int?, thermal: Int) {
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
        guard let request, request.schema == 1, !request.enabled else { return false }
        return request.id != requestID
    }
}

public struct GuardRecord: Codable, Equatable {
    public let trip: GuardTrip?
    public let controllerFault: ControllerFault?

    // Optional fault keeps existing guard records readable during upgrades.
    public init(trip: GuardTrip?, controllerFault: ControllerFault? = nil) {
        self.trip = trip
        self.controllerFault = controllerFault
    }
}
