import XCTest
import Darwin
@testable import ROAMac

final class DirectoryChangeMonitorTests: XCTestCase {
    func testAtomicReplacementNotifiesWithoutPolling() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("request.json").path
        try FileStore.write(false, path: path, permissions: 0o600)
        let changed = expectation(description: "Atomic replacement observed")
        changed.assertForOverFulfill = false
        let monitor = try XCTUnwrap(DirectoryChangeMonitor(path: directory.path, owner: getuid(),
                                                          queue: DispatchQueue(label: "monitor-test")) {
            if (try? FileStore.read(Bool.self, path: path, owner: getuid())) == true {
                changed.fulfill()
            }
        })
        try FileStore.write(true, path: path, permissions: 0o600)
        wait(for: [changed], timeout: 2)
        withExtendedLifetime(monitor) {}
    }

    func testRejectsSymlinkAndWritableDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let link = directory.appendingPathComponent("link").path
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: directory.path)
        XCTAssertNil(DirectoryChangeMonitor(path: link, owner: getuid(), queue: .main) {})
        XCTAssertNil(DirectoryChangeMonitor(path: directory.path, owner: getuid() + 1, queue: .main) {})
        let file = directory.appendingPathComponent("file.json").path
        try FileStore.write(false, path: file, permissions: 0o600)
        XCTAssertNil(DirectoryChangeMonitor(path: file, owner: getuid(), queue: .main) {})
        XCTAssertEqual(chmod(directory.path, 0o777), 0)
        XCTAssertNil(DirectoryChangeMonitor(path: directory.path, owner: getuid(), queue: .main) {})
    }
}
