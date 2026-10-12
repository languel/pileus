import Foundation
import SwiftUI
import AppKit

public enum AppTab: String, CaseIterable, Identifiable {
    case files = "Files List"
    case folders = "Folder Space Analyzer"

    public var id: String { rawValue }
    public var icon: String {
        switch self {
        case .files: return "list.bullet"
        case .folders: return "folder.badge.gearshape"
        }
    }
}

@MainActor
public final class AppViewModel: ObservableObject {
    @Published public var providers: [CloudProvider] = []
    @Published public var selectedProvider: CloudProvider?

    @Published public var allItems: [CloudItem] = []
    @Published public var folderNodes: [CloudFolderNode] = []

    @Published public var filterOptions = FilterOptions()
    @Published public var sortOption = SortOption(field: .allocatedSize, ascending: false)

    @Published public var isScanning: Bool = false
    @Published public var scanProgressText: String = "Ready"
    @Published public var scannedCount: Int = 0

    @Published public var isEvicting: Bool = false
    @Published public var evictionProgressCurrent: Int = 0
    @Published public var evictionProgressTotal: Int = 0
    @Published public var evictionProgressText: String = ""

    @Published public var selectedItemIds = Set<UUID>()
    @Published public var activeTab: AppTab = .files

    // Confirmation Sheet State
    @Published public var showConfirmationSheet: Bool = false
    @Published public var pendingEvictionItems: [CloudItem] = []
    @Published public var pendingEvictionTitle: String = ""
    @Published public var pendingEvictionDescription: String = ""

    // Report / Feedback
    @Published public var lastReport: EvictionReport?
    @Published public var showReportAlert: Bool = false
    @Published public var errorMessage: String?
    @Published public var showErrorAlert: Bool = false

    private var currentScanTask: Task<Void, Never>?
    private var currentEvictTask: Task<Void, Never>?

    public init() {
        loadProviders()
    }

    public func loadProviders() {
        let detected = ProviderDetector.shared.detectProviders()
        self.providers = detected
        if selectedProvider == nil || !detected.contains(where: { $0.id == selectedProvider?.id }) {
            self.selectedProvider = detected.first
        }
        if let provider = self.selectedProvider {
            startScan(for: provider)
        }
    }

    public func selectProvider(_ provider: CloudProvider) {
        guard provider.id != selectedProvider?.id else { return }
        selectedProvider = provider
        selectedItemIds.removeAll()
        filterOptions.selectedFolderPrefix = nil
        startScan(for: provider)
    }

    public func addCustomFolder(url: URL) {
        let id = "custom-\(UUID().uuidString.prefix(6))"
        let provider = CloudProvider(
            id: id,
            name: url.lastPathComponent,
            type: .custom,
            rootURL: url
        )
        providers.append(provider)
        selectedProvider = provider
        startScan(for: provider)
    }

