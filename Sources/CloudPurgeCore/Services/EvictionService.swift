import Foundation

public struct EvictionReport: Sendable {
    public let totalRequested: Int
    public let successfullyEvicted: Int
    public let skippedCount: Int
    public let bytesReclaimed: Int64
    public let failedItems: [(url: URL, reason: String)]
    public let evictedItemIds: Set<UUID>
}

public enum EvictionError: LocalizedError, Sendable {
    case notSafeToEvict(String)
    case systemEvictionFailed(String)
    case itemNotFound

    public var errorDescription: String? {
        switch self {
        case .notSafeToEvict(let reason):
            return "File is not safe to evict: \(reason)"
        case .systemEvictionFailed(let reason):
            return "macOS eviction failed: \(reason)"
        case .itemNotFound:
            return "File was not found on disk."
        }
    }
}

public final class EvictionService: Sendable {
    public static let shared = EvictionService()

    private static let safetyKeys: Set<URLResourceKey> = [
        .ubiquitousItemIsUploadedKey,
        .ubiquitousItemIsUploadingKey,
        .ubiquitousItemHasUnresolvedConflictsKey
    ]

    private var fileManager: FileManager {
        FileManager.default
    }

    /// Safely evicts a single file from local disk while preserving its cloud stub.
    public func evict(item: CloudItem) throws -> Int64 {
        let itemURL = item.url
        guard fileManager.fileExists(atPath: item.path) else {
            throw EvictionError.itemNotFound
        }

        guard item.isUploaded else {
            throw EvictionError.notSafeToEvict("Local edits have not uploaded to the cloud yet.")
        }

        guard !item.isUploading else {
            throw EvictionError.notSafeToEvict("File is actively uploading to the cloud.")
        }

        guard !item.hasConflicts else {
            throw EvictionError.notSafeToEvict("File has an unresolved cloud conflict.")
        }

        // Perform live pre-eviction check on ubiquitous status
        if let vals = try? itemURL.resourceValues(forKeys: Self.safetyKeys) {
            if vals.ubiquitousItemIsUploaded == false {
                throw EvictionError.notSafeToEvict("Local edits have not uploaded to the cloud yet.")
            }
            if vals.ubiquitousItemIsUploading == true {
                throw EvictionError.notSafeToEvict("File is actively uploading to the cloud.")
            }
            if vals.ubiquitousItemHasUnresolvedConflicts == true {
                throw EvictionError.notSafeToEvict("File has an unresolved cloud conflict.")
            }
        }

        let reclaimedBytes = item.allocatedSize

        do {
            try fileManager.evictUbiquitousItem(at: itemURL)
        } catch {
            throw EvictionError.systemEvictionFailed(error.localizedDescription)
        }

        return reclaimedBytes
    }

    /// Evicts multiple items in the background, reporting throttled progress.
    public func evictBatch(
        items: [CloudItem],
        onProgress: (@Sendable (Int, Int, Int64) -> Void)? = nil
    ) async -> EvictionReport {
        return await Task.detached(priority: .userInitiated) {
            var successCount = 0
            var skippedCount = 0
            var bytesReclaimed: Int64 = 0
            var failedItems: [(url: URL, reason: String)] = []
            var evictedIds = Set<UUID>()
            evictedIds.reserveCapacity(items.count)

            let total = items.count
            var lastProgressTime = CFAbsoluteTimeGetCurrent()

            for (index, item) in items.enumerated() {
                if Task.isCancelled {
                    break
                }

                if !item.isReclaimable {
                    skippedCount += 1
                } else {
                    do {
                        let freed = try self.evict(item: item)
                        successCount += 1
                        bytesReclaimed += freed
                        evictedIds.insert(item.id)
                    } catch {
                        failedItems.append((url: item.url, reason: error.localizedDescription))
                    }
                }

                let now = CFAbsoluteTimeGetCurrent()
                if index + 1 == total || now - lastProgressTime >= 0.10 {
                    lastProgressTime = now
                    onProgress?(index + 1, total, bytesReclaimed)
                }
            }

            return EvictionReport(
                totalRequested: total,
                successfullyEvicted: successCount,
                skippedCount: skippedCount,
                bytesReclaimed: bytesReclaimed,
                failedItems: failedItems,
                evictedItemIds: evictedIds
            )
        }.value
    }

    /// Requests that macOS materialize/download the ubiquitous item from cloud storage.
    public func download(item: CloudItem) throws {
        try fileManager.startDownloadingUbiquitousItem(at: item.url)
    }
}
