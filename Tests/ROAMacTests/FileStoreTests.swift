import XCTest
import Darwin
@testable import ROAMac
import ROACore

final class FileStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testAtomicRoundTripAndRejectSymlink() throws {
        let path = directory.appendingPathComponent("request.json").path
        let request = ModeRequest(enabled: true)
        try FileStore.write(request, path: path, permissions: 0o600)
        XCTAssertEqual(try FileStore.read(ModeRequest.self, path: path, owner: getuid()), request)
        let link = directory.appendingPathComponent("link.json").path
        XCTAssertEqual(symlink(path, link), 0)
        XCTAssertThrowsError(try FileStore.read(ModeRequest.self, path: link, owner: getuid()))
    }

    func testRejectWrongOwnerOversizedAndWritableData() throws {
        let path = directory.appendingPathComponent("request.json").path
        try FileStore.write(ModeRequest(enabled: true), path: path, permissions: 0o600)
        XCTAssertThrowsError(try FileStore.read(ModeRequest.self, path: path, owner: getuid() + 1))
        XCTAssertEqual(chmod(path, 0o666), 0)
        XCTAssertThrowsError(try FileStore.read(ModeRequest.self, path: path, owner: getuid()))
        try Data(repeating: 65, count: 8193).write(to: URL(fileURLWithPath: path))
        XCTAssertEqual(chmod(path, 0o600), 0)
        XCTAssertThrowsError(try FileStore.read(ModeRequest.self, path: path, owner: getuid()))
    }

    func testOversizedWritePreservesExistingRecord() throws {
        let path = directory.appendingPathComponent("request.json").path
        let request = ModeRequest(enabled: false)
        try FileStore.write(request, path: path, permissions: 0o600)
        XCTAssertThrowsError(try FileStore.write(String(repeating: "x", count: 8193), path: path, permissions: 0o600))
        XCTAssertEqual(try FileStore.read(ModeRequest.self, path: path, owner: getuid()), request)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["request.json"])
    }

    func testRejectFIFOWithoutBlocking() {
        let path = directory.appendingPathComponent("fifo").path
        XCTAssertEqual(mkfifo(path, 0o600), 0)
        XCTAssertThrowsError(try FileStore.read(ModeRequest.self, path: path, owner: getuid()))
    }

    func testPowerStateParser() {
        XCTAssertEqual(SleepController.parseSleepDisabled(" SleepDisabled 1\nCurrently in use:\n sleep 0\n"), true)
        XCTAssertEqual(SleepController.parseSleepDisabled("SleepDisabled 0\n"), false)
        XCTAssertNil(SleepController.parseSleepDisabled(" sleep 0\n"))
        XCTAssertNil(SleepController.parseSleepDisabled("SleepDisabled invalid\n"))
    }

    func testBootIdentityAndContinuousClockAreStable() throws {
        let identity = try XCTUnwrap(BootSession.currentID())
        XCTAssertNotNil(UUID(uuidString: identity))
        XCTAssertEqual(BootSession.currentID(), identity)
        let before = BootSession.elapsedTime()
        XCTAssertTrue(before.isFinite)
        XCTAssertGreaterThanOrEqual(before, 0)
        XCTAssertGreaterThanOrEqual(BootSession.elapsedTime(), before)
    }

    func testSessionRequestStoresVerifiedBootAndContinuousClock() throws {
        let path = directory.appendingPathComponent("request.json").path
        let store = FileStore(owner: getuid(), requestPath: path,
                              statusPath: directory.appendingPathComponent("status.json").path)
        let before = BootSession.elapsedTime()
        let request = try store.setEnabled(true, duration: 120, chargingOnly: true)
        XCTAssertEqual(request.bootSessionID, BootSession.currentID())
        XCTAssertEqual(request.duration, 120)
        XCTAssertTrue(request.chargingOnly)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(request.startedAtUptime), before)
        XCTAssertLessThanOrEqual(try XCTUnwrap(request.startedAtUptime), BootSession.elapsedTime())
        XCTAssertEqual(store.request(), request)
        let off = try store.setEnabled(false, duration: 120, chargingOnly: true)
        XCTAssertFalse(off.enabled)
        XCTAssertFalse(off.chargingOnly)
        XCTAssertNil(off.duration)
        XCTAssertNil(off.bootSessionID)
        XCTAssertNil(off.startedAtUptime)
    }

    func testInvalidDurationCannotReplaceExistingRequest() throws {
        let path = directory.appendingPathComponent("request.json").path
        let store = FileStore(owner: getuid(), requestPath: path,
                              statusPath: directory.appendingPathComponent("status.json").path)
        let original = try store.setEnabled(false)
        for duration in [59.0, 86401, .infinity, .nan] {
            XCTAssertThrowsError(try store.setEnabled(true, duration: duration))
            XCTAssertEqual(store.request(), original)
        }
    }
}
