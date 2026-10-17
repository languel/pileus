import Foundation
import Darwin

/// Thread-safe controller allowing a running POSIX `fts` scan to be paused and resumed without losing progress,
/// and streaming incremental item batches so partial work is immediately usable even while paused or scanning.
public final class ScanSessionControl: @unchecked Sendable {
    private let condition = NSCondition()
    private var _isPaused: Bool = false
    private var _isStopped: Bool = false

    public init() {}

    public var isPaused: Bool {
        condition.lock()
        defer { condition.unlock() }
        return _isPaused
    }

    public var isStopped: Bool {
        condition.lock()
        defer { condition.unlock() }
        return _isStopped
    }

    public func pause() {
        condition.lock()
        _isPaused = true
        condition.unlock()
    }

    public func resume() {
        condition.lock()
        _isPaused = false
        condition.broadcast()
        condition.unlock()
    }

    public func stop() {
        condition.lock()
        _isStopped = true
        _isPaused = false
        condition.broadcast()
        condition.unlock()
    }

    /// Blocks the background scanner thread while paused; returns `false` if stopped/cancelled.
    public func waitIfPaused() -> Bool {
        condition.lock()
        defer { condition.unlock() }
        while _isPaused && !_isStopped {
            condition.wait()
        }
        return !_isStopped
    }
}

public final class CloudScanner: Sendable {
    public static let shared = CloudScanner()

    public struct ScanResult: Sendable {
        public let items: [CloudItem]
        public let folderNodes: [CloudFolderNode]
        public let allFolders: [CloudFolderNode]
        public let totalCloudBytes: Int64
        public let reclaimableBytes: Int64
        public let downloadedCount: Int
        public let totalFilesCount: Int
    }

    public struct ScanProgress: Sendable {
        public let scannedFiles: Int
        public let currentPath: String
        public let totalCloudBytes: Int64
        public let reclaimableBytes: Int64
        public let downloadedCount: Int
        public let newItemsBatch: [CloudItem]
        public let snapshotFolderNodes: [CloudFolderNode]?
        public let snapshotAllFolders: [CloudFolderNode]?
    }

    private struct FolderFrame {
        let path: String
        let name: String
        let relativePath: String
        let depth: Int
        let suppressChildFolderNodes: Bool
        var totalBytes: Int64 = 0
        var reclaimableBytes: Int64 = 0
        var totalCount: Int = 0
        var downloadedCount: Int = 0
        var children: [CloudFolderNode] = []
    }

    /// Asynchronously scans a root URL using POSIX fts and yields throttled progress updates.
    public func scan(
        rootURL: URL,
        providerId: String,
        onProgress: (@Sendable (Int, String) -> Void)? = nil
    ) async throws -> ScanResult {
        return try await scanWithProgress(rootURL: rootURL, providerId: providerId) { progress in
            onProgress?(progress.scannedFiles, progress.currentPath)
        }
    }

    /// Builds a snapshot of the current folder hierarchy from the active stack (including in-progress folders)
    /// so pausing or stopping mid-scan preserves all folder analysis data discovered so far.
    private static func buildSnapshotFolders(
        from stack: [FolderFrame],
        completedAllFolders: [CloudFolderNode],
        providerId: String
    ) -> (tree: [CloudFolderNode], allFolders: [CloudFolderNode]) {
        guard !stack.isEmpty else { return ([], completedAllFolders) }
        var tempStack = stack
        var allList = completedAllFolders
        while tempStack.count > 1 {
            guard var finished = tempStack.popLast() else { break }
            let parentIdx = tempStack.count - 1
            tempStack[parentIdx].totalBytes += finished.totalBytes
            tempStack[parentIdx].reclaimableBytes += finished.reclaimableBytes
            tempStack[parentIdx].totalCount += finished.totalCount
            tempStack[parentIdx].downloadedCount += finished.downloadedCount

            if finished.totalCount > 0 && !tempStack[parentIdx].suppressChildFolderNodes {
                if finished.children.count > 1 {
                    finished.children.sort { $0.reclaimableBytes > $1.reclaimableBytes }
                }
                let node = CloudFolderNode(
                    path: finished.path,
                    name: finished.name,
                    relativePath: finished.relativePath,
                    providerId: providerId,
                    totalCloudBytes: finished.totalBytes,
                    reclaimableBytes: finished.reclaimableBytes,
                    totalFilesCount: finished.totalCount,
                    downloadedFilesCount: finished.downloadedCount,
                    children: finished.children
                )
                tempStack[parentIdx].children.append(node)

                var flatNode = node
                flatNode.children = []
                allList.append(flatNode)
            }
        }
        var topLevel = tempStack.first?.children ?? []
        topLevel.sort { $0.reclaimableBytes > $1.reclaimableBytes }
        return (topLevel, allList)
    }

