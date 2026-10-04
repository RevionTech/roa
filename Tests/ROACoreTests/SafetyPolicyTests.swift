import XCTest
@testable import ROACore

final class SafetyPolicyTests: XCTestCase {
    private func sample(_ percent: Int? = 80, battery: Bool? = true,
                        thermal: Int = 0, loggedIn: Bool = true) -> SafetySample {
        SafetySample(batteryPercent: percent, onBattery: battery,
                     thermal: thermal, ownerAtConsole: loggedIn)
    }

    func testLowBatteryBoundaryAndACBehavior() {
        var policy = SafetyPolicy()
        XCTAssertTrue(policy.evaluate(request: ModeRequest(enabled: true), sample: sample(21)).allowSleepOverride)
        XCTAssertFalse(policy.evaluate(request: ModeRequest(enabled: true), sample: sample(20)).allowSleepOverride)
        XCTAssertTrue(policy.evaluate(request: ModeRequest(enabled: true), sample: sample(10, battery: false)).allowSleepOverride)
    }

    func testThermalTripCannotAutomaticallyRearm() {
        var policy = SafetyPolicy()
        let on = ModeRequest(enabled: true)
        XCTAssertEqual(policy.evaluate(request: on, sample: sample(thermal: 2)).phase, .blocked)
        XCTAssertEqual(policy.evaluate(request: on, sample: sample()).phase, .blocked)
        XCTAssertEqual(policy.evaluate(request: ModeRequest(enabled: true), sample: sample()).phase, .active)
    }

    func testUnknownTelemetryFailsClosedAndLatches() {
        var policy = SafetyPolicy()
        let on = ModeRequest(enabled: true)
        XCTAssertFalse(policy.evaluate(request: on, sample: sample(nil, battery: nil)).allowSleepOverride)
        XCTAssertFalse(policy.evaluate(request: on, sample: sample()).allowSleepOverride)
        XCTAssertFalse(policy.evaluate(request: ModeRequest(enabled: true), sample: sample(101)).allowSleepOverride)
    }

    func testLogoutReleasesAndLoginRestoresDesiredState() {
        var policy = SafetyPolicy()
        let on = ModeRequest(enabled: true)
        XCTAssertTrue(policy.evaluate(request: on, sample: sample()).allowSleepOverride)
        XCTAssertFalse(policy.evaluate(request: on, sample: sample(loggedIn: false)).allowSleepOverride)
        XCTAssertTrue(policy.evaluate(request: on, sample: sample()).allowSleepOverride)
    }

    func testOffClearsLatchAndMissingRequestReleases() {
        var policy = SafetyPolicy()
        _ = policy.evaluate(request: ModeRequest(enabled: true), sample: sample(thermal: 3))
        XCTAssertEqual(policy.evaluate(request: ModeRequest(enabled: false), sample: sample()).phase, .off)
        XCTAssertEqual(policy.evaluate(request: nil, sample: sample()).phase, .off)
    }

    func testPersistedRequestCanRestoreAfterReboot() throws {
        let original = ModeRequest(enabled: true)
        let restored = try JSONDecoder().decode(ModeRequest.self, from: JSONEncoder().encode(original))
        var restartedPolicy = SafetyPolicy()
        XCTAssertEqual(original, restored)
        XCTAssertTrue(restartedPolicy.evaluate(request: restored, sample: sample()).allowSleepOverride)
    }

    func testSafetyLatchSurvivesServiceRestartAndUnreadableRequest() throws {
        let request = ModeRequest(enabled: true)
        var first = SafetyPolicy()
        _ = first.evaluate(request: request, sample: sample(20))
        let encoded = try JSONEncoder().encode(GuardRecord(trip: first.guardTrip))
        let record = try JSONDecoder().decode(GuardRecord.self, from: encoded)
        var restarted = SafetyPolicy(restoring: record.trip)
        _ = restarted.evaluate(request: nil, sample: sample())
        XCTAssertEqual(restarted.evaluate(request: request, sample: sample()).phase, .blocked)
        XCTAssertEqual(restarted.evaluate(request: ModeRequest(enabled: true), sample: sample()).phase, .active)
    }

    func testInvalidThermalTelemetryLatchesUntilExplicitRearm() {
        for thermal in [-1, 4] {
            var policy = SafetyPolicy()
            let request = ModeRequest(enabled: true)
            XCTAssertFalse(policy.evaluate(request: request, sample: sample(thermal: thermal)).allowSleepOverride)
            XCTAssertFalse(policy.evaluate(request: request, sample: sample()).allowSleepOverride)
            XCTAssertTrue(policy.evaluate(request: ModeRequest(enabled: true), sample: sample()).allowSleepOverride)
        }
    }

    func testGuardRecordUpgradePreservesControllerFault() throws {
        let legacy = try JSONDecoder().decode(GuardRecord.self, from: Data("{}".utf8))
        XCTAssertNil(legacy.controllerFault)
        let failedOff = ModeRequest(enabled: false)
        let fault = GuardRecord(trip: nil, controllerFault:
            ControllerFault(reason: "Sleep control failed", requestID: failedOff.id))
        let restored = try JSONDecoder().decode(GuardRecord.self, from: JSONEncoder().encode(fault))
        XCTAssertEqual(restored, fault)
        let restoredFault = try XCTUnwrap(restored.controllerFault)
        XCTAssertFalse(restoredFault.permitsRecovery(request: failedOff))
        XCTAssertFalse(restoredFault.permitsRecovery(request: nil))
        XCTAssertFalse(restoredFault.permitsRecovery(request: ModeRequest(enabled: true)))
        XCTAssertTrue(restoredFault.permitsRecovery(request: ModeRequest(enabled: false)))
    }

    func testInvalidRequestSchemaDoesNotClearSafetyLatch() throws {
        var policy = SafetyPolicy()
        let request = ModeRequest(enabled: true)
        _ = policy.evaluate(request: request, sample: sample(20))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        json["schema"] = 2
        json["enabled"] = false
        let invalid = try JSONDecoder().decode(ModeRequest.self, from: JSONSerialization.data(withJSONObject: json))
        let fault = ControllerFault(reason: "failed", requestID: request.id)
        XCTAssertFalse(fault.permitsRecovery(request: invalid))
        XCTAssertFalse(policy.evaluate(request: invalid, sample: sample()).allowSleepOverride)
        XCTAssertEqual(policy.evaluate(request: request, sample: sample()).phase, .blocked)
    }

    func testStatusRejectsStaleAndFutureHeartbeat() {
        let status = ServiceStatus(requestID: nil, desired: true, phase: .active,
                                   reason: "test", sleepDisabled: true, batteryPercent: 80, thermal: 0)
        XCTAssertTrue(status.isFresh(at: status.updatedAt.addingTimeInterval(1)))
        XCTAssertFalse(status.isFresh(at: status.updatedAt.addingTimeInterval(9)))
        XCTAssertFalse(status.isFresh(at: status.updatedAt.addingTimeInterval(-3)))
    }
}
