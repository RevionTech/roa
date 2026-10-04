import Foundation
import IOKit.ps
import SystemConfiguration
import ROACore

public enum PowerMonitor {
    public static func sample(owner: uid_t) -> SafetySample {
        var percent: Int?
        var onBattery: Bool?
        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                      description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                      let current = description[kIOPSCurrentCapacityKey] as? Int,
                      let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0,
                      let state = description[kIOPSPowerSourceStateKey] as? String else { continue }
                percent = Int(Double(current) / Double(maximum) * 100)
                if state == kIOPSBatteryPowerValue { onBattery = true }
                if state == kIOPSACPowerValue { onBattery = false }
                break
            }
        }
        var consoleUID: uid_t = 0
        var consoleGID: gid_t = 0
        let consoleName = SCDynamicStoreCopyConsoleUser(nil, &consoleUID, &consoleGID) as String?
        return SafetySample(batteryPercent: percent, onBattery: onBattery,
                            thermal: ProcessInfo.processInfo.thermalState.rawValue,
                            ownerAtConsole: consoleUID == owner && consoleName != nil && consoleName != "loginwindow")
    }
}
