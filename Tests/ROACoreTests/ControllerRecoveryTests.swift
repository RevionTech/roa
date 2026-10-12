import XCTest
@testable import ROACore

final class ControllerRecoveryTests: XCTestCase {
    func testRetryUsesLatestOffAndSafetyDecisions() {
        let request = ModeRequest(enabled: true, duration: 60, chargingOnly: true,
                                  bootSessionID: "boot", startedAtUptime: 100)
        let healthy = SafetySample(batteryPercent: 100, onBattery: false, thermal: 0,
                                   ownerAtConsole: true)
        let hot = SafetySample(batteryPercent: 100, onBattery: false, thermal: 2,
                               ownerAtConsole: true)
        let unplugged = SafetySample(batteryPercent: 100, onBattery: true, thermal: 0,
                                     ownerAtConsole: true)
        let switchedUser = SafetySample(batteryPercent: 100, onBattery: false, thermal: 0,
                                        ownerAtConsole: false)
        let cases: [(ModeRequest?, SafetySample, Double, String)] = [
            (ModeRequest(enabled: false), healthy, 101, "boot"),
            (nil, healthy, 101, "boot"),
            (request, hot, 101, "boot"),
            (request, unplugged, 101, "boot"),
            (request, switchedUser, 101, "boot"),
            (request, healthy, 160, "boot"),
            (request, healthy, 101, "new-boot")
        ]
        for (latestRequest, sample, uptime, boot) in cases {
            var policy = SafetyPolicy()
            var recovery = ControllerRecovery()
            let initial = policy.evaluate(request: request, sample: healthy,
                                          currentBootSessionID: "boot", currentUptime: 100,
                                          requireBootSession: true)
            XCTAssertTrue(recovery.target(for: initial))
            recovery.failed(isTimeout: true, sleepDisabled: false, requestID: request.id)
            let latest = policy.evaluate(request: latestRequest, sample: sample,
                                         currentBootSessionID: boot, currentUptime: uptime,
                                         requireBootSession: true)
            XCTAssertTrue(recovery.retryPending)
            XCTAssertFalse(recovery.target(for: latest))
            recovery.confirmed() // Fresh observation confirmed the OFF target.
            XCTAssertFalse(recovery.target(for: latest))
            XCTAssertNil(recovery.fault)
        }
    }

    func testTransientTimeoutRecoversWithoutNewRequest() {
        let request = ModeRequest(enabled: true)
        var recovery = ControllerRecovery()
        recovery.failed(isTimeout: true, sleepDisabled: false, requestID: request.id)
        XCTAssertTrue(recovery.retryPending)
        XCTAssertNotNil(recovery.fault)
        recovery.acknowledge(request)
        XCTAssertTrue(recovery.permitsControl)
        recovery.confirmed()
        XCTAssertNil(recovery.fault)
        XCTAssertFalse(recovery.retryPending)
    }

    func testThreeConsecutiveTimeoutsRequireExplicitOff() {
        let request = ModeRequest(enabled: true)
        var recovery = ControllerRecovery()
        for attempt in 1...3 {
            recovery.failed(isTimeout: true, sleepDisabled: false, requestID: request.id)
            XCTAssertEqual(recovery.retryPending, attempt < 3)
        }
        XCTAssertFalse(recovery.permitsControl)
        // A successful OFF observation or another ON cannot bypass the fault.
        recovery.confirmed()
        recovery.acknowledge(ModeRequest(enabled: true))
        XCTAssertFalse(recovery.permitsControl)
        recovery.acknowledge(ModeRequest(enabled: false))
        XCTAssertNil(recovery.fault)
        XCTAssertTrue(recovery.permitsControl)
    }

    func testUnconfirmedReleaseAndOtherErrorsNeverRetry() {
        for (timeout, actual) in [(true, nil), (true, true), (false, false)] as [(Bool, Bool?)] {
            var recovery = ControllerRecovery()
            recovery.failed(isTimeout: timeout, sleepDisabled: actual, requestID: UUID())
            XCTAssertFalse(recovery.retryPending)
            XCTAssertFalse(recovery.permitsControl)
            // A later transient error cannot downgrade the permanent fault.
            recovery.failed(isTimeout: true, sleepDisabled: false, requestID: UUID())
            XCTAssertFalse(recovery.permitsControl)
        }
    }

    func testSuccessRestoresRetryBudget() {
        var recovery = ControllerRecovery()
        let id = UUID()
        for _ in 0..<4 {
            recovery.failed(isTimeout: true, sleepDisabled: false, requestID: id)
            recovery.failed(isTimeout: true, sleepDisabled: false, requestID: id)
            XCTAssertTrue(recovery.retryPending)
            recovery.confirmed()
            XCTAssertNil(recovery.fault)
        }
    }

    func testPendingRetryIsPersistedAsFaultAndCannotRearmAfterRestart() throws {
        let request = ModeRequest(enabled: true)
        var recovery = ControllerRecovery()
        recovery.failed(isTimeout: true, sleepDisabled: false, requestID: request.id)
        let record = GuardRecord(trip: nil, controllerFault: recovery.fault)
        let restored = try JSONDecoder().decode(GuardRecord.self, from: JSONEncoder().encode(record))
        var restarted = ControllerRecovery(restoring: restored.controllerFault)
        restarted.acknowledge(request)
        XCTAssertFalse(restarted.retryPending)
        XCTAssertFalse(restarted.permitsControl)
        restarted.acknowledge(ModeRequest(enabled: false))
        XCTAssertTrue(restarted.permitsControl)
    }

    func testStorageFaultCancelsPendingRetry() {
        var recovery = ControllerRecovery()
        recovery.failed(isTimeout: true, sleepDisabled: false, requestID: UUID())
        let storageFault = ControllerFault(reason: "Status publishing failed", requestID: UUID())
        recovery.latch(storageFault)
        XCTAssertFalse(recovery.retryPending)
        XCTAssertFalse(recovery.permitsControl)
        recovery.confirmed()
        XCTAssertEqual(recovery.fault, storageFault)
    }

    func testSameFailedOffDoesNotResetRetryBudget() {
        let request = ModeRequest(enabled: false)
        var recovery = ControllerRecovery()
        for _ in 0..<3 {
            recovery.failed(isTimeout: true, sleepDisabled: false, requestID: request.id)
            recovery.acknowledge(request)
        }
        XCTAssertFalse(recovery.permitsControl)
        recovery.acknowledge(ModeRequest(enabled: false))
        XCTAssertTrue(recovery.permitsControl)
    }

    func testStatusRetryFlagIsOptionalAndRoundTrips() throws {
        for retrying in [nil, true] as [Bool?] {
            let status = ServiceStatus(requestID: UUID(), desired: true, phase: .error,
                                       reason: "test", sleepDisabled: false, batteryPercent: 100,
                                       thermal: 0, retryingSleepControl: retrying)
            let encoded = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(ServiceStatus.self, from: encoded)
            XCTAssertEqual(decoded.retryingSleepControl, retrying)
            if retrying == nil {
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
                XCTAssertNil(object["retryingSleepControl"])
            }
        }
    }
}
