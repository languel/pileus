import Foundation

public enum SortField: String, CaseIterable, Identifiable, Sendable {
    case allocatedSize = "Local Disk Space"
    case fileSize = "File Size"
    case name = "File Name"
    case modifiedDate = "Date Modified"
    case status = "Sync Status"

    public var id: String { rawValue }
}

public struct SortOption: Sendable, Equatable {
    public var field: SortField = .allocatedSize
    public var ascending: Bool = false // Default to largest first for sizes

    public init(field: SortField = .allocatedSize, ascending: Bool = false) {
        self.field = field
        self.ascending = ascending
    }

    public func comparator(lhs: CloudItem, rhs: CloudItem) -> Bool {
        switch field {
        case .allocatedSize:
            if lhs.allocatedSize != rhs.allocatedSize {
                return ascending ? lhs.allocatedSize < rhs.allocatedSize : lhs.allocatedSize > rhs.allocatedSize
            }
            return lhs.fileSize > rhs.fileSize
        case .fileSize:
            if lhs.fileSize != rhs.fileSize {
                return ascending ? lhs.fileSize < rhs.fileSize : lhs.fileSize > rhs.fileSize
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        case .name:
            let cmp = lhs.name.localizedStandardCompare(rhs.name)
            return ascending ? cmp == .orderedAscending : cmp == .orderedDescending
        case .modifiedDate:
            let lDate = lhs.modificationDate ?? Date.distantPast
            let rDate = rhs.modificationDate ?? Date.distantPast
            return ascending ? lDate < rDate : lDate > rDate
        case .status:
            let cmp = lhs.syncStatus.rawValue.localizedStandardCompare(rhs.syncStatus.rawValue)
            return ascending ? cmp == .orderedAscending : cmp == .orderedDescending
        }
    }
}