    /// High-performance POSIX fts directory scanner with O(1) stack-based folder tree aggregation,
    /// pause/resume support, and incremental batch streaming so partial data is never lost.
    public func scanWithProgress(
        rootURL: URL,
        providerId: String,
        control: ScanSessionControl? = nil,
        onProgress: (@Sendable (ScanProgress) -> Void)? = nil
    ) async throws -> ScanResult {
        return await Task.detached(priority: .userInitiated) {
            let rootPath = rootURL.standardizedFileURL.path
            let rootPrefixLen = rootPath.utf8.count

            guard let cRootPath = strdup(rootPath) else {
                return ScanResult(
                    items: [],
                    folderNodes: [],
                    allFolders: [],
                    totalCloudBytes: 0,
                    reclaimableBytes: 0,
                    downloadedCount: 0,
                    totalFilesCount: 0
                )
            }
            defer { free(cRootPath) }

            var paths: [UnsafeMutablePointer<CChar>?] = [cRootPath, nil]
            guard let fts = fts_open(&paths, FTS_PHYSICAL | FTS_NOCHDIR, nil) else {
                return ScanResult(
                    items: [],
                    folderNodes: [],
                    allFolders: [],
                    totalCloudBytes: 0,
                    reclaimableBytes: 0,
                    downloadedCount: 0,
                    totalFilesCount: 0
                )
            }
            defer { fts_close(fts) }

            var items: [CloudItem] = []
            items.reserveCapacity(16384)
            var lastReportedItemIndex = 0

            var allFolders: [CloudFolderNode] = []
            allFolders.reserveCapacity(1024)

            var stack: [FolderFrame] = []
            stack.reserveCapacity(64)

            var scannedCount = 0
            var totalCloudBytes: Int64 = 0
            var reclaimableBytes: Int64 = 0
            var downloadedCount = 0

            // Fast seed from providerId for deterministic UUID generation
            var seedHash: UInt64 = 0x436C6F7564507267
            for byte in providerId.utf8 {
                seedHash = (seedHash &* 1099511628211) ^ UInt64(byte)
            }
            var itemCounter: UInt64 = 0
            var lastProgressTime = CFAbsoluteTimeGetCurrent()

            while let ent = fts_read(fts) {
                let info = Int32(ent.pointee.fts_info)
                guard let pathPtr = ent.pointee.fts_path else { continue }

                // Extract filename from last '/' in fts_path in O(1)
                let namePtr = strrchr(pathPtr, 0x2f).map { $0.advanced(by: 1) } ?? pathPtr
                let name = String(cString: namePtr)

                if info == FTS_D {
                    let level = Int(ent.pointee.fts_level)
                    if level > 0 {
                        // Skip internal cloud/system metadata folders
                        if name == ".Trash" ||
                           name.hasPrefix(".shortcut-targets") ||
                           name == ".tmp" ||
                           name == ".DS_Store" ||
                           name == ".Spotlight-V100" ||
                           name == ".fseventsd" {
                            fts_set(fts, ent, FTS_SKIP)
                            continue
                        }
                    }

                    let fullPath = String(cString: pathPtr)
                    let relativePath: String
                    if fullPath.utf8.count > rootPrefixLen {
                        let startIdx = fullPath.utf8.index(fullPath.utf8.startIndex, offsetBy: rootPrefixLen)
                        var sub = Substring(fullPath[startIdx...])
                        if sub.first == "/" {
                            sub = sub.dropFirst()
                        }
                        relativePath = String(sub)
                    } else {
                        relativePath = "/"
                    }

                    let parentSuppresses = stack.last?.suppressChildFolderNodes ?? false
                    let isHeavyPackageDir = (
                        name == "node_modules" ||
                        name == ".git" ||
                        name == ".venv" ||
                        name == "venv" ||
                        name == "__pycache__" ||
                        name == "Pods" ||
                        name == ".next" ||
                        name == ".nuxt" ||
                        name.hasSuffix(".app") ||
                        name.hasSuffix(".framework") ||
                        name.hasSuffix(".xcodeproj") ||
                        name.hasSuffix(".photoslibrary")
                    )
                    // Suppress creating thousands of deep child FolderNodes inside node_modules/.git/.venv or beyond depth 10,
                    // while still counting 100% of their files and bytes in the folder node itself!
                    let suppressChildren = parentSuppresses || isHeavyPackageDir || level >= 10

                    stack.append(
                        FolderFrame(
                            path: fullPath,
                            name: name,
                            relativePath: relativePath,
                            depth: level,
                            suppressChildFolderNodes: suppressChildren
                        )
                    )
                } else if info == FTS_DP {
                    guard var finished = stack.popLast() else { continue }
                    if !stack.isEmpty {
                        let parentIdx = stack.count - 1
                        stack[parentIdx].totalBytes += finished.totalBytes
                        stack[parentIdx].reclaimableBytes += finished.reclaimableBytes
                        stack[parentIdx].totalCount += finished.totalCount
                        stack[parentIdx].downloadedCount += finished.downloadedCount

                        // Attach to parent's folder tree if non-empty and parent doesn't suppress child folder nodes
                        if finished.totalCount > 0 && !stack[parentIdx].suppressChildFolderNodes {
                            if finished.children.count > 1 {
                                finished.children.sort { $0.reclaimableBytes > $1.reclaimableBytes }
                            }
                            let node = CloudFolderNode(
                                path: finished.path,
                                name: finished.name,
                                relativePath: finished.relativePath,
                                providerId: providerId,
                                totalCloudBytes: finished.totalBytes,
                                reclaimableBytes: finished.reclaimableBytes,
                                totalFilesCount: finished.totalCount,
                                downloadedFilesCount: finished.downloadedCount,
                                children: finished.children
                            )
                            stack[parentIdx].children.append(node)

                            var flatNode = node
                            flatNode.children = []
                            allFolders.append(flatNode)
                        }
                    } else {
                        // Root frame popped: put it back so we can read its children at the end
                        stack.append(finished)
                    }
                } else if info == FTS_F {
                    if name == ".DS_Store" || name == ".localized" {
                        continue
                    }

                    guard let st = ent.pointee.fts_statp else { continue }

                    scannedCount &+= 1
                    itemCounter &+= 1

                    let logicalFileSize = Int64(st.pointee.st_size)
                    let flags = st.pointee.st_flags
                    let blocks = Int64(st.pointee.st_blocks)
                    let isDataless = (flags & DatalessDetector.sfDatalessFlag) != 0 || (blocks == 0 && logicalFileSize > 0)
                    let allocatedSize = isDataless ? 0 : max(0, blocks * 512)
                    let syncStatus: SyncStatus = isDataless ? .cloudOnly : .downloaded

                    let fullPath = String(cString: pathPtr)
                    let parentFolderPath = stack.last?.path ?? rootPath
                    let parentRel = stack.last?.relativePath ?? "/"
                    let relativePath = (parentRel == "/" || parentRel.isEmpty) ? name : "\(parentRel)/\(name)"

                    let modDate = Date(timeIntervalSince1970: TimeInterval(st.pointee.st_mtimespec.tv_sec))
                    let createDate = Date(timeIntervalSince1970: TimeInterval(st.pointee.st_birthtimespec.tv_sec))
                    let accessDate = Date(timeIntervalSince1970: TimeInterval(st.pointee.st_atimespec.tv_sec))

                    let item = CloudItem(
                        id: CloudItem.makeFastID(seed: seedHash, index: itemCounter),
                        path: fullPath,
                        name: name,
                        relativePath: relativePath,
                        parentFolderPath: parentFolderPath,
                        providerId: providerId,
                        fileSize: logicalFileSize,
                        allocatedSize: allocatedSize,
                        isDataless: isDataless,
                        isUploaded: true,
                        isUploading: false,
                        isDownloading: false,
                        hasConflicts: false,
                        syncStatus: syncStatus,
                        kind: FileKind.kind(forFileName: name),
                        modificationDate: modDate,
                        creationDate: createDate,
                        lastAccessDate: accessDate
                    )

                    items.append(item)

                    totalCloudBytes += logicalFileSize
                    let isReclaimable = !isDataless && allocatedSize > 0
                    if isReclaimable {
                        reclaimableBytes += allocatedSize
                        downloadedCount &+= 1
                    }

                    if !stack.isEmpty {
                        let topIdx = stack.count - 1
                        stack[topIdx].totalBytes += logicalFileSize
                        stack[topIdx].totalCount &+= 1
                        if isReclaimable {
                            stack[topIdx].reclaimableBytes += allocatedSize
                            stack[topIdx].downloadedCount &+= 1
                        }
                    }

                    // Periodic pause/stop check & throttled progress batch every 256 files
                    if (scannedCount & 255) == 0 {
                        let isPausedNow = control?.isPaused ?? false
                        let isStoppedNow = (control?.isStopped ?? false) || Task.isCancelled
                        let now = CFAbsoluteTimeGetCurrent()

                        if isPausedNow || isStoppedNow || (now - lastProgressTime >= 0.20) {
                            lastProgressTime = now
                            let currentRel = stack.last?.relativePath ?? name
                            let batch: [CloudItem]
                            if items.count > lastReportedItemIndex {
                                batch = Array(items[lastReportedItemIndex..<items.count])
                                lastReportedItemIndex = items.count
                            } else {
                                batch = []
                            }

                            // When pausing or stopping, also snapshot the folder tree so Folder Analyzer works immediately
                            let folderSnapshot: (tree: [CloudFolderNode], allFolders: [CloudFolderNode])? = (isPausedNow || isStoppedNow)
                                ? CloudScanner.buildSnapshotFolders(from: stack, completedAllFolders: allFolders, providerId: providerId)
                                : nil

                            onProgress?(
                                ScanProgress(
                                    scannedFiles: scannedCount,
                                    currentPath: currentRel,
                                    totalCloudBytes: totalCloudBytes,
                                    reclaimableBytes: reclaimableBytes,
                                    downloadedCount: downloadedCount,
                                    newItemsBatch: batch,
                                    snapshotFolderNodes: folderSnapshot?.tree,
                                    snapshotAllFolders: folderSnapshot?.allFolders
                                )
                            )
                        }

                        if isStoppedNow {
                            break
                        }

                        if let ctrl = control, !ctrl.waitIfPaused() {
                            break
                        }
                    }
                }
            }

            let finalSnapshot = CloudScanner.buildSnapshotFolders(
                from: stack,
                completedAllFolders: allFolders,
                providerId: providerId
            )
            let finalBatch: [CloudItem]
            if items.count > lastReportedItemIndex {
                finalBatch = Array(items[lastReportedItemIndex..<items.count])
                lastReportedItemIndex = items.count
            } else {
                finalBatch = []
            }

            if !finalBatch.isEmpty {
                onProgress?(
                    ScanProgress(
                        scannedFiles: scannedCount,
                        currentPath: "Complete",
                        totalCloudBytes: totalCloudBytes,
                        reclaimableBytes: reclaimableBytes,
                        downloadedCount: downloadedCount,
                        newItemsBatch: finalBatch,
                        snapshotFolderNodes: finalSnapshot.tree,
                        snapshotAllFolders: finalSnapshot.allFolders
                    )
                )
            }

            return ScanResult(
                items: items,
                folderNodes: finalSnapshot.tree,
                allFolders: finalSnapshot.allFolders,
                totalCloudBytes: totalCloudBytes,
                reclaimableBytes: reclaimableBytes,
                downloadedCount: downloadedCount,
                totalFilesCount: items.count
            )
        }.value
    }
}
