import Foundation
import CryptoKit
import Darwin

/// Resolution strategies when deduplicating files to a chosen primary copy.
public enum DuplicateResolutionStrategy: String, CaseIterable, Identifiable, Sendable {
    case symlink = "POSIX Symbolic Link (ln -s)"
    case macOSAlias = "macOS Finder Alias / Bookmark"
    case apfsClone = "APFS Copy-on-Write Clone (Zero Disk Space)"
    case trashDuplicates = "Move Duplicates to Trash"

    public var id: String { rawValue }

    public var shortTitle: String {
        switch self {
        case .symlink: return "Symbolic Link"
        case .macOSAlias: return "Finder Alias"
        case .apfsClone: return "APFS CoW Clone"
        case .trashDuplicates: return "Move to Trash"
        }
    }

    public var icon: String {
        switch self {
        case .symlink: return "link"
        case .macOSAlias: return "arrowshape.turn.up.right.circle.fill"
        case .apfsClone: return "doc.on.doc.fill"
        case .trashDuplicates: return "trash.fill"
        }
    }

    public var summaryDescription: String {
        switch self {
        case .symlink:
            return "Replaces each duplicate with a POSIX symbolic link pointing to the Primary file. Transparent to CLI tools, scripts, and code projects."
        case .macOSAlias:
            return "Replaces each duplicate with a native macOS Finder Alias (Bookmark) pointing to the Primary file. Ideal for iCloud Drive & Google Drive, and survives if the primary file is moved or renamed."
        case .apfsClone:
            return "Replaces each duplicate with an APFS Copy-on-Write clone (clonefile) of the Primary file. Shares 100% of physical disk blocks on your Mac (0 extra local space) while remaining an independent regular file."
        case .trashDuplicates:
            return "Moves all non-primary duplicate copies to the macOS Trash without leaving a link behind."
        }
    }
}

/// Platform and cloud-provider compatibility warning for a given duplicate resolution strategy.
public struct DuplicatePlatformWarning: Identifiable, Sendable {
    public enum Severity: Sendable {
        case info
        case caution
        case danger
    }

    public let id = UUID()
    public let severity: Severity
    public let title: String
    public let message: String
}

/// Represents a group of identical files sharing the same byte size and content hash.
public struct DuplicateGroup: Identifiable, Hashable, Sendable {
    public let id: String
    public let contentHash: String
    public let fileSize: Int64
    public var items: [CloudItem]
    public var primaryItemId: UUID
    public let isVerifiedFullHash: Bool

    public init(
        id: String,
        contentHash: String,
        fileSize: Int64,
        items: [CloudItem],
        primaryItemId: UUID? = nil,
        isVerifiedFullHash: Bool = true
    ) {
        self.id = id
        self.contentHash = contentHash
        self.fileSize = fileSize
        self.items = items
        self.primaryItemId = primaryItemId ?? items.first?.id ?? UUID()
        self.isVerifiedFullHash = isVerifiedFullHash
    }

    public var primaryItem: CloudItem? {
        items.first(where: { $0.id == primaryItemId }) ?? items.first
    }

    public var duplicateItems: [CloudItem] {
        guard let primary = primaryItem else { return [] }
        return items.filter { $0.id != primary.id }
    }

    /// Logical redundant bytes across all non-primary copies.
    public var redundantLogicalBytes: Int64 {
        Int64(max(0, items.count - 1)) * fileSize
    }

    /// Local disk space currently occupied by non-primary copies that will be freed on Mac.
    public var reclaimableLocalBytes: Int64 {
        duplicateItems.reduce(0) { $0 + $1.allocatedSize }
    }

    public var sampleName: String {
        primaryItem?.name ?? items.first?.name ?? "Duplicate File"
    }

    public var kind: FileKind {
        primaryItem?.kind ?? items.first?.kind ?? .other
    }
}

public struct DuplicateScanProgress: Sendable {
    public enum Phase: String, Sendable {
        case groupingBySize = "Grouping files by size..."
        case partialHashing = "Sampling 64 KB head/tail fingerprints..."
        case fullHashing = "Verifying full SHA-256 cryptographic hashes..."
        case complete = "Duplicate scan complete"
    }

    public let phase: Phase
    public let processedCount: Int
    public let totalCandidates: Int
    public let groupsFound: Int
    public let redundantBytesFound: Int64
}

public struct DuplicateResolutionReport: Sendable {
    public let strategy: DuplicateResolutionStrategy
    public let groupsResolved: Int
    public let duplicatesReplaced: Int
    public let localBytesReclaimed: Int64
    public let cloudBytesReclaimed: Int64
    public let failedItems: [(path: String, reason: String)]
    public let resolvedDuplicateIds: Set<UUID>
}

