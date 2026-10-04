import Foundation
import Darwin

/// Changes the next login's launch policy without unloading the currently running menu app.
public enum LoginItemManager {
    public static let preferenceKey = "launchAtLogin"
    public static var isEnabled: Bool { UserDefaults.standard.bool(forKey: preferenceKey) }

    public static func setEnabled(_ enabled: Bool) throws {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try write(enabled: enabled, to: directory.appendingPathComponent("net.reviontech.roa.menubar.plist"))
        UserDefaults.standard.set(enabled, forKey: preferenceKey)
    }

    static func write(enabled: Bool, to url: URL) throws {
        var directory = stat()
        let parent = url.deletingLastPathComponent().path
        guard lstat(parent, &directory) == 0,
              directory.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              directory.st_uid == getuid(), directory.st_mode & mode_t(0o022) == 0
        else { throw StoreError.unsafeFile }
        var existing = stat()
        let result = lstat(url.path, &existing)
        let acceptable = result == 0
            ? existing.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
                && existing.st_uid == getuid() && existing.st_mode & mode_t(0o022) == 0
            : errno == ENOENT
        guard acceptable
        else { throw StoreError.unsafeFile }
        let properties: [String: Any] = [
            "Label": "net.reviontech.roa.menubar",
            "ProgramArguments": ["/Applications/ROA.app/Contents/MacOS/ROA"],
            "RunAtLoad": enabled,
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Interactive"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: properties, format: .xml, options: 0)
        try data.write(to: url, options: .atomic)
        guard chmod(url.path, 0o644) == 0 else { throw StoreError.unsafeFile }
    }
}