    public func startScan(for providerOverride: CloudProvider? = nil) {
        let provider = providerOverride ?? selectedProvider
        guard let target = provider else { return }

        currentScanTask?.cancel()
        isScanning = true
        scannedCount = 0
        scanProgressText = "Scanning \(target.name)..."

        currentScanTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                let result = try await CloudScanner.shared.scan(
                    rootURL: target.rootURL,
                    providerId: target.id
                ) { count, path in
                    Task { @MainActor in
                        self.scannedCount = count
                        self.scanProgressText = "Scanned \(count) files: \(path)"
                    }
                }

                if !Task.isCancelled {
                    self.allItems = result.items
                    self.folderNodes = result.folderNodes
                    self.isScanning = false
                    self.scanProgressText = "Scan complete. Found \(result.items.count) files (\(ByteFormatter.string(fromByteCount: result.reclaimableBytes)) reclaimable)."

                    // Update provider cached metrics
                    if let index = self.providers.firstIndex(where: { $0.id == target.id }) {
                        var p = self.providers[index]
                        p.totalCloudBytes = result.totalCloudBytes
                        p.reclaimableBytes = result.reclaimableBytes
                        p.totalFilesCount = result.totalFilesCount
                        p.downloadedFilesCount = result.downloadedCount
                        self.providers[index] = p
                    }
                }
            } catch {
                if !Task.isCancelled {
                    self.isScanning = false
                    self.scanProgressText = "Scan failed: \(error.localizedDescription)"
                }
            }
        }
    }

    public func cancelScan() {
        currentScanTask?.cancel()
        isScanning = false
        scanProgressText = "Scan cancelled."
    }

    // MARK: - Computed Filtered & Sorted Items

    public var filteredAndSortedItems: [CloudItem] {
        let filtered = allItems.filter { filterOptions.matches(item: $0) }
        return filtered.sorted { sortOption.comparator(lhs: $0, rhs: $1) }
    }

    public var totalCloudBytes: Int64 {
        allItems.reduce(0) { $0 + $1.fileSize }
    }

    public var totalReclaimableBytes: Int64 {
        allItems.reduce(0) { $0 + ($1.isReclaimable ? $1.allocatedSize : 0) }
    }

    public var totalDownloadedCount: Int {
        allItems.filter { $0.isReclaimable }.count
    }

    public var reclaimablePercentage: Double {
        guard totalCloudBytes > 0 else { return 0 }
        return (Double(totalReclaimableBytes) / Double(totalCloudBytes)) * 100.0
    }

    // MARK: - Eviction Actions

    public func evictSingle(item: CloudItem) {
        guard item.isReclaimable else {
            errorMessage = "File is not eligible for eviction or is already dateless."
            showErrorAlert = true
            return
        }

        pendingEvictionItems = [item]
        pendingEvictionTitle = "Remove Download: \(item.name)"
        pendingEvictionDescription = "This will make '\(item.name)' cloud-only, freeing \(ByteFormatter.string(fromByteCount: item.allocatedSize)) on your Mac. The file remains safely stored in the cloud and can be reopened anytime."
        showConfirmationSheet = true
    }

    public func promptEvictSelection() {
        let items = allItems.filter { selectedItemIds.contains($0.id) && $0.isReclaimable }
        guard !items.isEmpty else {
            errorMessage = "No reclaimable downloaded files selected."
            showErrorAlert = true
            return
        }

        let totalFreed = items.reduce(0) { $0 + $1.allocatedSize }
        pendingEvictionItems = items
        pendingEvictionTitle = "Remove Downloads (\(items.count) Files)"
        pendingEvictionDescription = "You are about to reclaim \(ByteFormatter.string(fromByteCount: totalFreed)) across \(items.count) selected files. These files will be converted to cloud placeholders and can be re-downloaded at any time."
        showConfirmationSheet = true
    }

    public func promptEvictAllFiltered() {
        let items = filteredAndSortedItems.filter { $0.isReclaimable }
        guard !items.isEmpty else {
            errorMessage = "No downloaded files match current filters."
            showErrorAlert = true
            return
        }

        let totalFreed = items.reduce(0) { $0 + $1.allocatedSize }
        pendingEvictionItems = items
        pendingEvictionTitle = "Remove All Filtered Downloads"
        pendingEvictionDescription = "Reclaim \(ByteFormatter.string(fromByteCount: totalFreed)) across all \(items.count) files matching your active filters. Files remain preserved in the cloud."
        showConfirmationSheet = true
    }

    public func promptEvictFolder(node: CloudFolderNode) {
        let folderPath = node.url.standardizedFileURL.path
        let itemsInFolder = allItems.filter {
            $0.url.standardizedFileURL.path.hasPrefix(folderPath) && $0.isReclaimable
        }

        guard !itemsInFolder.isEmpty else {
            errorMessage = "Folder '\(node.name)' contains no downloaded files to reclaim."
            showErrorAlert = true
            return
        }

        let totalFreed = itemsInFolder.reduce(0) { $0 + $1.allocatedSize }
        pendingEvictionItems = itemsInFolder
        pendingEvictionTitle = "Remove Downloads in '\(node.name)'"
        pendingEvictionDescription = "Recursively evict \(itemsInFolder.count) downloaded files in '\(node.name)' and its subfolders, freeing \(ByteFormatter.string(fromByteCount: totalFreed)) of local disk space."
        showConfirmationSheet = true
    }

    public func executeConfirmedEviction() {
        showConfirmationSheet = false
        let itemsToEvict = pendingEvictionItems
        guard !itemsToEvict.isEmpty else { return }

        isEvicting = true
        evictionProgressCurrent = 0
        evictionProgressTotal = itemsToEvict.count
        evictionProgressText = "Preparing eviction..."

        currentEvictTask = Task { [weak self] in
            guard let self = self else { return }
            let report = await EvictionService.shared.evictBatch(items: itemsToEvict) { cur, total, freed in
                Task { @MainActor in
                    self.evictionProgressCurrent = cur
                    self.evictionProgressTotal = total
                    self.evictionProgressText = "Evicted \(cur) of \(total) files (\(ByteFormatter.string(fromByteCount: freed)) freed)..."
                }
            }

            self.isEvicting = false
            self.lastReport = report
            self.showReportAlert = true

            // Rescan to update ground-truth disk stats
            self.startScan()
        }
    }

    public func downloadItem(item: CloudItem) {
        do {
            try EvictionService.shared.download(item: item)
            scanProgressText = "Requested download for \(item.name)..."
        } catch {
            errorMessage = "Failed to download: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    public func revealInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