public final class DuplicateService: Sendable {
    public static let shared = DuplicateService()

    private static let sampleChunkSize = 32 * 1024 // 32 KB head + 32 KB tail

    /// Evaluates platform-specific caveats when linking duplicates across Local Drives, iCloud Drive, Google Drive, OneDrive, and Dropbox.
    public func evaluateWarnings(
        strategy: DuplicateResolutionStrategy,
        groups: [DuplicateGroup],
        providersById: [String: CloudProvider]
    ) -> [DuplicatePlatformWarning] {
        var warnings: [DuplicatePlatformWarning] = []

        var targetProviderTypes = Set<ProviderType>()
        var hasCrossProviderLink = false
        var hasDatalessPrimary = false
        var unverifiedCloudGroupCount = 0

        for group in groups {
            if !group.isVerifiedFullHash {
                unverifiedCloudGroupCount += 1
            }
            guard let primary = group.primaryItem else { continue }
            if primary.isDataless {
                hasDatalessPrimary = true
            }
            let primaryProv = providersById[primary.providerId]
            for dup in group.duplicateItems {
                if let dupProv = providersById[dup.providerId] {
                    targetProviderTypes.insert(dupProv.type)
                    if let pType = primaryProv?.type, pType != dupProv.type || primary.providerId != dup.providerId {
                        hasCrossProviderLink = true
                    }
                }
            }
        }

        if unverifiedCloudGroupCount > 0 {
            warnings.append(DuplicatePlatformWarning(
                severity: .caution,
                title: "Contains Undownloaded Cloud-Only Files (Matched by Exact Size + Filename)",
                message: "\(unverifiedCloudGroupCount) \(unverifiedCloudGroupCount == 1 ? "group includes" : "groups include") cloud-only (evicted) files that were matched by exact byte size + filename without downloading their contents. Please verify paths before replacing or deleting."
            ))
        }

        switch strategy {
        case .symlink:
            if targetProviderTypes.contains(.googleDrive) {
                warnings.append(DuplicatePlatformWarning(
                    severity: .caution,
                    title: "Google Drive & Symbolic Links",
                    message: "Google Drive for macOS (File Provider) ignores POSIX symbolic links or does not sync them to Google Drive web. Replacing a Google Drive file with a symlink removes the duplicate from cloud sync while keeping the symlink working locally on this Mac."
                ))
            }
            if targetProviderTypes.contains(.iCloud) {
                warnings.append(DuplicatePlatformWarning(
                    severity: .caution,
                    title: "iCloud Drive & Symbolic Links",
                    message: "POSIX symlinks inside iCloud Drive use absolute paths on this Mac. They work for local apps and terminal tools, but will break on iOS/iPadOS or another Mac if the path or username differs."
                ))
            }
            if targetProviderTypes.contains(.dropbox) || targetProviderTypes.contains(.oneDrive) {
                warnings.append(DuplicatePlatformWarning(
                    severity: .caution,
                    title: "Dropbox / OneDrive Symlink Traversal",
                    message: "Dropbox and OneDrive may either skip symlinks or follow them and re-upload the target file into the cloud folder. Prefer 'macOS Finder Alias' for cloud drives."
                ))
            }
            if warnings.isEmpty {
                warnings.append(DuplicatePlatformWarning(
                    severity: .info,
                    title: "POSIX Symbolic Link (ln -s)",
                    message: "Creates a standard filesystem symlink pointing to the Primary file. Works transparently with command-line tools, compilers, and local applications. Best for local drives."
                ))
            }

        case .macOSAlias:
            warnings.append(DuplicatePlatformWarning(
                severity: .info,
                title: "macOS Finder Alias / Drive Bookmark (Cloud-Safe)",
                message: "Creates a native macOS Alias file (~1–4 KB) pointing to the Primary copy. Cloud providers (iCloud Drive, Google Drive, OneDrive, Dropbox) sync Alias files safely as lightweight data files without re-uploading the target or breaking sync."
            ))
            warnings.append(DuplicatePlatformWarning(
                severity: .caution,
                title: "Finder vs. CLI Behavior",
                message: "Double-clicking a Finder Alias in Finder or standard macOS Open dialogs opens the Primary file even if the Primary is later moved or renamed. However, POSIX CLI tools (e.g. `cat`, `python`, `node`) do not automatically resolve Finder Aliases."
            ))

        case .apfsClone:
            warnings.append(DuplicatePlatformWarning(
                severity: .info,
                title: "APFS Copy-on-Write Clone (Local Zero-Cost Copy)",
                message: "Uses macOS `clonefile(2)` so the duplicate shares the exact same physical APFS storage blocks on your Mac SSD as the Primary file (consuming 0 additional local disk bytes) while appearing as a normal, independent file."
            ))
            if hasCrossProviderLink {
                warnings.append(DuplicatePlatformWarning(
                    severity: .caution,
                    title: "Same APFS Volume Required",
                    message: "APFS clones only work when the Primary and Duplicate reside on the same APFS volume/partition. Cross-drive items will fail safely without deleting the original."
                ))
            }
            if !targetProviderTypes.subtracting([.custom]).isEmpty {
                warnings.append(DuplicatePlatformWarning(
                    severity: .caution,
                    title: "Cloud Quota Notice",
                    message: "While an APFS clone uses 0 extra bytes on your Mac's SSD, cloud providers still see it as a full regular file and will count it toward your cloud storage quota."
                ))
            }

        case .trashDuplicates:
            warnings.append(DuplicatePlatformWarning(
                severity: .danger,
                title: "Moves Duplicate Copies to Trash (No Link Created)",
                message: "All non-primary copies in the selected groups will be moved to your Mac's Trash (and removed from cloud folders if located inside iCloud Drive or Google Drive). The Primary copy is kept untouched."
            ))
        }

        if hasDatalessPrimary && strategy == .apfsClone {
            warnings.append(DuplicatePlatformWarning(
                severity: .danger,
                title: "Primary File is Cloud-Only",
                message: "One or more selected Primary files are currently cloud-only (evicted). APFS cloning requires the Primary copy to be downloaded locally first."
            ))
        }

        return warnings
    }

