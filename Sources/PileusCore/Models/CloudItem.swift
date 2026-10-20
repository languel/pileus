import Foundation
import UniformTypeIdentifiers

public enum SyncStatus: String, CaseIterable, Sendable, Codable {
    case downloaded = "Downloaded"
    case cloudOnly = "Cloud Only"
    case uploading = "Uploading..."
    case downloading = "Downloading..."
    case conflict = "Conflict"
    case unsynced = "Unsynced Edits"

    public var isSafeToEvict: Bool {
        return self == .downloaded
    }

    public var iconName: String {
        switch self {
        case .downloaded:
            return "arrow.down.circle.fill"
        case .cloudOnly:
            return "icloud.fill"
        case .uploading:
            return "arrow.up.circle.fill"
        case .downloading:
            return "arrow.down.circle"
        case .conflict:
            return "exclamationmark.triangle.fill"
        case .unsynced:
            return "pencil.circle.fill"
        }
    }

    public var badgeColor: String {
        switch self {
        case .downloaded:
            return "green"
        case .cloudOnly:
            return "blue"
        case .uploading, .downloading:
            return "orange"
        case .conflict, .unsynced:
            return "red"
        }
    }
}

public enum FileKind: String, CaseIterable, Sendable, Codable {
    case video = "Video"
    case audio = "Audio"
    case image = "Image"
    case document = "Document"
    case archive = "Archive"
    case code = "Code / Data"
    case other = "Other"

    public static func kind(for url: URL) -> FileKind {
        return kind(forFileName: url.lastPathComponent)
    }

    public static func kind(forFileName fileName: String) -> FileKind {
        guard let dotIndex = fileName.lastIndex(of: "."),
              dotIndex < fileName.index(before: fileName.endIndex) else {
            return .other
        }
        let ext = fileName[fileName.index(after: dotIndex)...].lowercased()
        switch ext {
        case "mp4", "mov", "mkv", "avi", "webm", "m4v", "wmv", "flv":
            return .video
        case "mp3", "wav", "m4a", "flac", "aac", "ogg", "aiff":
            return .audio
        case "png", "jpg", "jpeg", "heic", "gif", "svg", "webp", "tiff", "bmp", "raw", "psd":
            return .image
        case "pdf", "docx", "doc", "xlsx", "xls", "pptx", "ppt", "pages", "numbers", "keynote", "txt", "rtf", "md":
            return .document
        case "zip", "tar", "gz", "tgz", "rar", "7z", "dmg", "iso", "pkg":
            return .archive
        case "swift", "js", "ts", "jsx", "tsx", "py", "rs", "go", "json", "yaml", "yml", "xml", "html", "css", "c", "cpp", "h", "sh", "sql":
            return .code
        default:
            return .other
        }
    }

    public var icon: String {
        switch self {
        case .video:
            return "film"
        case .audio:
            return "waveform"
        case .image:
            return "photo"
        case .document:
            return "doc.text"
        case .archive:
            return "doc.zipper"
        case .code:
            return "chevron.left.forwardslash.chevron.right"
        case .other:
            return "doc"
        }
    }
}

public struct CloudItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let path: String
    public var url: URL { URL(fileURLWithPath: path) }
    public let name: String
    public let relativePath: String
    public let parentFolderPath: String
    public let providerId: String
    public let fileSize: Int64
    public var allocatedSize: Int64
    public var isDataless: Bool
    public var isUploaded: Bool
    public var isUploading: Bool
    public var isDownloading: Bool
    public var hasConflicts: Bool
    public var syncStatus: SyncStatus
    public let kind: FileKind
    public let modificationDate: Date?
    public let creationDate: Date?
    public let lastAccessDate: Date?

    /// Fast deterministic UUID generator that avoids kernel CSPRNG overhead when scanning 500k+ files.
    @inline(__always)
    public static func makeFastID(seed: UInt64, index: UInt64) -> UUID {
        var pair = (seed.bigEndian, index.bigEndian)
        return withUnsafeBytes(of: &pair) { rawBuffer in
            rawBuffer.load(as: UUID.self)
        }
    }

    public init(
        id: UUID = UUID(),
        path: String,
        name: String,
        relativePath: String,
        parentFolderPath: String,
        providerId: String,
        fileSize: Int64,
        allocatedSize: Int64,
        isDataless: Bool,
        isUploaded: Bool,
        isUploading: Bool,
        isDownloading: Bool,
        hasConflicts: Bool,
        syncStatus: SyncStatus,
        kind: FileKind,
        modificationDate: Date?,
        creationDate: Date?,
        lastAccessDate: Date?
    ) {
        self.id = id
        self.path = path
        self.name = name
        self.relativePath = relativePath
        self.parentFolderPath = parentFolderPath
        self.providerId = providerId
        self.fileSize = fileSize
        self.allocatedSize = allocatedSize
        self.isDataless = isDataless
        self.isUploaded = isUploaded
        self.isUploading = isUploading
        self.isDownloading = isDownloading
        self.hasConflicts = hasConflicts
        self.syncStatus = syncStatus
        self.kind = kind
        self.modificationDate = modificationDate
        self.creationDate = creationDate
        self.lastAccessDate = lastAccessDate
    }

    public init(
        id: UUID = UUID(),
        url: URL,
        name: String,
        relativePath: String,
        parentFolderPath: String,
        providerId: String,
        fileSize: Int64,
        allocatedSize: Int64,
        isDataless: Bool,
        isUploaded: Bool,
        isUploading: Bool,
        isDownloading: Bool,
        hasConflicts: Bool,
        syncStatus: SyncStatus,
        kind: FileKind,
        modificationDate: Date?,
        creationDate: Date?,
        lastAccessDate: Date?
    ) {
        self.init(
            id: id,
            path: url.path,
            name: name,
            relativePath: relativePath,
            parentFolderPath: parentFolderPath,
            providerId: providerId,
            fileSize: fileSize,
            allocatedSize: allocatedSize,
            isDataless: isDataless,
            isUploaded: isUploaded,
            isUploading: isUploading,
            isDownloading: isDownloading,
            hasConflicts: hasConflicts,
            syncStatus: syncStatus,
            kind: kind,
            modificationDate: modificationDate,
            creationDate: creationDate,
            lastAccessDate: lastAccessDate
        )
    }

    /// True if the item is currently taking space on local disk and is fully synced to the cloud.
    @inline(__always)
    public var isReclaimable: Bool {
        return syncStatus == .downloaded && allocatedSize > 0
    }

    public static func == (lhs: CloudItem, rhs: CloudItem) -> Bool {
        return lhs.id == rhs.id &&
               lhs.allocatedSize == rhs.allocatedSize &&
               lhs.syncStatus == rhs.syncStatus &&
               lhs.isDataless == rhs.isDataless
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(allocatedSize)
        hasher.combine(syncStatus)
    }
}
