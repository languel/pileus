import Foundation

public struct EvictionReport: Sendable {
    public let totalRequested: Int
    public let successfullyEvicted: Int
    public let skippedCount: Int
    public let bytesReclaimed: Int64
    public let failedItems: [(url: URL, reason: String)]
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

    private var fileManager: FileManager {
        FileManager.default
    }

    /// Safely evicts a single file from local disk while preserving its cloud stub.
    public func evict(item: CloudItem) throws -> Int64 {
        guard fileManager.fileExists(atPath: item.url.path) else {
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

        let reclaimedBytes = item.allocatedSize

        do {
            try fileManager.evictUbiquitousItem(at: item.url)
        } catch {
            throw EvictionError.systemEvictionFailed(error.localizedDescription)
        }

        return reclaimedBytes
    }

    /// Evicts multiple items in the background, reporting progress.
    public func evictBatch(
        items: [CloudItem],
        onProgress: (@Sendable (Int, Int, Int64) -> Void)? = nil
    ) async -> EvictionReport {
        var successCount = 0
        var skippedCount = 0
        var bytesReclaimed: Int64 = 0
        var failedItems: [(url: URL, reason: String)] = []

        let total = items.count

        for (index, item) in items.enumerated() {
            if Task.isCancelled {
                break
            }

            guard item.isReclaimable else {
                skippedCount += 1
                onProgress?(index + 1, total, bytesReclaimed)
                continue
            }

            do {
                let freed = try evict(item: item)
                successCount += 1
                bytesReclaimed += freed
            } catch {
                failedItems.append((url: item.url, reason: error.localizedDescription))
            }

            onProgress?(index + 1, total, bytesReclaimed)
            // Small cooperative yield
            await Task.yield()
        }

        return EvictionReport(
            totalRequested: total,
            successfullyEvicted: successCount,
            skippedCount: skippedCount,
            bytesReclaimed: bytesReclaimed,
            failedItems: failedItems
        )
    }

    /// Requests that macOS materialize/download the ubiquitous item from cloud storage.
    public func download(item: CloudItem) throws {
        try fileManager.startDownloadingUbiquitousItem(at: item.url)
    }
}