    /// Scans the given items for exact content duplicates using a 3-stage pipeline:
    /// Stage 1: Exact `fileSize` grouping (O(N), zero disk I/O).
    /// Stage 2: Fast 64 KB head+tail SHA-256 fingerprint on local downloaded files of identical size.
    /// Stage 3: Full streaming SHA-256 verification on remaining downloaded candidates, plus Cloud-Only (or Mixed Local+Cloud)
    ///          exact `fileSize + filename` matching so undownloaded cloud files can also be deduplicated without downloading them.
    public func findDuplicates(
        items: [CloudItem],
        minimumFileSize: Int64 = 1024, // Default >= 1 KB
        includeCloudOnlyByNameAndSize: Bool = true,
        control: ScanSessionControl? = nil,
        onProgress: (@Sendable (DuplicateScanProgress) -> Void)? = nil
    ) async -> [DuplicateGroup] {
        return await Task.detached(priority: .userInitiated) {
            // Stage 1: Group by exact logical fileSize
            onProgress?(DuplicateScanProgress(
                phase: .groupingBySize,
                processedCount: 0,
                totalCandidates: items.count,
                groupsFound: 0,
                redundantBytesFound: 0
            ))

            var bySize: [Int64: [CloudItem]] = [:]
            bySize.reserveCapacity(min(items.count, 16384))

            for item in items {
                guard item.fileSize >= minimumFileSize else { continue }
                if !includeCloudOnlyByNameAndSize && item.isDataless {
                    // Never read bytes from a dataless cloud stub because reading it would trigger an unwanted download!
                    continue
                }
                bySize[item.fileSize, default: []].append(item)
            }

            let sizeBuckets = bySize.values.filter { $0.count > 1 }
            let totalCandidates = sizeBuckets.reduce(0) { $0 + $1.count }
            if totalCandidates == 0 {
                onProgress?(DuplicateScanProgress(
                    phase: .complete,
                    processedCount: 0,
                    totalCandidates: 0,
                    groupsFound: 0,
                    redundantBytesFound: 0
                ))
                return []
            }

            // Stage 2: Partial 64KB (32KB head + 32KB tail) hash for downloaded files;
            //          Collect cloud-only items by (fileSize, normalizedName) so they can attach to matching downloaded groups
            //          OR form pure/mixed Cloud Name+Size duplicate groups without triggering any cloud downloads.
            var partialBuckets: [String: [CloudItem]] = [:]
            var cloudOnlyBySizeAndName: [String: [CloudItem]] = [:]
            var downloadedBySizeAndName: [String: [CloudItem]] = [:]
            var processed = 0
            var lastProgressTime = CFAbsoluteTimeGetCurrent()

            for bucket in sizeBuckets {
                if (control?.isStopped ?? false) || Task.isCancelled { break }
                if let ctrl = control, !ctrl.waitIfPaused() { break }

                for item in bucket {
                    processed += 1
                    let sizeNameKey = "\(item.fileSize):\(item.name.lowercased())"
                    if item.isDataless {
                        cloudOnlyBySizeAndName[sizeNameKey, default: []].append(item)
                    } else {
                        downloadedBySizeAndName[sizeNameKey, default: []].append(item)
                        if let partialHash = Self.computePartialHash(path: item.path, fileSize: item.fileSize) {
                            let key = "partial:\(item.fileSize):\(partialHash)"
                            partialBuckets[key, default: []].append(item)
                        }
                    }

                    let now = CFAbsoluteTimeGetCurrent()
                    if now - lastProgressTime >= 0.15 {
                        lastProgressTime = now
                        onProgress?(DuplicateScanProgress(
                            phase: .partialHashing,
                            processedCount: processed,
                            totalCandidates: totalCandidates,
                            groupsFound: 0,
                            redundantBytesFound: 0
                        ))
                    }
                }
            }

            let candidatePartialGroups = partialBuckets.filter { $0.value.count > 1 }
            let fullHashTotal = candidatePartialGroups.values.reduce(0) { $0 + $1.count }

            // Stage 3: Full SHA-256 verification on downloaded files that matched size + head/tail sample
            var verifiedGroups: [DuplicateGroup] = []
            var fullProcessed = 0
            var runningRedundantBytes: Int64 = 0
            var assignedItemIds = Set<UUID>()

            for (partialKey, groupItems) in candidatePartialGroups {
                if (control?.isStopped ?? false) || Task.isCancelled { break }
                if let ctrl = control, !ctrl.waitIfPaused() { break }

                let sampleSize = groupItems[0].fileSize
                // If fileSize <= 64 KB, the partial hash already read 100% of the file!
                if sampleSize <= Int64(Self.sampleChunkSize * 2) {
                    let hashHex = String(partialKey.split(separator: ":").last ?? "")
                    var combinedItems = groupItems
                    var hasCloudOnlyAttached = false

                    if includeCloudOnlyByNameAndSize {
                        let namesInGroup = Set(groupItems.map { "\(sampleSize):\($0.name.lowercased())" })
                        for snKey in namesInGroup {
                            if let cloudMatches = cloudOnlyBySizeAndName[snKey] {
                                for cItem in cloudMatches where !assignedItemIds.contains(cItem.id) {
                                    combinedItems.append(cItem)
                                    assignedItemIds.insert(cItem.id)
                                    hasCloudOnlyAttached = true
                                }
                            }
                        }
                    }

                    for dItem in groupItems {
                        assignedItemIds.insert(dItem.id)
                    }

                    let sorted = Self.sortDefaultPrimaryFirst(combinedItems)
                    let group = DuplicateGroup(
                        id: "sha256:\(sampleSize):\(hashHex)",
                        contentHash: hasCloudOnlyAttached ? "\(hashHex) (+ Cloud Size+Name Match)" : hashHex,
                        fileSize: sampleSize,
                        items: sorted,
                        primaryItemId: sorted[0].id,
                        isVerifiedFullHash: !hasCloudOnlyAttached
                    )
                    verifiedGroups.append(group)
                    runningRedundantBytes += group.redundantLogicalBytes
                    fullProcessed += groupItems.count
                    continue
                }

                var byFullHash: [String: [CloudItem]] = [:]
                for item in groupItems {
                    if (control?.isStopped ?? false) || Task.isCancelled { break }
                    if let ctrl = control, !ctrl.waitIfPaused() { break }

                    fullProcessed += 1
                    if let fullHash = Self.computeFullSHA256(path: item.path, control: control) {
                        byFullHash[fullHash, default: []].append(item)
                    }

                    let now = CFAbsoluteTimeGetCurrent()
                    if now - lastProgressTime >= 0.15 {
                        lastProgressTime = now
                        onProgress?(DuplicateScanProgress(
                            phase: .fullHashing,
                            processedCount: fullProcessed,
                            totalCandidates: fullHashTotal,
                            groupsFound: verifiedGroups.count,
                            redundantBytesFound: runningRedundantBytes
                        ))
                    }
                }

                for (fullHash, matched) in byFullHash where matched.count > 1 {
                    var combinedItems = matched
                    var hasCloudOnlyAttached = false

                    if includeCloudOnlyByNameAndSize {
                        let namesInGroup = Set(matched.map { "\(sampleSize):\($0.name.lowercased())" })
                        for snKey in namesInGroup {
                            if let cloudMatches = cloudOnlyBySizeAndName[snKey] {
                                for cItem in cloudMatches where !assignedItemIds.contains(cItem.id) {
                                    combinedItems.append(cItem)
                                    assignedItemIds.insert(cItem.id)
                                    hasCloudOnlyAttached = true
                                }
                            }
                        }
                    }

                    for dItem in matched {
                        assignedItemIds.insert(dItem.id)
                    }

                    let sorted = Self.sortDefaultPrimaryFirst(combinedItems)
                    let group = DuplicateGroup(
                        id: "sha256:\(sampleSize):\(fullHash)",
                        contentHash: hasCloudOnlyAttached ? "\(fullHash) (+ Cloud Size+Name Match)" : fullHash,
                        fileSize: sampleSize,
                        items: sorted,
                        primaryItemId: sorted[0].id,
                        isVerifiedFullHash: !hasCloudOnlyAttached
                    )
                    verifiedGroups.append(group)
                    runningRedundantBytes += group.redundantLogicalBytes
                }
            }

            // Stage 4: Form Cloud-Only (and Mixed 1-Downloaded + Cloud-Only) duplicate groups by exact Size + Filename
            if includeCloudOnlyByNameAndSize {
                for (snKey, cloudItems) in cloudOnlyBySizeAndName {
                    if (control?.isStopped ?? false) || Task.isCancelled { break }
                    var unassignedCloud = cloudItems.filter { !assignedItemIds.contains($0.id) }
                    guard !unassignedCloud.isEmpty else { continue }

                    // Also include any downloaded item with the exact same size + filename that wasn't already part of a multi-downloaded group
                    if let localMatches = downloadedBySizeAndName[snKey] {
                        for lItem in localMatches where !assignedItemIds.contains(lItem.id) {
                            unassignedCloud.append(lItem)
                            assignedItemIds.insert(lItem.id)
                        }
                    }

                    if unassignedCloud.count > 1 {
                        for item in unassignedCloud {
                            assignedItemIds.insert(item.id)
                        }
                        let sorted = Self.sortDefaultPrimaryFirst(unassignedCloud)
                        let group = DuplicateGroup(
                            id: "cloudonly:\(snKey)",
                            contentHash: "Unverified (Cloud Size + Filename Match)",
                            fileSize: sorted[0].fileSize,
                            items: sorted,
                            primaryItemId: sorted[0].id,
                            isVerifiedFullHash: false
                        )
                        verifiedGroups.append(group)
                        runningRedundantBytes += group.redundantLogicalBytes
                    }
                }
            }

            verifiedGroups.sort {
                if $0.redundantLogicalBytes != $1.redundantLogicalBytes {
                    return $0.redundantLogicalBytes > $1.redundantLogicalBytes
                }
                return $0.fileSize > $1.fileSize
            }

            onProgress?(DuplicateScanProgress(
                phase: .complete,
                processedCount: fullHashTotal,
                totalCandidates: fullHashTotal,
                groupsFound: verifiedGroups.count,
                redundantBytesFound: runningRedundantBytes
            ))

            return verifiedGroups
        }.value
    }

