import XCTest
import ROACore
@testable import ROAMac

final class SessionPresentationTests: XCTestCase {
    func testCountdownBoundariesAndInvalidInputs() {
        XCTAssertEqual(SessionPresentation.countdown(59.2), "01:00")
        XCTAssertEqual(SessionPresentation.countdown(3600), "1:00:00")
        XCTAssertEqual(SessionPresentation.countdown(86400), "24:00:00")
        for invalid in [-1.0, .nan, .infinity, 86401] {
            XCTAssertEqual(SessionPresentation.countdown(invalid), "—")
        }
    }

    func testBlockedOnRequestOffersExplicitRearmAndStaleStatusNeverClaimsActive() {
        let request = ModeRequest(enabled: true)
        let status = ServiceStatus(requestID: request.id, desired: true, phase: .blocked,
                                   reason: "Battery safety stop", sleepDisabled: false, batteryPercent: 20, thermal: 0)
        XCTAssertFalse(SessionPresentation.shouldTurnOff(status: status, request: request))
        XCTAssertNil(SessionPresentation.confirmed(status, at: status.updatedAt.addingTimeInterval(9)))
        let report = SessionPresentation.diagnostics(status, at: status.updatedAt.addingTimeInterval(9))
        XCTAssertTrue(report.contains("Sleep: Unconfirmed"))
        XCTAssertFalse(report.contains(request.id.uuidString))
        XCTAssertFalse(report.contains("Battery: 20%"))
    }

    func testIncompatibleServiceAllowsOffRecoveryButCannotConfirmAnActiveTimer() throws {
        let request = ModeRequest(enabled: true)
        let status = ServiceStatus(requestID: request.id, desired: true, phase: .active,
                                   reason: "ROA is on", sleepDisabled: true, batteryPercent: 80, thermal: 0,
                                   remainingSeconds: 60)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(status)) as? [String: Any])
        json["version"] = "0.2.3"
        let incompatible = try JSONDecoder().decode(ServiceStatus.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(SessionPresentation.confirmed(incompatible))
        XCTAssertTrue(SessionPresentation.shouldTurnOff(status: incompatible, request: request))
        let report = SessionPresentation.diagnostics(incompatible)
        XCTAssertTrue(report.contains("No confirmed timer"))
        XCTAssertTrue(report.contains("Sleep: Unconfirmed"))
    }
}
