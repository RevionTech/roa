import Foundation
import Darwin
import ROACore
import ROAMac

let store = FileStore(owner: getuid())
let arguments = Array(CommandLine.arguments.dropFirst())
let usage = """
ROA — Run. On. Anywhere.
Usage: roa on [--minutes N | --hours N] [--charging-only]
       roa off | toggle | status [--json] | version | help
       roa off --no-wait   (save OFF before starting the service)

Durations range from 1 minute to 24 hours. Without a duration, ON has no timer.
ON survives service restarts in the current boot; reboot always requires a new ON.
The timer continues while the app is closed or the owner is logged out.
--charging-only stops and latches if external power is disconnected.
After a safety stop or an ended session, run 'roa on' to try again.
Emergency recovery: sudo /usr/bin/pmset -a disablesleep 0
"""

func fail(_ message: String, code: Int32 = 1) -> Never {
    fputs("roa: \(message)\n", stderr)
    exit(code)
}

let command = arguments.first ?? "help"

func onOptions(_ options: ArraySlice<String>) -> (duration: TimeInterval?, chargingOnly: Bool) {
    var duration: TimeInterval?
    var chargingOnly = false
    var iterator = options.makeIterator()
    while let option = iterator.next() {
        switch option {
        case "--charging-only":
            guard !chargingOnly else { fail(usage, code: 64) }
            chargingOnly = true
        case "--minutes", "--hours":
            guard duration == nil, let value = iterator.next(),
                  value.range(of: #"^(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+)$"#,
                              options: .regularExpression) != nil,
                  let number = Double(value), number.isFinite else { fail(usage, code: 64) }
            let seconds = number * (option == "--minutes" ? 60 : 3600)
            guard ModeRequest.isValidDuration(seconds) else {
                fail("Session duration must be between 1 minute and 24 hours.", code: 64)
            }
            duration = seconds
        default: fail(usage, code: 64)
        }
    }
    return (duration, chargingOnly)
}

switch command {
case "help", "--help", "-h":
    guard arguments.count <= 1 else { fail(usage, code: 64) }
    print(usage)
case "version", "--version":
    guard arguments.count == 1 else { fail(usage, code: 64) }
    print(ROAConstants.version)
case "status":
    guard arguments.count == 1 || arguments == ["status", "--json"] else { fail(usage, code: 64) }
    guard let status = store.status(), status.isFresh(), status.version == ROAConstants.version else {
        fail("Service status is unavailable or stale. Check installation / launchd.")
    }
    if arguments.last == "--json" {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do { print(String(decoding: try encoder.encode(status), as: UTF8.self)) }
        catch { fail(error.localizedDescription) }
    } else {
        print("ROA \(ROAConstants.version)  |  Service \(status.version)")
        print("Requested: \(status.desired ? "ON" : "OFF")  |  Effective: \(status.phase.rawValue.uppercased())")
        print("\(status.reason)")
        print("Sleep disabled: \(status.sleepDisabled.map { String($0) } ?? "unknown")")
        print("Battery: \(status.batteryPercent.map { "\($0)%" } ?? "unknown")  |  Thermal: \(status.thermal)")
        print("Power: \(status.onBattery.map { $0 ? "battery" : "external power" } ?? "unknown")")
        if let remaining = status.remainingSeconds, remaining.isFinite, remaining >= 0 {
            print("Remaining: \(Int(ceil(remaining))) seconds (service confirmed)")
        }
        if let lastStopReason = status.lastStopReason { print("Last stop: \(lastStopReason)") }
    }
case "on", "off", "toggle":
    let noWait = arguments == ["off", "--no-wait"]
    let options: (duration: TimeInterval?, chargingOnly: Bool)
    if command == "on" {
        options = onOptions(arguments.dropFirst())
    } else {
        guard arguments.count == 1 || noWait else { fail(usage, code: 64) }
        options = (nil, false)
    }
    let enabled = command == "toggle" ? !(store.request()?.enabled ?? false) : command == "on"
    if enabled {
        guard let status = store.status(), status.isFresh(), status.version == ROAConstants.version else {
            fail("A matching, running ROA service is required before turning ON. Check installation / launchd.")
        }
    }
    do {
        let request = try store.setEnabled(enabled, duration: options.duration,
                                           chargingOnly: options.chargingOnly)
        if noWait {
            print("ROA: OFF request saved; service confirmation was not requested.")
            exit(0)
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 12
        while ProcessInfo.processInfo.systemUptime < deadline {
            if let status = store.status(), status.isFresh(), status.requestID == request.id {
                print("ROA: \(status.phase.rawValue.uppercased()) — \(status.reason)")
                guard !enabled || status.version == ROAConstants.version,
                      status.phase == (enabled ? .active : .off), status.sleepDisabled == enabled else {
                    fail("Request acknowledged, but the requested power state is not active.", code: 2)
                }
                exit(0)
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        fail("Request saved, but the service did not confirm it in time. Run 'roa status'.")
    } catch { fail(error.localizedDescription) }
default: fail(usage, code: 64)
}
