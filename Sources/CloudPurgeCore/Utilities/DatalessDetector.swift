import Foundation
import Darwin

/// Helper utility for detecting dataless / evicted APFS cloud file states
public enum DatalessDetector {
    /// APFS BSD Flag: SF_DATALESS = 0x40000000 (file is dataless / cloud-only object)
    public static let sfDatalessFlag: UInt32 = 0x40000000

    public struct FileStatInfo: Sendable {
        public let isDataless: Bool
        public let allocatedBytes: Int64
        public let logicalBytes: Int64
        public let blocks: Int64
        public let flags: UInt32
    }

    /// Queries the low-level BSD file stat attributes for datalessness and physical disk allocation.
    public static func statInfo(for url: URL) -> FileStatInfo {
        var fileStat = Darwin.stat()
        let result: Int32 = url.path.withCString { cPath in
            stat(cPath, &fileStat)
        }

        guard result == 0 else {
            return FileStatInfo(isDataless: false, allocatedBytes: 0, logicalBytes: 0, blocks: 0, flags: 0)
        }

        let isDataless = (fileStat.st_flags & sfDatalessFlag) != 0
        let blocks = Int64(fileStat.st_blocks)
        // Darwin st_blocks is count of 512-byte blocks. If file is dataless, local disk allocation is 0.
        let allocatedBytes = isDataless ? 0 : max(0, blocks * 512)
        let logicalBytes = Int64(fileStat.st_size)

        return FileStatInfo(
            isDataless: isDataless,
            allocatedBytes: allocatedBytes,
            logicalBytes: logicalBytes,
            blocks: blocks,
            flags: fileStat.st_flags
        )
    }
}
