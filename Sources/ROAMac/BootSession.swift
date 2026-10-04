import Foundation
import Darwin

public enum BootSession {
    private static let secondsPerTick: Double = {
        var info = mach_timebase_info_data_t()
        guard mach_timebase_info(&info) == KERN_SUCCESS, info.denom != 0 else { return .nan }
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()

    /// Time since boot including sleep, unaffected by changes to the calendar clock.
    /// A failed kernel conversion returns NaN so callers reject the request safely.
    public static func elapsedTime() -> TimeInterval {
        Double(mach_continuous_time()) * secondsPerTick
    }

    /// Kernel-generated identity; never fall back to a wall clock or user-controlled file.
    public static func currentID() -> String? {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0,
              size > 1, size <= 128 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        let result = bytes.withUnsafeMutableBytes { buffer in
            sysctlbyname("kern.bootsessionuuid", buffer.baseAddress, &size, nil, 0)
        }
        guard result == 0, size > 1, size <= bytes.count,
              bytes[size - 1] == 0,
              let text = String(bytes: bytes.prefix(size - 1), encoding: .utf8),
              let identifier = UUID(uuidString: text) else { return nil }
        return identifier.uuidString
    }
}
