import Foundation
import ROACore

public enum SessionPresentation {
    public static func confirmed(_ status: ServiceStatus?, at now: Date = Date()) -> ServiceStatus? {
        guard let status, status.isFresh(at: now), status.version == ROAConstants.version else { return nil }
        return status
    }

    public static func shouldTurnOff(status: ServiceStatus?, request: ModeRequest?) -> Bool {
        request?.enabled == true && confirmed(status)?.phase != .blocked
    }

    public static func countdown(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0, seconds <= 86400 else { return "—" }
        let value = Int(ceil(seconds))
        return value >= 3600
            ? String(format: "%d:%02d:%02d", value / 3600, (value % 3600) / 60, value % 60)
            : String(format: "%02d:%02d", value / 60, value % 60)
    }

    public static func diagnostics(_ status: ServiceStatus?, at now: Date = Date()) -> String {
        let confirmed = confirmed(status, at: now)
        let heartbeat = status.map { String(format: "%.1f seconds ago", now.timeIntervalSince($0.updatedAt)) } ?? "Unavailable"
        let battery = confirmed?.batteryPercent.map { "\($0)%" } ?? "Unknown"
        let power = confirmed?.onBattery.map { $0 ? "Battery" : "Power adapter" } ?? "Unknown"
        let sleep = confirmed?.sleepDisabled.map { $0 ? "Disabled (ROA on)" : "Enabled (ROA off)" } ?? "Unconfirmed"
        let thermal = confirmed.map { ["Nominal", "Fair", "Serious", "Critical"].indices.contains($0.thermal)
            ? ["Nominal", "Fair", "Serious", "Critical"][$0.thermal] : "Unknown" } ?? "Unknown"
        let remaining = confirmed?.remainingSeconds.map(countdown) ?? "No confirmed timer"
        // Fixed fields omit account names, file paths, request IDs and notification credentials.
        return """
        ROA Diagnostics
        App version: \(ROAConstants.version)
        Service version: \(status?.version ?? "Unavailable")
        Service heartbeat: \(heartbeat)
        Service confirmation: \(confirmed == nil ? "Unavailable or incompatible" : "Current")
        Sleep: \(sleep)
        Battery: \(battery)
        Power source: \(power)
        Thermal state: \(thermal)
        Remaining time: \(remaining)
        Status: \(confirmed?.reason ?? "Service unavailable")
        Last stop: \(confirmed?.lastStopReason ?? "None recorded")
        """
    }
}
