import Foundation
import Darwin

public enum SleepControllerError: Error {
    case commandFailed, timeout, unknownState
}

/// Fixed executable and fixed arguments. Never runs a shell or user-provided code.
public struct SleepController {
    public init() {}

    private func run(_ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin", "LC_ALL": "C"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.1)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw SleepControllerError.timeout
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw SleepControllerError.commandFailed }
        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    public static func parseSleepDisabled(_ output: String) -> Bool? {
        for line in output.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0.isWhitespace })
            if parts.count == 2 && parts[0] == "SleepDisabled" {
                if parts[1] == "1" { return true }
                if parts[1] == "0" { return false }
            }
        }
        return nil
    }

    public func current() throws -> Bool {
        guard let value = Self.parseSleepDisabled(try run(["-g"])) else {
            throw SleepControllerError.unknownState
        }
        return value
    }

    public func setDisabled(_ disabled: Bool) throws {
        _ = try run(["-a", "disablesleep", disabled ? "1" : "0"])
    }
}
