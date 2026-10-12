import Foundation

public enum ProviderType: String, CaseIterable, Sendable, Codable {
    case iCloud = "iCloud Drive"
    case googleDrive = "Google Drive"
    case oneDrive = "OneDrive"
    case dropbox = "Dropbox"
    case custom = "Custom Folder"

    public var systemIcon: String {
        switch self {
        case .iCloud:
            return "icloud.fill"
        case .googleDrive:
            return "externaldrive.badge.icloud"
        case .oneDrive:
            return "cloud.fill"
        case .dropbox:
            return "shippingbox.fill"
        case .custom:
            return "folder.badge.gearshape"
        }
    }
}

public struct CloudProvider: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let type: ProviderType
    public let rootURL: URL
    public var accountEmail: String?
    public var totalCloudBytes: Int64 = 0
    public var reclaimableBytes: Int64 = 0
    public var totalFilesCount: Int = 0
    public var downloadedFilesCount: Int = 0

    public init(
        id: String,
        name: String,
        type: ProviderType,
        rootURL: URL,
        accountEmail: String? = nil,
        totalCloudBytes: Int64 = 0,
        reclaimableBytes: Int64 = 0,
        totalFilesCount: Int = 0,
        downloadedFilesCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.rootURL = rootURL
        self.accountEmail = accountEmail
        self.totalCloudBytes = totalCloudBytes
        self.reclaimableBytes = reclaimableBytes
        self.totalFilesCount = totalFilesCount
        self.downloadedFilesCount = downloadedFilesCount
    }
}