    /// Chooses a sensible default Primary copy (prefers downloaded files, shortest path depth, and oldest creation date).
    private static func sortDefaultPrimaryFirst(_ items: [CloudItem]) -> [CloudItem] {
        return items.sorted { lhs, rhs in
            if lhs.isDataless != rhs.isDataless {
                return !lhs.isDataless
            }
            let lhsDepth = lhs.relativePath.utf8.filter { $0 == UInt8(ascii: "/") }.count
            let rhsDepth = rhs.relativePath.utf8.filter { $0 == UInt8(ascii: "/") }.count
            if lhsDepth != rhsDepth {
                return lhsDepth < rhsDepth
            }
            if let lCreate = lhs.creationDate, let rCreate = rhs.creationDate, lCreate != rCreate {
                return lCreate < rCreate
            }
            return lhs.path < rhs.path
        }
    }

    /// Reads at most 32 KB from the start and 32 KB from the end of a local file without triggering cloud downloads.
    private static func computePartialHash(path: String, fileSize: Int64) -> String? {
        // Double-check file is not dataless right before opening
        let statInfo = DatalessDetector.statInfo(forPath: path)
        if statInfo.isDataless { return nil }

        let fd = open(path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var hasher = SHA256()
        let chunk = Self.sampleChunkSize
        var buffer = [UInt8](repeating: 0, count: chunk)

        let headBytesRead = buffer.withUnsafeMutableBytes { rawPtr -> Int in
            guard let base = rawPtr.baseAddress else { return -1 }
            return pread(fd, base, chunk, 0)
        }
        guard headBytesRead > 0 else { return nil }
        hasher.update(data: buffer.prefix(headBytesRead))

        if fileSize > Int64(chunk) {
            let tailOffset = max(Int64(chunk), fileSize - Int64(chunk))
            let tailBytesRead = buffer.withUnsafeMutableBytes { rawPtr -> Int in
                guard let base = rawPtr.baseAddress else { return -1 }
                return pread(fd, base, chunk, off_t(tailOffset))
            }
            if tailBytesRead > 0 {
                hasher.update(data: buffer.prefix(tailBytesRead))
            }
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Computes the full streaming SHA-256 hash of a local file in 256 KB chunks.
    private static func computeFullSHA256(path: String, control: ScanSessionControl?) -> String? {
        let statInfo = DatalessDetector.statInfo(forPath: path)
        if statInfo.isDataless { return nil }

        let fd = open(path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        // Advise kernel of sequential read
        _ = fcntl(fd, F_RDAHEAD, 1)

        var hasher = SHA256()
        let bufferSize = 256 * 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        while true {
            if (control?.isStopped ?? false) || Task.isCancelled { return nil }
            let bytesRead = buffer.withUnsafeMutableBytes { rawPtr -> Int in
                guard let base = rawPtr.baseAddress else { return -1 }
                return read(fd, base, bufferSize)
            }
            if bytesRead < 0 {
                return nil
            }
            if bytesRead == 0 {
                break
            }
            hasher.update(data: buffer.prefix(bytesRead))
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Safe Resolution (Symlink, Finder Alias, APFS Clone, or Trash)

    /// Resolves the given duplicate groups by replacing non-primary copies with a link/clone to each group's chosen Primary file.
    /// If `relocatePrimaryToDirectory` is provided, first moves the Primary file into that canonical destination folder,
    /// places a link at the Primary's original location pointing to the new canonical file, and links all duplicates to the new canonical file!
    /// Uses a safe atomic staging pattern: backs up files before replacing and restores on error so data is NEVER lost.
    public func resolveDuplicates(
        groups: [DuplicateGroup],
        strategy: DuplicateResolutionStrategy,
        useRelativeSymlinksWhenSameSource: Bool = true,
        relocatePrimaryToDirectory: URL? = nil,
        control: ScanSessionControl? = nil
    ) async -> DuplicateResolutionReport {
        return await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            var groupsResolved = 0
            var duplicatesReplaced = 0
            var localBytesReclaimed: Int64 = 0
            var cloudBytesReclaimed: Int64 = 0
            var failedItems: [(path: String, reason: String)] = []
            var resolvedIds = Set<UUID>()

            if let destDir = relocatePrimaryToDirectory {
                try? fm.createDirectory(at: destDir, withIntermediateDirectories: true)
            }

            for group in groups {
                if (control?.isStopped ?? false) || Task.isCancelled { break }
                if let ctrl = control, !ctrl.waitIfPaused() { break }

                guard let primary = group.primaryItem else { continue }
                let originalPrimaryURL = URL(fileURLWithPath: primary.path)

                guard fm.fileExists(atPath: primary.path) else {
                    failedItems.append((path: primary.path, reason: "Primary file no longer exists on disk."))
                    continue
                }

                // Step 1: Optionally relocate the Primary copy into the user's chosen canonical destination folder
                var effectivePrimaryURL = originalPrimaryURL
                var relocatedPrimaryFromOriginal = false

                if let destDir = relocatePrimaryToDirectory {
                    let targetURL = Self.uniqueDestinationURL(in: destDir, fileName: originalPrimaryURL.lastPathComponent, existingPrimaryURL: originalPrimaryURL)
                    if targetURL.standardizedFileURL.path != originalPrimaryURL.standardizedFileURL.path {
                        do {
                            try fm.moveItem(at: originalPrimaryURL, to: targetURL)
                            effectivePrimaryURL = targetURL
                            relocatedPrimaryFromOriginal = true

                            // Leave a link at the Primary's original location pointing to the new canonical location
                            // (For `.trashDuplicates`, we still leave a Finder Alias or Symlink at the old primary location if requested,
                            // or if strategy is a link/clone strategy, use that exact strategy!)
                            let primaryLinkStrategy: DuplicateResolutionStrategy = (strategy == .trashDuplicates) ? .symlink : strategy
                            do {
                                try Self.createLinkAtEmptySlot(
                                    slotURL: originalPrimaryURL,
                                    targetPrimaryURL: effectivePrimaryURL,
                                    strategy: primaryLinkStrategy,
                                    useRelativePath: useRelativeSymlinksWhenSameSource
                                )
                            } catch {
                                // Rollback move if linking the primary's original slot failed
                                try? fm.moveItem(at: effectivePrimaryURL, to: originalPrimaryURL)
                                effectivePrimaryURL = originalPrimaryURL
                                relocatedPrimaryFromOriginal = false
                                failedItems.append((path: primary.path, reason: "Failed to link original primary path after moving: \(error.localizedDescription)"))
                                continue
                            }
                        } catch {
                            failedItems.append((path: primary.path, reason: "Failed to move primary to destination folder: \(error.localizedDescription)"))
                            continue
                        }
                    }
                }

                var anyReplacedInGroup = relocatedPrimaryFromOriginal

                // Step 2: Replace all non-primary duplicate copies with links/clones pointing to `effectivePrimaryURL`
                for dup in group.duplicateItems {
                    if (control?.isStopped ?? false) || Task.isCancelled { break }
                    if dup.path == effectivePrimaryURL.path { continue }

                    let dupURL = URL(fileURLWithPath: dup.path)
                    guard fm.fileExists(atPath: dup.path) else {
                        failedItems.append((path: dup.path, reason: "Duplicate file not found."))
                        continue
                    }

                    let canUseRelative = useRelativeSymlinksWhenSameSource && (
                        relocatePrimaryToDirectory != nil || dup.providerId == primary.providerId
                    )

                    do {
                        switch strategy {
                        case .trashDuplicates:
                            try fm.trashItem(at: dupURL, resultingItemURL: nil)

                        case .symlink:
                            try Self.replaceWithSymlinkAtomically(
                                duplicateURL: dupURL,
                                primaryURL: effectivePrimaryURL,
                                useRelativePath: canUseRelative
                            )

                        case .macOSAlias:
                            try Self.replaceWithFinderAliasAtomically(
                                duplicateURL: dupURL,
                                primaryURL: effectivePrimaryURL
                            )

                        case .apfsClone:
                            try Self.replaceWithAPFSCloneAtomically(
                                duplicateURL: dupURL,
                                primaryURL: effectivePrimaryURL
                            )
                        }

                        duplicatesReplaced += 1
                        localBytesReclaimed += dup.allocatedSize
                        cloudBytesReclaimed += dup.fileSize
                        resolvedIds.insert(dup.id)
                        anyReplacedInGroup = true
                    } catch {
                        failedItems.append((path: dup.path, reason: error.localizedDescription))
                    }
                }

                if anyReplacedInGroup {
                    groupsResolved += 1
                }
            }

            return DuplicateResolutionReport(
                strategy: strategy,
                groupsResolved: groupsResolved,
                duplicatesReplaced: duplicatesReplaced,
                localBytesReclaimed: localBytesReclaimed,
                cloudBytesReclaimed: cloudBytesReclaimed,
                failedItems: failedItems,
                resolvedDuplicateIds: resolvedIds
            )
        }.value
    }

    /// Computes a collision-free destination URL inside `directory` (e.g. `report.pdf`, `report (2).pdf`).
    private static func uniqueDestinationURL(in directory: URL, fileName: String, existingPrimaryURL: URL) -> URL {
        let fm = FileManager.default
        let candidate = directory.appendingPathComponent(fileName)
        if candidate.standardizedFileURL.path == existingPrimaryURL.standardizedFileURL.path || !fm.fileExists(atPath: candidate.path) {
            return candidate
        }

        let ext = (fileName as NSString).pathExtension
        let baseName = (fileName as NSString).deletingPathExtension
        var counter = 2
        while true {
            let numberedName = ext.isEmpty ? "\(baseName) (\(counter))" : "\(baseName) (\(counter)).\(ext)"
            let numberedURL = directory.appendingPathComponent(numberedName)
            if !fm.fileExists(atPath: numberedURL.path) {
                return numberedURL
            }
            counter += 1
        }
    }

    /// Creates a Symlink, Finder Alias, or APFS Clone at `slotURL` (where the Primary file used to live before relocation).
    private static func createLinkAtEmptySlot(
        slotURL: URL,
        targetPrimaryURL: URL,
        strategy: DuplicateResolutionStrategy,
        useRelativePath: Bool
    ) throws {
        let fm = FileManager.default
        let parentDir = slotURL.deletingLastPathComponent()

        switch strategy {
        case .symlink, .trashDuplicates:
            let destPath = useRelativePath
                ? Self.relativePath(fromDirectory: parentDir.standardizedFileURL.path, toFile: targetPrimaryURL.standardizedFileURL.path)
                : targetPrimaryURL.path
            try fm.createSymbolicLink(atPath: slotURL.path, withDestinationPath: destPath)

        case .macOSAlias:
            let bookmarkData = try targetPrimaryURL.bookmarkData(
                options: [.suitableForBookmarkFile],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            try URL.writeBookmarkData(bookmarkData, to: slotURL)

        case .apfsClone:
            let rc = targetPrimaryURL.path.withCString { srcPtr in
                slotURL.path.withCString { dstPtr in
                    Darwin.clonefile(srcPtr, dstPtr, 0)
                }
            }
            if rc != 0 {
                let errCode = errno
                throw NSError(
                    domain: NSPOSIXErrorDomain,
                    code: Int(errCode),
                    userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errCode))]
                )
            }
        }
    }

    private static func replaceWithSymlinkAtomically(
        duplicateURL: URL,
        primaryURL: URL,
        useRelativePath: Bool
    ) throws {
        let fm = FileManager.default
        let parentDir = duplicateURL.deletingLastPathComponent()
        let backupURL = parentDir.appendingPathComponent(".\(duplicateURL.lastPathComponent).pileus-bak-\(UUID().uuidString.prefix(8))")

        let targetDestination: String
        if useRelativePath {
            targetDestination = Self.relativePath(fromDirectory: parentDir.standardizedFileURL.path, toFile: primaryURL.standardizedFileURL.path)
        } else {
            targetDestination = primaryURL.path
        }

        try fm.moveItem(at: duplicateURL, to: backupURL)
        do {
            try fm.createSymbolicLink(atPath: duplicateURL.path, withDestinationPath: targetDestination)
            try? fm.removeItem(at: backupURL)
        } catch {
            // Rollback so original duplicate is never lost
            try? fm.moveItem(at: backupURL, to: duplicateURL)
            throw error
        }
    }

    private static func replaceWithFinderAliasAtomically(
        duplicateURL: URL,
        primaryURL: URL
    ) throws {
        let fm = FileManager.default
        let parentDir = duplicateURL.deletingLastPathComponent()
        let backupURL = parentDir.appendingPathComponent(".\(duplicateURL.lastPathComponent).pileus-bak-\(UUID().uuidString.prefix(8))")

        // Generate native macOS Finder Alias bookmark data before touching the duplicate file
        let bookmarkData = try primaryURL.bookmarkData(
            options: [.suitableForBookmarkFile],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        try fm.moveItem(at: duplicateURL, to: backupURL)
        do {
            try URL.writeBookmarkData(bookmarkData, to: duplicateURL)
            try? fm.removeItem(at: backupURL)
        } catch {
            try? fm.moveItem(at: backupURL, to: duplicateURL)
            throw error
        }
    }

    private static func replaceWithAPFSCloneAtomically(
        duplicateURL: URL,
        primaryURL: URL
    ) throws {
        let fm = FileManager.default
        let primaryStat = DatalessDetector.statInfo(forPath: primaryURL.path)
        if primaryStat.isDataless {
            throw NSError(
                domain: "Pileus.DuplicateService",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "Primary file is cloud-only (evicted). Download the primary file first before creating an APFS clone."]
            )
        }

        let parentDir = duplicateURL.deletingLastPathComponent()
        let backupURL = parentDir.appendingPathComponent(".\(duplicateURL.lastPathComponent).pileus-bak-\(UUID().uuidString.prefix(8))")

        try fm.moveItem(at: duplicateURL, to: backupURL)
        let rc = primaryURL.path.withCString { srcPtr in
            duplicateURL.path.withCString { dstPtr in
                Darwin.clonefile(srcPtr, dstPtr, 0)
            }
        }

        if rc == 0 {
            try? fm.removeItem(at: backupURL)
        } else {
            let errCode = errno
            try? fm.moveItem(at: backupURL, to: duplicateURL)
            let message = String(cString: strerror(errCode))
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errCode),
                userInfo: [NSLocalizedDescriptionKey: "APFS clonefile failed (\(message)). Ensure both files are on the same APFS drive."]
            )
        }
    }

    /// Computes a clean POSIX relative path from `fromDirectory` to `toFile` (e.g. `../../shared/logo.png`).
    public static func relativePath(fromDirectory baseDirPath: String, toFile targetFilePath: String) -> String {
        let baseComponents = baseDirPath.split(separator: "/").map(String.init)
        let targetComponents = targetFilePath.split(separator: "/").map(String.init)

        var commonCount = 0
        let minLen = min(baseComponents.count, targetComponents.count)
        while commonCount < minLen && baseComponents[commonCount] == targetComponents[commonCount] {
            commonCount += 1
        }

        if commonCount == 0 {
            return targetFilePath
        }

        let upCount = baseComponents.count - commonCount
        var resultParts: [String] = Array(repeating: "..", count: upCount)
        resultParts.append(contentsOf: targetComponents[commonCount...])
        return resultParts.isEmpty ? "." : resultParts.joined(separator: "/")
    }
}
