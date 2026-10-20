import Foundation

public enum PurgeActionMode: String, Sendable {
    case evictLocalOnly = "Evict Local Copy"
    case deleteEverywhere = "Delete from Mac & Cloud"
}

public struct EvictionReport: Sendable {
    public let actionMode: PurgeActionMode
    public let totalRequested: Int
    public let successfullyEvicted: Int
    public let skippedCount: Int
    public let bytesReclaimed: Int64
    public let cloudBytesDeleted: Int64
    public let failedItems: [(url: URL, reason: String)]
    public let evictedItemIds: Set<UUID>
    public let deletedFolderPaths: [String]
    public let wasCancelled: Bool
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
    /// When `fastBatchMode` is true, skips redundant pre-flight URLResourceValues XPC round-trips
    /// because `FileManager.evictUbiquitousItem(at:)` natively enforces cloud sync safety in the kernel/FileProvider daemon.
    public func evict(item: CloudItem, fastBatchMode: Bool = false) throws -> Int64 {
        let itemURL = item.url

        guard item.isUploaded else {
            throw EvictionError.notSafeToEvict("Local edits have not uploaded to the cloud yet.")
        }

        guard !item.isUploading else {
            throw EvictionError.notSafeToEvict("File is actively uploading to the cloud.")
        }

        guard !item.hasConflicts else {
            throw EvictionError.notSafeToEvict("File has an unresolved cloud conflict.")
        }

        if !fastBatchMode {
            guard fileManager.fileExists(atPath: item.path) else {
                throw EvictionError.itemNotFound
            }

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
        }

        let reclaimedBytes = item.allocatedSize

        do {
            try fileManager.evictUbiquitousItem(at: itemURL)
        } catch {
            throw EvictionError.systemEvictionFailed(error.localizedDescription)
        }

        return reclaimedBytes
    }

