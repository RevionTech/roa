import Foundation
import Darwin
import ROACore
import ROAMac

let store = FileStore(owner: getuid())
let arguments = Array(CommandLine.arguments.dropFirst())
let usage = """
ROA — Run. On. Anywhere.
Usage: roa on | off | toggle | status [--json] | version | help
       roa off --no-wait   (save OFF before starting the service)

ON persists across restarts and resumes after owner login if guards permit.
After a safety stop, run 'roa on' to try again.
Emergency recovery: sudo /usr/bin/pmset -a disablesleep 0
"""

func fail(_ message: String, code: Int32 = 1) -> Never {
    fputs("roa: \(message)\n", stderr)
    exit(code)
}

let command = arguments.first ?? "help"
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
    }
case "on", "off", "toggle":
    let noWait = arguments == ["off", "--no-wait"]
    guard arguments.count == 1 || noWait else { fail(usage, code: 64) }
    let enabled = command == "toggle" ? !(store.request()?.enabled ?? false) : command == "on"
    do {
        let request = try store.setEnabled(enabled)
        if noWait {
            print("ROA: OFF request saved; service confirmation was not requested.")
            exit(0)
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 12
        while ProcessInfo.processInfo.systemUptime < deadline {
            if let status = store.status(), status.isFresh(), status.requestID == request.id {
                print("ROA: \(status.phase.rawValue.uppercased()) — \(status.reason)")
                guard status.version == ROAConstants.version, status.phase == (enabled ? .active : .off), status.sleepDisabled == enabled else {
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
