import Foundation
import Darwin

/// Observe the containing directory because FileStore atomically replaces files.
/// Events are hints only: callers still validate and read the authoritative file.
public final class DirectoryChangeMonitor {
    private let source: DispatchSourceFileSystemObject

    public init?(path: String, owner: uid_t, queue: DispatchQueue,
                 onChange: @escaping () -> Void) {
        let descriptor = open(path, O_EVTONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              info.st_uid == owner, info.st_mode & mode_t(0o022) == 0 else {
            close(descriptor)
            return nil
        }
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: .write, queue: queue)
        source.setEventHandler(handler: onChange)
        source.setCancelHandler { close(descriptor) }
        source.resume()
    }

    deinit { source.cancel() }
}