    /// Evicts multiple items concurrently in the background, supporting safe cancellation/pause at any point.
    /// If `rootFolderURLs` are provided (e.g. `node_modules` directories), attempts directory-level eviction first.
    public func evictBatch(
        items: [CloudItem],
        rootFolderURLs: [URL] = [],
        control: ScanSessionControl? = nil,
        onProgress: (@Sendable (Int, Int, Int64) -> Void)? = nil
    ) async -> EvictionReport {
        return await Task.detached(priority: .userInitiated) {
            let total = items.count
            guard total > 0 else {
                return EvictionReport(
                    actionMode: .evictLocalOnly,
                    totalRequested: 0,
                    successfullyEvicted: 0,
                    skippedCount: 0,
                    bytesReclaimed: 0,
                    cloudBytesDeleted: 0,
                    failedItems: [],
                    evictedItemIds: [],
                    deletedFolderPaths: [],
                    wasCancelled: false
                )
            }

            // Fast Path: If whole folders (such as node_modules) were requested, ask macOS to evict the folder URLs directly first.
            var remainingItems: [CloudItem] = []
            var preEvictedSuccessCount = 0
            var preEvictedBytes: Int64 = 0
            var preEvictedIds = Set<UUID>()
            preEvictedIds.reserveCapacity(total)

            if !rootFolderURLs.isEmpty {
                var folderEvictedPrefixes: [String] = []
                for folderURL in rootFolderURLs {
                    if (control?.isStopped ?? false) || Task.isCancelled { break }
                    if (try? FileManager.default.evictUbiquitousItem(at: folderURL)) != nil {
                        let p = folderURL.path
                        folderEvictedPrefixes.append(p.hasSuffix("/") ? p : (p + "/"))
                    }
                }

                if !folderEvictedPrefixes.isEmpty {
                    for item in items {
                        if folderEvictedPrefixes.contains(where: { item.path.hasPrefix($0) }) {
                            let st = DatalessDetector.statInfo(forPath: item.path)
                            if st.isDataless || st.allocatedBytes == 0 {
                                preEvictedSuccessCount += 1
                                preEvictedBytes += item.allocatedSize
                                preEvictedIds.insert(item.id)
                                continue
                            }
                        }
                        remainingItems.append(item)
                    }
                    if preEvictedSuccessCount > 0 {
                        onProgress?(preEvictedSuccessCount, total, preEvictedBytes)
                    }
                } else {
                    remainingItems = items
                }
            } else {
                remainingItems = items
            }

            if remainingItems.isEmpty {
                return EvictionReport(
                    actionMode: .evictLocalOnly,
                    totalRequested: total,
                    successfullyEvicted: preEvictedSuccessCount,
                    skippedCount: 0,
                    bytesReclaimed: preEvictedBytes,
                    cloudBytesDeleted: 0,
                    failedItems: [],
                    evictedItemIds: preEvictedIds,
                    deletedFolderPaths: [],
                    wasCancelled: false
                )
            }

            let workerCount = min(8, max(1, remainingItems.count))
            let chunkSize = (remainingItems.count + workerCount - 1) / workerCount

            actor ProgressTracker {
                var processed: Int
                var successCount: Int
                var skippedCount: Int = 0
                var bytesReclaimed: Int64
                var failedItems: [(url: URL, reason: String)] = []
                var evictedIds: Set<UUID>
                var lastReportTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()

                init(initialSuccess: Int, initialBytes: Int64, initialIds: Set<UUID>, capacity: Int) {
                    self.processed = initialSuccess
                    self.successCount = initialSuccess
                    self.bytesReclaimed = initialBytes
                    self.evictedIds = initialIds
                    self.evictedIds.reserveCapacity(capacity)
                }

                func recordBatch(
                    processedDelta: Int,
                    successDelta: Int,
                    skippedDelta: Int,
                    bytesDelta: Int64,
                    ids: [UUID],
                    failures: [(url: URL, reason: String)],
                    total: Int,
                    forceReport: Bool,
                    onProgress: (@Sendable (Int, Int, Int64) -> Void)?
                ) {
                    processed += processedDelta
                    successCount += successDelta
                    skippedCount += skippedDelta
                    bytesReclaimed += bytesDelta
                    for id in ids {
                        evictedIds.insert(id)
                    }
                    if !failures.isEmpty {
                        failedItems.append(contentsOf: failures)
                    }

                    let now = CFAbsoluteTimeGetCurrent()
                    if forceReport || processed >= total || (now - lastReportTime >= 0.12) {
                        lastReportTime = now
                        onProgress?(processed, total, bytesReclaimed)
                    }
                }

                func snapshot(total: Int, wasCancelled: Bool) -> EvictionReport {
                    return EvictionReport(
                        actionMode: .evictLocalOnly,
                        totalRequested: total,
                        successfullyEvicted: successCount,
                        skippedCount: skippedCount,
                        bytesReclaimed: bytesReclaimed,
                        cloudBytesDeleted: 0,
                        failedItems: failedItems,
                        evictedItemIds: evictedIds,
                        deletedFolderPaths: [],
                        wasCancelled: wasCancelled
                    )
                }
            }

            let tracker = ProgressTracker(
                initialSuccess: preEvictedSuccessCount,
                initialBytes: preEvictedBytes,
                initialIds: preEvictedIds,
                capacity: total
            )

            await withTaskGroup(of: Void.self) { group in
                for workerIdx in 0..<workerCount {
                    let start = workerIdx * chunkSize
                    guard start < remainingItems.count else { break }
                    let end = min(remainingItems.count, start + chunkSize)
                    let slice = Array(remainingItems[start..<end])

                    group.addTask {
                        var localProcessed = 0
                        var localSuccess = 0
                        var localSkipped = 0
                        var localBytes: Int64 = 0
                        var localIds: [UUID] = []
                        localIds.reserveCapacity(32)
                        var localFailures: [(url: URL, reason: String)] = []

                        for item in slice {
                            if (control?.isStopped ?? false) || Task.isCancelled {
                                break
                            }
                            if let ctrl = control, !ctrl.waitIfPaused() {
                                break
                            }

                            localProcessed += 1
                            if !item.isReclaimable {
                                localSkipped += 1
                            } else {
                                do {
                                    let freed = try EvictionService.shared.evict(item: item, fastBatchMode: true)
                                    localSuccess += 1
                                    localBytes += freed
                                    localIds.append(item.id)
                                } catch {
                                    localFailures.append((url: item.url, reason: error.localizedDescription))
                                }
                            }

                            if localProcessed >= 16 {
                                await tracker.recordBatch(
                                    processedDelta: localProcessed,
                                    successDelta: localSuccess,
                                    skippedDelta: localSkipped,
                                    bytesDelta: localBytes,
                                    ids: localIds,
                                    failures: localFailures,
                                    total: total,
                                    forceReport: false,
                                    onProgress: onProgress
                                )
                                localProcessed = 0
                                localSuccess = 0
                                localSkipped = 0
                                localBytes = 0
                                localIds.removeAll(keepingCapacity: true)
                                localFailures.removeAll(keepingCapacity: true)
                            }
                        }

                        if localProcessed > 0 {
                            await tracker.recordBatch(
                                processedDelta: localProcessed,
                                successDelta: localSuccess,
                                skippedDelta: localSkipped,
                                bytesDelta: localBytes,
                                ids: localBytes >= 0 ? localIds : [],
                                failures: localFailures,
                                total: total,
                                forceReport: true,
                                onProgress: onProgress
                            )
                        }
                    }
                }
            }

            let cancelled = (control?.isStopped ?? false) || Task.isCancelled
            return await tracker.snapshot(total: total, wasCancelled: cancelled)
        }.value
    }

