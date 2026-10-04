import XCTest
import Darwin
@testable import ROAMac

final class LoginItemManagerTests: XCTestCase {
    func testOptInChangesOnlyNextLoginPolicyAndKeepsFixedExecutable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("login.plist")
        for enabled in [true, false] {
            try LoginItemManager.write(enabled: enabled, to: file)
            let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: file), format: nil) as? [String: Any])
            XCTAssertEqual(plist["RunAtLoad"] as? Bool, enabled)
            XCTAssertEqual(plist["ProgramArguments"] as? [String], ["/Applications/ROA.app/Contents/MacOS/ROA"])
            XCTAssertNil(plist["KeepAlive"])
        }
    }

    func testRejectsSymlinkWithoutTouchingDestination() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("destination")
        try Data("unchanged".utf8).write(to: destination)
        let file = directory.appendingPathComponent("login.plist")
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: destination)
        XCTAssertThrowsError(try LoginItemManager.write(enabled: true, to: file))
        XCTAssertEqual(try String(contentsOf: destination), "unchanged")
    }
}
