import Foundation
import Darwin

/// Wait for process exit events rather than polling with coalesced background sleeps.
/// Executable selection remains the caller's responsibility (SleepController uses pmset only).
enum BoundedProcess {
    static func run(_ process: Process, timeout: TimeInterval = 3) throws {
        let completed = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completed.signal() }
        try process.run()
        if completed.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if completed.wait(timeout: .now() + .milliseconds(100)) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
            }
            process.waitUntilExit()
            throw SleepControllerError.timeout
        }
        process.waitUntilExit()
    }
}
