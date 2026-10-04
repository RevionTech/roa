import XCTest
import Darwin
@testable import ROAMac

final class BoundedProcessTests: XCTestCase {
    func testImmediateExitIsNotMissed() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try BoundedProcess.run(process)
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testTimeoutTerminatesProcess() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["10"]
        XCTAssertThrowsError(try BoundedProcess.run(process, timeout: 0.05)) { error in
            guard case SleepControllerError.timeout = error else { return XCTFail("Unexpected error") }
        }
        XCTAssertFalse(process.isRunning)
    }

    func testTimeoutKillsProcessIgnoringTermination() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "trap '' TERM; exec /bin/sleep 10"]
        XCTAssertThrowsError(try BoundedProcess.run(process, timeout: 0.1))
        XCTAssertFalse(process.isRunning)
        XCTAssertEqual(process.terminationReason, .uncaughtSignal)
        XCTAssertEqual(process.terminationStatus, SIGKILL)
    }
}
