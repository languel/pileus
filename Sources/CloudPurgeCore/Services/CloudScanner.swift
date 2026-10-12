import Foundation

public final class CloudScanner: Sendable {
    public static let shared = CloudScanner()

    public struct ScanResult: Sendable {
        public let items: [CloudItem]
        public let folderNodes: [CloudFolderNode]
        public let totalCloudBytes: Int64
        public let reclaimableBytes: Int64
        public let downloadedCount: Int
        public let totalFilesCount: Int
    }

    private let resourceKeys: Set<URLResourceKey> = [
        .ubiquitousItemDownloadingStatusKey,
        .ubiquitousItemIsUploadedKey,
        .ubiquitousItemIsUploadingKey,
        .ubiquitousItemIsDownloadingKey,
        .ubiquitousItemHasUnresolvedConflictsKey,
        .fileSizeKey,
        .totalFileAllocatedSizeKey,
        .contentModificationDateKey,
        .contentAccessDateKey,
        .creationDateKey,
        .isDirectoryKey,
        .isPackageKey,
        .isRegularFileKey
    ]

    /// Asynchronously scans a root URL and yields periodic progress updates.
    public func scan(
        rootURL: URL,
        providerId: String,
        onProgress: (@Sendable (Int, String) -> Void)? = nil
    ) async throws -> ScanResult {
        let fileManager = FileManager.default
        var items: [CloudItem] = []
        var folderStats: [String: (url: URL, name: String, relative: String, totalBytes: Int64, reclaimableBytes: Int64, totalCount: Int, downloadedCount: Int)] = [:]

        // Pre-create root entry in folder stats
        let rootPath = rootURL.standardizedFileURL.path
        folderStats[rootPath] = (
            url: rootURL,
            name: rootURL.lastPathComponent,
            relative: "/",
            totalBytes: 0,
            reclaimableBytes: 0,
            totalCount: 0,
            downloadedCount: 0
        )

        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return ScanResult(
                items: [],
                folderNodes: [],
                totalCloudBytes: 0,
                reclaimableBytes: 0,
                downloadedCount: 0,
                totalFilesCount: 0
            )
        }

        var scannedCount = 0

        while let itemURL = enumerator.nextObject() as? URL {
            if Task.isCancelled {
                throw CancellationError()
            }

            let lastComponent = itemURL.lastPathComponent
            // Ignore internal metadata files and directories
            if lastComponent.hasPrefix(".Trash") ||
               lastComponent.hasPrefix(".shortcut-targets") ||
               lastComponent.hasPrefix(".tmp") ||
               lastComponent == ".DS_Store" {
                continue
            }

            guard let resourceValues = try? itemURL.resourceValues(forKeys: resourceKeys) else {
                continue
            }

            let isDirectory = resourceValues.isDirectory ?? false
            let isPackage = resourceValues.isPackage ?? false

            let standardizedPath = itemURL.standardizedFileURL.path
            let relativePath: String
            if standardizedPath.hasPrefix(rootPath) {
                let suffix = String(standardizedPath.dropFirst(rootPath.count))
                relativePath = suffix.hasPrefix("/") ? String(suffix.dropFirst()) : suffix
            } else {
                relativePath = lastComponent
            }

            if isDirectory && !isPackage {
                // Register directory in folder map
                if folderStats[standardizedPath] == nil {
                    folderStats[standardizedPath] = (
                        url: itemURL,
                        name: lastComponent,
                        relative: relativePath,
                        totalBytes: 0,
                        reclaimableBytes: 0,
                        totalCount: 0,
                        downloadedCount: 0
                    )
                }
                continue
            }

            // It's a file or package
            scannedCount += 1
            if scannedCount % 25 == 0 {
                onProgress?(scannedCount, relativePath)
            }

            let statInfo = DatalessDetector.statInfo(for: itemURL)
            let logicalFileSize = Int64(resourceValues.fileSize ?? Int(statInfo.logicalBytes))
            let isDataless = statInfo.isDataless || (statInfo.blocks == 0 && logicalFileSize > 0)
            let allocatedSize = isDataless ? 0 : statInfo.allocatedBytes

            // Sync Status computation
            let isUploaded = resourceValues.ubiquitousItemIsUploaded ?? true
            let isUploading = resourceValues.ubiquitousItemIsUploading ?? false
            let isDownloading = resourceValues.ubiquitousItemIsDownloading ?? false
            let hasConflicts = resourceValues.ubiquitousItemHasUnresolvedConflicts ?? false
            let downloadStatus = resourceValues.ubiquitousItemDownloadingStatus

            let syncStatus: SyncStatus
            if hasConflicts {
                syncStatus = .conflict
            } else if isUploading {
                syncStatus = .uploading
            } else if isDownloading {
                syncStatus = .downloading
            } else if !isUploaded {
                syncStatus = .unsynced
            } else if isDataless || downloadStatus == .notDownloaded {
                syncStatus = .cloudOnly
            } else {
                syncStatus = .downloaded
            }

            let parentURL = itemURL.deletingLastPathComponent().standardizedFileURL
            let parentFolderPath = parentURL.path

            let cloudItem = CloudItem(
                url: itemURL,
                name: lastComponent,
                relativePath: relativePath,
                parentFolderPath: parentFolderPath,
                providerId: providerId,
                fileSize: logicalFileSize,
                allocatedSize: allocatedSize,
                isDataless: isDataless,
                isUploaded: isUploaded,
                isUploading: isUploading,
                isDownloading: isDownloading,
                hasConflicts: hasConflicts,
                syncStatus: syncStatus,
                kind: FileKind.kind(for: itemURL),
                modificationDate: resourceValues.contentModificationDate,
                creationDate: resourceValues.creationDate,
                lastAccessDate: resourceValues.contentAccessDate
            )

            items.append(cloudItem)

            // Propagate file size and reclaimable bytes to all ancestor folders
            var curDir = parentURL
            while true {
                let curDirPath = curDir.path
                if var existing = folderStats[curDirPath] {
                    existing.totalBytes += logicalFileSize
                    if cloudItem.isReclaimable {
                        existing.reclaimableBytes += allocatedSize
                        existing.downloadedCount += 1
                    }
                    existing.totalCount += 1
                    folderStats[curDirPath] = existing
                } else if curDirPath.hasPrefix(rootPath) {
                    let rel: String
                    if curDirPath == rootPath {
                        rel = "/"
                    } else {
                        let suf = String(curDirPath.dropFirst(rootPath.count))
                        rel = suf.hasPrefix("/") ? String(suf.dropFirst()) : suf
                    }
                    folderStats[curDirPath] = (
                        url: curDir,
                        name: curDir.lastPathComponent,
                        relative: rel,
                        totalBytes: logicalFileSize,
                        reclaimableBytes: cloudItem.isReclaimable ? allocatedSize : 0,
                        totalCount: 1,
                        downloadedCount: cloudItem.isReclaimable ? 1 : 0
                    )
                }

                if curDirPath == rootPath || !curDirPath.hasPrefix(rootPath) {
                    break
                }
                curDir = curDir.deletingLastPathComponent().standardizedFileURL
            }
        }

