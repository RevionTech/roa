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

    func testPersistedRequestIsRejectedAfterReboot() throws {
        let original = ModeRequest(enabled: true, bootSessionID: "previous-boot", startedAtUptime: 100)
        let restored = try JSONDecoder().decode(ModeRequest.self, from: JSONEncoder().encode(original))
        var restartedPolicy = SafetyPolicy()
        XCTAssertEqual(original, restored)
        XCTAssertFalse(restartedPolicy.evaluate(request: restored, sample: sample(),
                                               currentBootSessionID: "new-boot", currentUptime: 200,
                                               requireBootSession: true).allowSleepOverride)
    }

    private func timedRequest(duration: TimeInterval = 60, chargingOnly: Bool = false) -> ModeRequest {
        ModeRequest(enabled: true, duration: duration, chargingOnly: chargingOnly,
                    bootSessionID: "test-boot", startedAtUptime: 100)
    }

    private func evaluate(_ policy: inout SafetyPolicy, _ request: ModeRequest,
                          now: TimeInterval, battery: Bool? = false,
                          loggedIn: Bool = true) -> ModeDecision {
        policy.evaluate(request: request, sample: sample(battery: battery, loggedIn: loggedIn),
                        currentBootSessionID: "test-boot", currentUptime: now, requireBootSession: true)
    }

    func testDurationBoundsAndInvalidNumbers() {
        for duration in [60.0, 3600, 86400] { XCTAssertTrue(ModeRequest.isValidDuration(duration)) }
        for duration in [0.0, 59.999, 86400.001, -.infinity, .infinity, .nan] {
            XCTAssertFalse(ModeRequest.isValidDuration(duration))
            var policy = SafetyPolicy()
            XCTAssertEqual(evaluate(&policy, timedRequest(duration: duration), now: 100).phase, .blocked)
        }
    }

    func testTimerExpiresAtBoundaryAndCannotAutomaticallyRearm() {
        let request = timedRequest()
        var policy = SafetyPolicy()
        XCTAssertEqual(evaluate(&policy, request, now: 159.9).phase, .active)
        XCTAssertEqual(request.remainingSeconds(currentBootSessionID: "test-boot", currentUptime: 159), 1)
        XCTAssertEqual(evaluate(&policy, request, now: 160).reason, "Session ended")
        XCTAssertEqual(evaluate(&policy, request, now: 170).phase, .blocked)
        XCTAssertEqual(request.remainingSeconds(currentBootSessionID: "test-boot", currentUptime: 170), 0)
        XCTAssertEqual(evaluate(&policy, timedRequest(), now: 100).phase, .active)
    }

    func testTimerContinuesAcrossDaemonRestartAndOwnerLogout() throws {
        let request = try JSONDecoder().decode(ModeRequest.self, from: JSONEncoder().encode(timedRequest()))
        var first = SafetyPolicy()
        XCTAssertEqual(evaluate(&first, request, now: 120).phase, .active)
        XCTAssertEqual(evaluate(&first, request, now: 130, loggedIn: false).phase, .blocked)
        var restarted = SafetyPolicy(restoring: first.guardTrip)
        XCTAssertEqual(evaluate(&restarted, request, now: 150).phase, .active)
        // The sampled continuous clock advances through sleep as well as awake time.
        XCTAssertEqual(evaluate(&restarted, request, now: 500, loggedIn: false).reason, "Session ended")
        XCTAssertEqual(evaluate(&restarted, request, now: 501).phase, .blocked)
    }

    func testLegacyRequestsAndMissingOrInvalidBootClockFailClosed() throws {
        let oldJSON = "{\"schema\":1,\"id\":\"\(UUID().uuidString)\",\"enabled\":true}"
        let legacy = try JSONDecoder().decode(ModeRequest.self, from: Data(oldJSON.utf8))
        XCTAssertFalse(legacy.chargingOnly)
        var policy = SafetyPolicy()
        XCTAssertEqual(evaluate(&policy, legacy, now: 100).phase, .blocked)
        for now in [99.0, -.infinity, .infinity, .nan] {
            var invalidClockPolicy = SafetyPolicy()
            XCTAssertEqual(evaluate(&invalidClockPolicy, timedRequest(), now: now).phase, .blocked)
            XCTAssertNil(timedRequest().remainingSeconds(currentBootSessionID: "test-boot", currentUptime: now))
        }
        var missingBootPolicy = SafetyPolicy()
        XCTAssertEqual(missingBootPolicy.evaluate(request: timedRequest(), sample: sample(),
                                                  currentUptime: 100, requireBootSession: true).phase, .blocked)
        XCTAssertEqual(missingBootPolicy.evaluate(request: ModeRequest(enabled: false), sample: sample(),
                                                  requireBootSession: true).phase, .off)
    }

    func testChargingOnlyStopsLatchUntilNewRequestAndDefaultAllowsBattery() {
        var policy = SafetyPolicy()
        let request = timedRequest(chargingOnly: true)
        XCTAssertEqual(evaluate(&policy, request, now: 100).phase, .active)
        XCTAssertEqual(evaluate(&policy, request, now: 101, battery: true).phase, .blocked)
        XCTAssertEqual(evaluate(&policy, request, now: 102).phase, .blocked)
        XCTAssertEqual(evaluate(&policy, timedRequest(chargingOnly: true), now: 103).phase, .active)
        XCTAssertEqual(evaluate(&policy, timedRequest(), now: 104, battery: true).phase, .active)
        XCTAssertEqual(evaluate(&policy, timedRequest(chargingOnly: true), now: 105, battery: nil).phase, .blocked)
    }

    func testUntimedSessionStillRequiresCurrentBootAndStartObservation() {
        var policy = SafetyPolicy()
        let request = ModeRequest(enabled: true, bootSessionID: "test-boot", startedAtUptime: 100)
        XCTAssertEqual(evaluate(&policy, request, now: 1_000_000).phase, .active)
        XCTAssertNil(request.remainingSeconds(currentBootSessionID: "test-boot", currentUptime: 1_000_000))
        let rebooted = policy.evaluate(request: request, sample: sample(), currentBootSessionID: "new-boot",
                                      currentUptime: 1_000_001, requireBootSession: true)
        XCTAssertEqual(rebooted.phase, .blocked)
        XCTAssertEqual(evaluate(&policy, request, now: 1_000_002).phase, .blocked)
    }

    func testRequestSchemaPreventsOlderServiceFromIgnoringNewSafetyOptions() throws {
        let current = timedRequest(chargingOnly: true)
        XCTAssertEqual(current.schema, 2)
        XCTAssertTrue(current.isSupported)
        // Version 0.2.3 only accepted schema 1. New ON is rejected by that predicate.
        XCTAssertFalse(current.schema == 1)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(current)) as? [String: Any])
        json["schema"] = 1
        let legacyOn = try JSONDecoder().decode(ModeRequest.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(legacyOn.isSupported)
        XCTAssertNil(legacyOn.remainingSeconds(currentBootSessionID: "test-boot", currentUptime: 110))
        var policy = SafetyPolicy()
        XCTAssertEqual(evaluate(&policy, legacyOn, now: 110).phase, .blocked)
        json["enabled"] = false
        json["id"] = UUID().uuidString
        let legacyOff = try JSONDecoder().decode(ModeRequest.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(legacyOff.isSupported)
        XCTAssertEqual(evaluate(&policy, legacyOff, now: 110).phase, .off)
        XCTAssertTrue(ControllerFault(reason: "test fault", requestID: current.id).permitsRecovery(request: legacyOff))
        XCTAssertFalse(ControllerFault(reason: "test fault", requestID: current.id).permitsRecovery(request: legacyOn))
    }

    func testServiceStatusAndLastStopReasonRoundTrip() throws {
        let status = ServiceStatus(requestID: UUID(), desired: true, phase: .blocked,
                                   reason: "Session ended", sleepDisabled: false, batteryPercent: 80,
                                   thermal: 0, onBattery: false, remainingSeconds: 0,
                                   lastStopReason: "Session ended")
        let restored = try JSONDecoder().decode(ServiceStatus.self, from: JSONEncoder().encode(status))
        XCTAssertEqual(restored.remainingSeconds, 0)
        XCTAssertEqual(restored.lastStopReason, "Session ended")
        let record = GuardRecord(trip: nil, lastStopReason: "Session ended")
        XCTAssertEqual(try JSONDecoder().decode(GuardRecord.self, from: JSONEncoder().encode(record)), record)
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
        json["schema"] = 3
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
