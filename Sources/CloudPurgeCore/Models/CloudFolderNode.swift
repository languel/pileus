import Foundation

public struct CloudFolderNode: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public var url: URL { URL(fileURLWithPath: path) }
    public let name: String
    public let relativePath: String
    public let providerId: String
    public var totalCloudBytes: Int64
    public var reclaimableBytes: Int64
    public var totalFilesCount: Int
    public var downloadedFilesCount: Int
    public var children: [CloudFolderNode]

    public init(
        path: String,
        name: String,
        relativePath: String,
        providerId: String,
        totalCloudBytes: Int64 = 0,
        reclaimableBytes: Int64 = 0,
        totalFilesCount: Int = 0,
        downloadedFilesCount: Int = 0,
        children: [CloudFolderNode] = []
    ) {
        self.path = path
        self.name = name
        self.relativePath = relativePath
        self.providerId = providerId
        self.totalCloudBytes = totalCloudBytes
        self.reclaimableBytes = reclaimableBytes
        self.totalFilesCount = totalFilesCount
        self.downloadedFilesCount = downloadedFilesCount
        self.children = children
    }

    public init(
        url: URL,
        name: String,
        relativePath: String,
        providerId: String,
        totalCloudBytes: Int64 = 0,
        reclaimableBytes: Int64 = 0,
        totalFilesCount: Int = 0,
        downloadedFilesCount: Int = 0,
        children: [CloudFolderNode] = []
    ) {
        self.init(
            path: url.path,
            name: name,
            relativePath: relativePath,
            providerId: providerId,
            totalCloudBytes: totalCloudBytes,
            reclaimableBytes: reclaimableBytes,
            totalFilesCount: totalFilesCount,
            downloadedFilesCount: downloadedFilesCount,
            children: children
        )
    }

    /// Percentage of the folder's cloud content that is currently materialized locally and can be reclaimed
    public var percentageReclaimable: Double {
        guard totalCloudBytes > 0 else { return 0 }
        return min(100.0, max(0.0, (Double(reclaimableBytes) / Double(totalCloudBytes)) * 100.0))
    }

    public var percentageString: String {
        guard totalCloudBytes > 0 else { return "0%" }
        return String(format: "%.1f%%", percentageReclaimable)
    }

    public static func == (lhs: CloudFolderNode, rhs: CloudFolderNode) -> Bool {
        return lhs.path == rhs.path &&
               lhs.reclaimableBytes == rhs.reclaimableBytes &&
               lhs.totalCloudBytes == rhs.totalCloudBytes &&
               lhs.downloadedFilesCount == rhs.downloadedFilesCount &&
               lhs.totalFilesCount == rhs.totalFilesCount
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(path)
        hasher.combine(reclaimableBytes)
        hasher.combine(downloadedFilesCount)
    }
}
