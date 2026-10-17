import Foundation

public enum StatusFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All Files"
    case downloadedOnly = "Downloaded Only"
    case cloudOnly = "Cloud Only"
    case syncingOnly = "Syncing / Edits"

    public var id: String { rawValue }
}

public enum SizeFilter: String, CaseIterable, Identifiable, Sendable {
    case any = "Any Size"
    case greaterThan10MB = "> 10 MB"
    case greaterThan50MB = "> 50 MB"
    case greaterThan100MB = "> 100 MB"
    case greaterThan500MB = "> 500 MB"
    case greaterThan1GB = "> 1 GB"

    public var id: String { rawValue }

    public var minimumBytes: Int64 {
        switch self {
        case .any: return 0
        case .greaterThan10MB: return 10 * 1024 * 1024
        case .greaterThan50MB: return 50 * 1024 * 1024
        case .greaterThan100MB: return 100 * 1024 * 1024
        case .greaterThan500MB: return 500 * 1024 * 1024
        case .greaterThan1GB: return 1024 * 1024 * 1024
        }
    }
}

public enum AgeFilter: String, CaseIterable, Identifiable, Sendable {
    case any = "Any Age"
    case olderThan7Days = "> 7 Days Old"
    case olderThan30Days = "> 30 Days Old"
    case olderThan90Days = "> 90 Days Old"
    case olderThan180Days = "> 6 Months Old"
    case olderThan1Year = "> 1 Year Old"

    public var id: String { rawValue }

    public var days: Int {
        switch self {
        case .any: return 0
        case .olderThan7Days: return 7
        case .olderThan30Days: return 30
        case .olderThan90Days: return 90
        case .olderThan180Days: return 180
        case .olderThan1Year: return 365
        }
    }
}

public enum FileKindFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All Kinds"
    case video = "Videos"
    case audio = "Audio"
    case image = "Images"
    case document = "Documents"
    case archive = "Archives"
    case code = "Code / Data"

    public var id: String { rawValue }

    public var matchingKind: FileKind? {
        switch self {
        case .all: return nil
        case .video: return .video
        case .audio: return .audio
        case .image: return .image
        case .document: return .document
        case .archive: return .archive
        case .code: return .code
        }
    }
}

public struct FilterOptions: Sendable, Equatable {
    public var searchText: String = ""
    public var statusFilter: StatusFilter = .all
    public var sizeFilter: SizeFilter = .any
    public var ageFilter: AgeFilter = .any
    public var kindFilter: FileKindFilter = .all
    public var selectedFolderPrefix: String? = nil

    public init() {}

    public var isUnfiltered: Bool {
        return searchText.isEmpty &&
               statusFilter == .all &&
               sizeFilter == .any &&
               ageFilter == .any &&
               kindFilter == .all &&
               (selectedFolderPrefix == nil || selectedFolderPrefix?.isEmpty == true)
    }

    /// Batch filters an array of items using pre-computed filter thresholds.
    public func filter(items: [CloudItem]) -> [CloudItem] {
        if isUnfiltered {
            return items
        }

        let hasQuery = !searchText.isEmpty
        let query = searchText
        let folderPrefix = (selectedFolderPrefix?.isEmpty == false) ? selectedFolderPrefix : nil
        let minBytes = sizeFilter.minimumBytes
        let cutoffDate: Date? = ageFilter.days > 0 ? Date().addingTimeInterval(-Double(ageFilter.days * 86400)) : nil
        let targetKind = kindFilter.matchingKind
        let status = statusFilter

        var result: [CloudItem] = []
        result.reserveCapacity(min(items.count, 4096))

        for item in items {
            // 1. Fast integer / enum checks first before string comparisons
            switch status {
            case .all:
                break
            case .downloadedOnly:
                if item.syncStatus != .downloaded { continue }
            case .cloudOnly:
                if item.syncStatus != .cloudOnly { continue }
            case .syncingOnly:
                let s = item.syncStatus
                if s != .uploading && s != .downloading && s != .unsynced && s != .conflict {
                    continue
                }
            }

            if minBytes > 0 {
                let effectiveSize = item.isReclaimable ? item.allocatedSize : item.fileSize
                if effectiveSize < minBytes { continue }
            }

            if let targetKind = targetKind {
                if item.kind != targetKind { continue }
            }

            if let cutoff = cutoffDate {
                guard let refDate = item.lastAccessDate ?? item.modificationDate ?? item.creationDate,
                      refDate <= cutoff else {
                    continue
                }
            }

            if let prefix = folderPrefix {
                if !item.relativePath.hasPrefix(prefix) { continue }
            }

            if hasQuery {
                if item.name.range(of: query, options: .caseInsensitive) == nil &&
                   item.relativePath.range(of: query, options: .caseInsensitive) == nil {
                    continue
                }
            }

            result.append(item)
        }

        return result
    }

    public func matches(item: CloudItem) -> Bool {
        // Status filter
        switch statusFilter {
        case .all:
            break
        case .downloadedOnly:
            if item.syncStatus != .downloaded { return false }
        case .cloudOnly:
            if item.syncStatus != .cloudOnly { return false }
        case .syncingOnly:
            if item.syncStatus != .uploading && item.syncStatus != .downloading && item.syncStatus != .unsynced && item.syncStatus != .conflict {
                return false
            }
        }

        // Size filter
        if sizeFilter.minimumBytes > 0 {
            let effectiveSize = item.isReclaimable ? item.allocatedSize : item.fileSize
            if effectiveSize < sizeFilter.minimumBytes {
                return false
            }
        }

        // Kind filter
        if let targetKind = kindFilter.matchingKind {
            if item.kind != targetKind {
                return false
            }
        }

        // Age filter
        if ageFilter.days > 0 {
            let referenceDate = item.lastAccessDate ?? item.modificationDate ?? item.creationDate
            guard let date = referenceDate else { return false }
            let cutoff = Date().addingTimeInterval(-Double(ageFilter.days * 86400))
            if date > cutoff {
                return false
            }
        }

        // Folder filter
        if let prefix = selectedFolderPrefix, !prefix.isEmpty {
            if !item.relativePath.hasPrefix(prefix) {
                return false
            }
        }

        // Search text
        if !searchText.isEmpty {
            if item.name.range(of: searchText, options: .caseInsensitive) == nil &&
               item.relativePath.range(of: searchText, options: .caseInsensitive) == nil {
                return false
            }
        }

        return true
    }
}
