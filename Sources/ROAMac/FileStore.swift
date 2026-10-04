import Foundation
import Darwin
import ROACore

public enum StoreError: Error, LocalizedError {
    case unsafeFile, notInstalled, invalidDuration, bootSessionUnavailable
    public var errorDescription: String? {
        switch self {
        case .unsafeFile: return "ROA encountered an invalid or unsafe state file."
        case .notInstalled: return "ROA is not installed for this account. Run ./scripts/install.sh."
        case .invalidDuration: return "Session duration must be finite and between 60 and 86400 seconds."
        case .bootSessionUnavailable: return "The current boot session could not be verified. No ON request was saved."
        }
    }
}

public struct FileStore {
    public let owner: uid_t
    public let requestPath: String
    public let statusPath: String

    public init(owner: uid_t) {
        self.owner = owner
        requestPath = "\(ROAConstants.dataRoot)/\(owner)/request.json"
        statusPath = "\(ROAConstants.runtimeRoot)/status.json"
    }

    // Test stores use isolated temporary files, never the installed service's state.
    init(owner: uid_t, requestPath: String, statusPath: String) {
        self.owner = owner
        self.requestPath = requestPath
        self.statusPath = statusPath
    }

    /// No symlink following; only a bounded regular file belonging to the expected UID.
    public static func read<T: Decodable>(_ type: T.Type, path: String, owner: uid_t) throws -> T {
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw StoreError.unsafeFile }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_uid == owner, info.st_size > 0, info.st_size <= 8192,
              info.st_mode & mode_t(0o022) == 0 else { throw StoreError.unsafeFile }
        var bytes = [UInt8](repeating: 0, count: Int(info.st_size))
        let count = bytes.withUnsafeMutableBytes { buffer in
            Darwin.read(descriptor, buffer.baseAddress, buffer.count)
        }
        guard count == bytes.count else { throw StoreError.unsafeFile }
        return try JSONDecoder().decode(type, from: Data(bytes))
    }

    public func request() -> ModeRequest? {
        try? Self.read(ModeRequest.self, path: requestPath, owner: owner)
    }

    public func status() -> ServiceStatus? {
        try? Self.read(ServiceStatus.self, path: statusPath, owner: 0)
    }

    public func setEnabled(_ enabled: Bool, duration: TimeInterval? = nil,
                           chargingOnly: Bool = false) throws -> ModeRequest {
        if let duration, !ModeRequest.isValidDuration(duration) { throw StoreError.invalidDuration }
        guard getuid() == owner, FileManager.default.isWritableFile(atPath: URL(fileURLWithPath: requestPath).deletingLastPathComponent().path)
        else { throw StoreError.notInstalled }
        var bootSessionID: String?
        var startedAtUptime: TimeInterval?
        if enabled {
            guard let identifier = BootSession.currentID() else { throw StoreError.bootSessionUnavailable }
            let uptime = BootSession.elapsedTime()
            guard uptime.isFinite, uptime >= 0 else { throw StoreError.bootSessionUnavailable }
            bootSessionID = identifier
            startedAtUptime = uptime
        }
        let request = ModeRequest(enabled: enabled, duration: enabled ? duration : nil,
                                  chargingOnly: enabled && chargingOnly,
                                  bootSessionID: bootSessionID, startedAtUptime: startedAtUptime)
        try Self.write(request, path: requestPath, permissions: 0o600)
        return request
    }

    public func publish(_ status: ServiceStatus) throws {
        guard geteuid() == 0 else { throw StoreError.unsafeFile }
        try Self.write(status, path: statusPath, permissions: 0o644)
    }

    /// Write to a new exclusive temporary file, then atomically rename it.
    public static func write<T: Encodable>(_ value: T, path: String, permissions: mode_t) throws {
        let data = try JSONEncoder().encode(value)
        guard data.count <= 8192 else { throw StoreError.unsafeFile }
        let temporary = path + "." + UUID().uuidString
        let descriptor = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, permissions)
        guard descriptor >= 0 else { throw StoreError.unsafeFile }
        defer { close(descriptor); unlink(temporary) }
        let count = data.withUnsafeBytes { buffer in
            Darwin.write(descriptor, buffer.baseAddress, buffer.count)
        }
        guard count == data.count, fsync(descriptor) == 0, rename(temporary, path) == 0
        else { throw StoreError.unsafeFile }
    }
}
