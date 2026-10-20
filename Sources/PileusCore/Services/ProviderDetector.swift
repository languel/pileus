import Foundation

public final class ProviderDetector: Sendable {
    public static let shared = ProviderDetector()

    private var fileManager: FileManager {
        FileManager.default
    }

    public func detectProviders() -> [CloudProvider] {
        var providers: [CloudProvider] = []

        // 1. Detect iCloud Drive
        let home = fileManager.homeDirectoryForCurrentUser
        let icloudURL = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if fileManager.fileExists(atPath: icloudURL.path) {
            providers.append(
                CloudProvider(
                    id: "icloud-drive",
                    name: "iCloud Drive",
                    type: .iCloud,
                    rootURL: icloudURL
                )
            )
        }

        // 2. Detect CloudStorage providers (Google Drive, OneDrive, Dropbox, Box)
        let cloudStorageURL = home.appendingPathComponent("Library/CloudStorage")
        if let contents = try? fileManager.contentsOfDirectory(at: cloudStorageURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for driveURL in contents {
                let name = driveURL.lastPathComponent
                var type: ProviderType = .custom
                var displayName = name
                var email: String? = nil

                if name.lowercased().hasPrefix("googledrive") {
                    type = .googleDrive
                    if let dashIndex = name.firstIndex(of: "-") {
                        let potentialEmail = String(name[name.index(after: dashIndex)...])
                        if potentialEmail.contains("@") {
                            email = potentialEmail
                            displayName = "Google Drive (\(potentialEmail))"
                        } else {
                            displayName = "Google Drive"
                        }
                    } else {
                        displayName = "Google Drive"
                    }
                } else if name.lowercased().hasPrefix("onedrive") {
                    type = .oneDrive
                    displayName = "OneDrive"
                } else if name.lowercased().hasPrefix("dropbox") {
                    type = .dropbox
                    displayName = "Dropbox"
                }

                providers.append(
                    CloudProvider(
                        id: "cs-\(name)",
                        name: displayName,
                        type: type,
                        rootURL: driveURL,
                        accountEmail: email
                    )
                )
            }
        }

        return providers
    }
}