    /// Permanently deletes items or entire directories (such as `node_modules`) from both local disk and cloud storage.
    /// Deleting a directory via `FileManager.removeItem(at:)` removes the entire folder tree in one operation without
    /// needing per-file XPC eviction calls.
    public func deleteBatch(
        items: [CloudItem],
        rootFolderURLs: [URL] = [],
        control: ScanSessionControl? = nil,
        onProgress: (@Sendable (Int, Int, Int64) -> Void)? = nil
    ) async -> EvictionReport {
        return await Task.detached(priority: .userInitiated) {
            let total = items.count
            var deletedIds = Set<UUID>()
            deletedIds.reserveCapacity(total)
            var deletedFolderPaths: [String] = []
            var localBytesFreed: Int64 = 0
            var cloudBytesDeleted: Int64 = 0
            var failedItems: [(url: URL, reason: String)] = []

            // 1. If whole folders were selected (e.g. node_modules), delete each directory tree directly!
            if !rootFolderURLs.isEmpty {
                for (fIdx, folderURL) in rootFolderURLs.enumerated() {
                    if (control?.isStopped ?? false) || Task.isCancelled { break }
                    if let ctrl = control, !ctrl.waitIfPaused() { break }

                    let folderPath = folderURL.path
                    let prefix = folderPath.hasSuffix("/") ? folderPath : (folderPath + "/")

                    do {
                        if FileManager.default.fileExists(atPath: folderPath) {
                            try FileManager.default.removeItem(at: folderURL)
                        }
                        deletedFolderPaths.append(folderPath)

                        // Account for all items inside this deleted folder
                        for item in items where item.parentFolderPath == folderPath || item.path.hasPrefix(prefix) {
                            if deletedIds.insert(item.id).inserted {
                                localBytesFreed += item.allocatedSize
                                cloudBytesDeleted += item.fileSize
                            }
                        }

                        onProgress?(deletedIds.count, max(1, total), localBytesFreed)
                    } catch {
                        failedItems.append((url: folderURL, reason: error.localizedDescription))
                    }

                    if fIdx + 1 == rootFolderURLs.count {
                        onProgress?(deletedIds.count, max(1, total), localBytesFreed)
                    }
                }
            }

            // 2. Delete any remaining individual files not covered by rootFolderURLs
            var lastReportTime = CFAbsoluteTimeGetCurrent()
            for (idx, item) in items.enumerated() {
                if deletedIds.contains(item.id) { continue }
                if (control?.isStopped ?? false) || Task.isCancelled { break }
                if let ctrl = control, !ctrl.waitIfPaused() { break }

                do {
                    if FileManager.default.fileExists(atPath: item.path) {
                        try FileManager.default.removeItem(atPath: item.path)
                    }
                    deletedIds.insert(item.id)
                    localBytesFreed += item.allocatedSize
                    cloudBytesDeleted += item.fileSize
                } catch {
                    failedItems.append((url: item.url, reason: error.localizedDescription))
                }

                let now = CFAbsoluteTimeGetCurrent()
                if idx + 1 == total || (now - lastReportTime >= 0.12) {
                    lastReportTime = now
                    onProgress?(deletedIds.count, total, localBytesFreed)
                }
            }

            let cancelled = (control?.isStopped ?? false) || Task.isCancelled
            return EvictionReport(
                actionMode: .deleteEverywhere,
                totalRequested: total,
                successfullyEvicted: deletedIds.count,
                skippedCount: 0,
                bytesReclaimed: localBytesFreed,
                cloudBytesDeleted: cloudBytesDeleted,
                failedItems: failedItems,
                evictedItemIds: deletedIds,
                deletedFolderPaths: deletedFolderPaths,
                wasCancelled: cancelled
            )
        }.value
    }

    /// Requests that macOS materialize/download the ubiquitous item from cloud storage.
    public func download(item: CloudItem) throws {
        try fileManager.startDownloadingUbiquitousItem(at: item.url)
    }
}