        onProgress?(scannedCount, "Complete")

        // Build hierarchical folder nodes
        let folderNodes = buildFolderTree(from: folderStats, rootPath: rootPath, providerId: providerId)

        var totalCloudBytes: Int64 = 0
        var reclaimableBytes: Int64 = 0
        var downloadedCount = 0

        for item in items {
            totalCloudBytes += item.fileSize
            if item.isReclaimable {
                reclaimableBytes += item.allocatedSize
                downloadedCount += 1
            }
        }

        return ScanResult(
            items: items,
            folderNodes: folderNodes,
            totalCloudBytes: totalCloudBytes,
            reclaimableBytes: reclaimableBytes,
            downloadedCount: downloadedCount,
            totalFilesCount: items.count
        )
    }

    private func buildFolderTree(
        from stats: [String: (url: URL, name: String, relative: String, totalBytes: Int64, reclaimableBytes: Int64, totalCount: Int, downloadedCount: Int)],
        rootPath: String,
        providerId: String
    ) -> [CloudFolderNode] {
        // Collect all folders except root
        var folderMap: [String: CloudFolderNode] = [:]

        for (path, stat) in stats where path != rootPath && stat.totalCount > 0 {
            let node = CloudFolderNode(
                url: stat.url,
                name: stat.name,
                relativePath: stat.relative,
                providerId: providerId,
                totalCloudBytes: stat.totalBytes,
                reclaimableBytes: stat.reclaimableBytes,
                totalFilesCount: stat.totalCount,
                downloadedFilesCount: stat.downloadedCount,
                children: []
            )
            folderMap[path] = node
        }

        // Build parent-child tree
        var topLevelNodes: [CloudFolderNode] = []

        for (_, node) in folderMap {
            let parentPath = node.url.deletingLastPathComponent().standardizedFileURL.path
            if parentPath == rootPath {
                topLevelNodes.append(node)
            }
        }

        // Nest children
        func populateChildren(for node: inout CloudFolderNode) {
            let parentPath = node.url.standardizedFileURL.path
            var children: [CloudFolderNode] = []
            for (_, childCandidate) in folderMap {
                let candidateParent = childCandidate.url.deletingLastPathComponent().standardizedFileURL.path
                if candidateParent == parentPath {
                    var child = childCandidate
                    populateChildren(for: &child)
                    children.append(child)
                }
            }
            // Sort children by reclaimable bytes descending
            children.sort { $0.reclaimableBytes > $1.reclaimableBytes }
            node.children = children
        }

        for i in 0..<topLevelNodes.count {
            populateChildren(for: &topLevelNodes[i])
        }

        topLevelNodes.sort { $0.reclaimableBytes > $1.reclaimableBytes }
        return topLevelNodes
    }
}
