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

public struct ProviderScanState: Sendable {
    public var isScanning: Bool = false
    public var isPaused: Bool = false
    public var hasCompletedScan: Bool = false
    public var scannedCount: Int = 0
    public var scanProgressText: String = "Ready to scan"
    public var items: [CloudItem] = []
    public var folderNodes: [CloudFolderNode] = []
    public var allFolders: [CloudFolderNode] = []
    public var totalCloudBytes: Int64 = 0
    public var reclaimableBytes: Int64 = 0
    public var downloadedCount: Int = 0
    public var lastScannedDate: Date? = nil

    public init() {}
}

@MainActor
public final class AppViewModel: ObservableObject {
    public static let defaultDisplayLimit = 500
    private static let customFoldersDefaultsKey = "CloudPurge.CustomFolderPaths"

    @Published public var providers: [CloudProvider] = []
    @Published public var selectedProvider: CloudProvider?

    /// Per-provider scan states so switching sources never loses progress or restarts scans.
    @Published public private(set) var providerStates: [String: ProviderScanState] = [:]

    /// Currently filtered & sorted items (computed in background) and the paginated slice for Table rendering.
    @Published public private(set) var filteredAndSortedItems: [CloudItem] = []
    @Published public private(set) var displayedItems: [CloudItem] = []
    @Published public private(set) var totalMatchingCount: Int = 0
    @Published public private(set) var matchingReclaimableCount: Int = 0
    @Published public private(set) var matchingReclaimableBytes: Int64 = 0
    @Published public private(set) var isFiltering: Bool = false
    @Published public var displayLimit: Int = AppViewModel.defaultDisplayLimit

    @Published public var filterOptions = FilterOptions() {
        didSet {
            if oldValue != filterOptions {
                displayLimit = Self.defaultDisplayLimit
                scheduleFilterAndSort(debounceSearch: oldValue.searchText != filterOptions.searchText)
            }
        }
    }

    @Published public var sortOption = SortOption(field: .allocatedSize, ascending: false) {
        didSet {
            if oldValue != sortOption {
                scheduleFilterAndSort(debounceSearch: false)
            }
        }
    }

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

    private var scanTasks: [String: Task<Void, Never>] = [:]
    private var scanControls: [String: ScanSessionControl] = [:]
    private var lastLiveRefreshTime: [String: CFAbsoluteTime] = [:]
    private var filterSortTask: Task<Void, Never>?
    private var currentEvictTask: Task<Void, Never>?

    public init() {
        loadProviders()
    }

    // MARK: - Active Provider Convenience Accessors (O(1))

    private var activeState: ProviderScanState {
        guard let id = selectedProvider?.id else { return ProviderScanState() }
        return providerStates[id] ?? ProviderScanState()
    }

    public var allItems: [CloudItem] {
        activeState.items
    }

    public var folderNodes: [CloudFolderNode] {
        activeState.folderNodes
    }

    public var allFolders: [CloudFolderNode] {
        activeState.allFolders
    }

    public var isScanning: Bool {
        activeState.isScanning
    }

    public var isPaused: Bool {
        activeState.isPaused
    }

    public var scanProgressText: String {
        activeState.scanProgressText
    }

    public var scannedCount: Int {
        activeState.scannedCount
    }

    public var totalCloudBytes: Int64 {
        activeState.totalCloudBytes
    }

    public var totalReclaimableBytes: Int64 {
        activeState.reclaimableBytes
    }

    public var totalDownloadedCount: Int {
        activeState.downloadedCount
    }

    public var reclaimablePercentage: Double {
        let total = totalCloudBytes
        guard total > 0 else { return 0 }
        return min(100.0, max(0.0, (Double(totalReclaimableBytes) / Double(total)) * 100.0))
    }

    public func state(for providerId: String) -> ProviderScanState {
        return providerStates[providerId] ?? ProviderScanState()
    }

    // MARK: - Provider Selection, Custom Folders & Multi-Source Scanning

    public func loadProviders() {
        let detected = ProviderDetector.shared.detectProviders()
        let currentCustomProviders = providers.filter { $0.type == .custom }
        var merged: [CloudProvider] = []

        for var d in detected {
            if let existingState = providerStates[d.id],
               existingState.hasCompletedScan || existingState.isScanning || !existingState.items.isEmpty {
                d.totalCloudBytes = existingState.totalCloudBytes
                d.reclaimableBytes = existingState.reclaimableBytes
                d.totalFilesCount = existingState.items.count
                d.downloadedFilesCount = existingState.downloadedCount
            }
            merged.append(d)
        }

        // Restore persisted custom folders from UserDefaults and currently loaded custom folders
        let savedCustomPaths = UserDefaults.standard.stringArray(forKey: Self.customFoldersDefaultsKey) ?? []
        for path in savedCustomPaths {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let id = Self.customProviderId(for: url)
            if !merged.contains(where: { $0.id == id || $0.rootURL.standardizedFileURL.path == url.standardizedFileURL.path }) {
                var custom = CloudProvider(
                    id: id,
                    name: url.lastPathComponent,
                    type: .custom,
                    rootURL: url
                )
                if let existingState = providerStates[id] {
                    custom.totalCloudBytes = existingState.totalCloudBytes
                    custom.reclaimableBytes = existingState.reclaimableBytes
                    custom.totalFilesCount = existingState.items.count
                    custom.downloadedFilesCount = existingState.downloadedCount
                }
                merged.append(custom)
            }
        }

        for c in currentCustomProviders where !merged.contains(where: { $0.id == c.id }) {
            merged.append(c)
        }

        self.providers = merged

        if selectedProvider == nil || !merged.contains(where: { $0.id == selectedProvider?.id }) {
            self.selectedProvider = merged.first
        }

        if let provider = self.selectedProvider {
            let st = state(for: provider.id)
            if !st.hasCompletedScan && !st.isScanning && st.items.isEmpty {
                startScan(for: provider, forceRestart: false)
            } else {
                scheduleFilterAndSort(debounceSearch: false)
            }
        }
    }

    public func selectProvider(_ provider: CloudProvider) {
        guard provider.id != selectedProvider?.id else { return }
        filterSortTask?.cancel()
        selectedProvider = provider
        selectedItemIds.removeAll()
        displayLimit = Self.defaultDisplayLimit

        // Immediately clear displayed items and metrics so the previous source's analysis is never shown
        filteredAndSortedItems = []
        displayedItems = []
        totalMatchingCount = 0
        matchingReclaimableCount = 0
        matchingReclaimableBytes = 0

        if filterOptions.selectedFolderPrefix != nil {
            filterOptions.selectedFolderPrefix = nil
        }

        let st = state(for: provider.id)
        if !st.hasCompletedScan && !st.isScanning && st.items.isEmpty {
            // Start scanning this provider if never scanned yet; other providers keep scanning in background!
            startScan(for: provider, forceRestart: false)
        } else {
            // Immediately display cached, paused, or currently-scanning state for this provider
            scheduleFilterAndSort(debounceSearch: false)
        }
    }

    private static func customProviderId(for url: URL) -> String {
        let normalized = url.standardizedFileURL.path
        var hash: UInt64 = 14695981039346656037
        for byte in normalized.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1099511628211
        }
        return String(format: "custom-%016llx", hash)
    }

    private func saveCustomFoldersToDefaults() {
        let customPaths = providers
            .filter { $0.type == .custom }
            .map { $0.rootURL.standardizedFileURL.path }
        UserDefaults.standard.set(customPaths, forKey: Self.customFoldersDefaultsKey)
    }

    public func addCustomFolder(url: URL) {
        let standardizedPath = url.standardizedFileURL.path
        if let existing = providers.first(where: { $0.rootURL.standardizedFileURL.path == standardizedPath }) {
            selectProvider(existing)
            return
        }

        let id = Self.customProviderId(for: url)
        let provider = CloudProvider(
            id: id,
            name: url.lastPathComponent,
            type: .custom,
            rootURL: url
        )
        providers.append(provider)
        saveCustomFoldersToDefaults()
        selectProvider(provider)
    }

    /// Removes a custom folder from the sidebar list and cleans up its scan task & state.
    public func removeCustomProvider(_ provider: CloudProvider) {
        guard provider.type == .custom else { return }
        let id = provider.id

        // Stop any running scan for this custom folder
        scanControls[id]?.stop()
        scanControls[id] = nil
        scanTasks[id]?.cancel()
        scanTasks[id] = nil
        providerStates[id] = nil
        lastLiveRefreshTime[id] = nil

        providers.removeAll { $0.id == id }
        saveCustomFoldersToDefaults()

        if selectedProvider?.id == id {
            if let next = providers.first {
                selectProvider(next)
            } else {
                selectedProvider = nil
                scheduleFilterAndSort(debounceSearch: false)
            }
        }
    }

    /// Starts or restarts a scan for a specific provider without cancelling scans of other providers.
    public func startScan(for providerOverride: CloudProvider? = nil, forceRestart: Bool = true) {
        guard let target = providerOverride ?? selectedProvider else { return }
        let providerId = target.id

        if !forceRestart {
            if let existing = providerStates[providerId], existing.isScanning || existing.hasCompletedScan || !existing.items.isEmpty {
                return
            }
        }

        // Stop only this provider's previous task if restarting
        scanControls[providerId]?.stop()
        scanTasks[providerId]?.cancel()

        let control = ScanSessionControl()
        scanControls[providerId] = control
        lastLiveRefreshTime[providerId] = 0

        var initial = ProviderScanState()
        initial.isScanning = true
        initial.isPaused = false
        initial.scannedCount = 0
        initial.scanProgressText = "Scanning \(target.name)..."
        providerStates[providerId] = initial

        if selectedProvider?.id == providerId {
            scheduleFilterAndSort(debounceSearch: false)
        }

        scanTasks[providerId] = Task { [weak self] in
            guard let self = self else { return }
            do {
                let result = try await CloudScanner.shared.scanWithProgress(
                    rootURL: target.rootURL,
                    providerId: providerId,
                    control: control
                ) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        guard var st = self.providerStates[providerId] else { return }

                        st.scannedCount = progress.scannedFiles
                        st.totalCloudBytes = progress.totalCloudBytes
                        st.reclaimableBytes = progress.reclaimableBytes
                        st.downloadedCount = progress.downloadedCount

                        if !progress.newItemsBatch.isEmpty {
                            st.items.append(contentsOf: progress.newItemsBatch)
                        }
                        if let folderSnap = progress.snapshotFolderNodes {
                            st.folderNodes = folderSnap
                        }
                        if let allFolderSnap = progress.snapshotAllFolders {
                            st.allFolders = allFolderSnap
                        }

                        if st.isPaused {
                            st.scanProgressText = "Scan paused • \(progress.scannedFiles.formatted()) files (\(ByteFormatter.string(fromByteCount: progress.reclaimableBytes)) reclaimable)"
                        } else if st.isScanning {
                            st.scanProgressText = "Scanning \(target.name): \(progress.scannedFiles.formatted()) files (\(ByteFormatter.string(fromByteCount: progress.reclaimableBytes)) reclaimable) — \(progress.currentPath)"
                        }

                        self.providerStates[providerId] = st
                        self.updateProviderSummary(
                            providerId: providerId,
                            totalCloudBytes: progress.totalCloudBytes,
                            reclaimableBytes: progress.reclaimableBytes,
                            totalFilesCount: progress.scannedFiles,
                            downloadedCount: progress.downloadedCount
                        )

                        // Periodically refresh the visible table while scanning or immediately when paused
                        if self.selectedProvider?.id == providerId {
                            let now = CFAbsoluteTimeGetCurrent()
                            let lastRefresh = self.lastLiveRefreshTime[providerId] ?? 0
                            if st.isPaused || (now - lastRefresh >= 1.0) {
                                self.lastLiveRefreshTime[providerId] = now
                                self.scheduleFilterAndSort(debounceSearch: false)
                            }
                        }
                    }
                }

                let wasStopped = control.isStopped || Task.isCancelled
                var completedState = self.providerStates[providerId] ?? ProviderScanState()
                completedState.isScanning = false
                completedState.isPaused = false
                completedState.hasCompletedScan = !wasStopped
                completedState.scannedCount = result.totalFilesCount
                completedState.items = result.items
                completedState.folderNodes = result.folderNodes
                completedState.allFolders = result.allFolders
                completedState.totalCloudBytes = result.totalCloudBytes
                completedState.reclaimableBytes = result.reclaimableBytes
                completedState.downloadedCount = result.downloadedCount
                completedState.lastScannedDate = Date()

                if wasStopped {
                    completedState.scanProgressText = "Scan stopped • \(result.totalFilesCount.formatted()) files kept (\(ByteFormatter.string(fromByteCount: result.reclaimableBytes)) reclaimable)"
                } else {
                    completedState.scanProgressText = "Scan complete • \(result.totalFilesCount.formatted()) files (\(ByteFormatter.string(fromByteCount: result.reclaimableBytes)) reclaimable)"
                }

                self.providerStates[providerId] = completedState
                self.scanTasks[providerId] = nil
                self.scanControls[providerId] = nil

                self.updateProviderSummary(
                    providerId: providerId,
                    totalCloudBytes: result.totalCloudBytes,
                    reclaimableBytes: result.reclaimableBytes,
                    totalFilesCount: result.totalFilesCount,
                    downloadedCount: result.downloadedCount
                )

                if self.selectedProvider?.id == providerId {
                    self.scheduleFilterAndSort(debounceSearch: false)
                }
            } catch {
                if !Task.isCancelled {
                    var failedState = self.providerStates[providerId] ?? ProviderScanState()
                    failedState.isScanning = false
                    failedState.isPaused = false
                    failedState.scanProgressText = "Scan failed: \(error.localizedDescription)"
                    self.providerStates[providerId] = failedState
                    self.scanTasks[providerId] = nil
                    self.scanControls[providerId] = nil
                }
            }
        }
    }

    /// Pauses an active scan in-place without losing any discovered files or directory progress.
    public func pauseScan(for providerId: String? = nil) {
        guard let targetId = providerId ?? selectedProvider?.id else { return }
        guard var st = providerStates[targetId], st.isScanning, !st.isPaused else { return }
        scanControls[targetId]?.pause()
        st.isPaused = true
        st.scanProgressText = "Scan paused • \(st.scannedCount.formatted()) files (\(ByteFormatter.string(fromByteCount: st.reclaimableBytes)) reclaimable)"
        providerStates[targetId] = st

        if selectedProvider?.id == targetId {
            scheduleFilterAndSort(debounceSearch: false)
        }
    }

    /// Resumes a paused scan from the exact file where it left off.
    public func resumeScan(for providerId: String? = nil) {
        guard let targetId = providerId ?? selectedProvider?.id else { return }
        guard var st = providerStates[targetId], st.isScanning, st.isPaused else { return }
        st.isPaused = false
        st.scanProgressText = "Resuming scan (\(st.scannedCount.formatted()) files)..."
        providerStates[targetId] = st
        scanControls[targetId]?.resume()
    }

    /// Toggles pause/resume for a provider's active scan.
    public func togglePauseScan(for providerId: String? = nil) {
        guard let targetId = providerId ?? selectedProvider?.id else { return }
        guard let st = providerStates[targetId], st.isScanning else { return }
        if st.isPaused {
            resumeScan(for: targetId)
        } else {
            pauseScan(for: targetId)
        }
    }

    /// Stops the scan while preserving all files and folder metrics discovered so far.
    public func cancelScan(for providerId: String? = nil) {
        guard let targetId = providerId ?? selectedProvider?.id else { return }
        scanControls[targetId]?.stop()
        if var st = providerStates[targetId] {
            st.isScanning = false
            st.isPaused = false
            st.scanProgressText = "Scan stopped • \(st.scannedCount.formatted()) files kept (\(ByteFormatter.string(fromByteCount: st.reclaimableBytes)) reclaimable)"
            providerStates[targetId] = st
        }
        if selectedProvider?.id == targetId {
            scheduleFilterAndSort(debounceSearch: false)
        }
    }

    private func updateProviderSummary(
        providerId: String,
        totalCloudBytes: Int64,
        reclaimableBytes: Int64,
        totalFilesCount: Int,
        downloadedCount: Int
    ) {
        if let index = providers.firstIndex(where: { $0.id == providerId }) {
            var p = providers[index]
            p.totalCloudBytes = totalCloudBytes
            p.reclaimableBytes = reclaimableBytes
            p.totalFilesCount = totalFilesCount
            p.downloadedFilesCount = downloadedCount
            providers[index] = p
        }
    }

    // MARK: - Background Filtering, Sorting & Pagination

    public func loadMoreItems() {
        displayLimit += 1000
        displayedItems = Array(filteredAndSortedItems.prefix(displayLimit))
    }

    public func showAllItems() {
        displayLimit = max(filteredAndSortedItems.count, Self.defaultDisplayLimit)
        displayedItems = filteredAndSortedItems
    }

    private func scheduleFilterAndSort(debounceSearch: Bool) {
        filterSortTask?.cancel()
        let targetProviderId = selectedProvider?.id
        let itemsSnapshot = activeState.items
        let filtersSnapshot = filterOptions
        let sortSnapshot = sortOption
        let limitSnapshot = displayLimit

        if itemsSnapshot.isEmpty {
            filteredAndSortedItems = []
            displayedItems = []
            totalMatchingCount = 0
            matchingReclaimableCount = 0
            matchingReclaimableBytes = 0
            isFiltering = false
            return
        }

        isFiltering = true

        filterSortTask = Task { [weak self] in
            if debounceSearch {
                try? await Task.sleep(nanoseconds: 120_000_000) // 120ms debounce while typing
                if Task.isCancelled { return }
            }

            let computed = await Task.detached(priority: .userInitiated) { () -> (sorted: [CloudItem], reclaimableCount: Int, reclaimableBytes: Int64)? in
                if Task.isCancelled { return nil }
                var filtered = filtersSnapshot.filter(items: itemsSnapshot)
                if Task.isCancelled { return nil }

                var reclaimCount = 0
                var reclaimBytes: Int64 = 0
                for item in filtered where item.isReclaimable {
                    reclaimCount &+= 1
                    reclaimBytes += item.allocatedSize
                }

                filtered.sort { sortSnapshot.comparator(lhs: $0, rhs: $1) }
                if Task.isCancelled { return nil }
                return (filtered, reclaimCount, reclaimBytes)
            }.value

            guard let self = self,
                  !Task.isCancelled,
                  self.selectedProvider?.id == targetProviderId,
                  let computed = computed else { return }
            self.filteredAndSortedItems = computed.sorted
            self.totalMatchingCount = computed.sorted.count
            self.matchingReclaimableCount = computed.reclaimableCount
            self.matchingReclaimableBytes = computed.reclaimableBytes
            self.displayedItems = Array(computed.sorted.prefix(limitSnapshot))
            self.isFiltering = false
        }
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
        let folderPath = node.path
        let folderPrefix = folderPath.hasSuffix("/") ? folderPath : (folderPath + "/")
        let itemsInFolder = allItems.filter {
            $0.isReclaimable && ($0.parentFolderPath == folderPath || $0.path.hasPrefix(folderPrefix))
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

    /// Recursively evicts all downloaded files across a list of folders (e.g., all matching `node_modules` folders).
    public func promptEvictMultipleFolders(nodes: [CloudFolderNode], label: String) {
        let reclaimableFolders = nodes.filter { $0.reclaimableBytes > 0 }
        guard !reclaimableFolders.isEmpty else {
            errorMessage = "No downloaded files to reclaim in the matching folders."
            showErrorAlert = true
            return
        }

        let exactPaths = Set(reclaimableFolders.map { $0.path })
        let prefixes = reclaimableFolders.map { $0.path.hasSuffix("/") ? $0.path : ($0.path + "/") }

        var matchedItems: [CloudItem] = []
        var seenIds = Set<UUID>()

        for item in allItems where item.isReclaimable {
            if exactPaths.contains(item.parentFolderPath) || prefixes.contains(where: { item.path.hasPrefix($0) }) {
                if seenIds.insert(item.id).inserted {
                    matchedItems.append(item)
                }
            }
        }

        guard !matchedItems.isEmpty else {
            errorMessage = "No downloaded files to reclaim in the matching folders."
            showErrorAlert = true
            return
        }

        let totalFreed = matchedItems.reduce(0) { $0 + $1.allocatedSize }
        pendingEvictionItems = matchedItems
        pendingEvictionTitle = "Remove Downloads in \(reclaimableFolders.count) Folders (\(label))"
        pendingEvictionDescription = "Recursively evict \(matchedItems.count.formatted()) downloaded files across \(reclaimableFolders.count) matching folders, freeing \(ByteFormatter.string(fromByteCount: totalFreed)) of local disk space."
        showConfirmationSheet = true
    }

    public func executeConfirmedEviction() {
        showConfirmationSheet = false
        let itemsToEvict = pendingEvictionItems
        guard !itemsToEvict.isEmpty else { return }
        let targetProviderId = itemsToEvict.first?.providerId ?? selectedProvider?.id

        isEvicting = true
        evictionProgressCurrent = 0
        evictionProgressTotal = itemsToEvict.count
        evictionProgressText = "Preparing eviction..."

        currentEvictTask = Task { [weak self] in
            guard let self = self else { return }
            let report = await EvictionService.shared.evictBatch(items: itemsToEvict) { [weak self] cur, total, freed in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.evictionProgressCurrent = cur
                    self.evictionProgressTotal = total
                    self.evictionProgressText = "Evicted \(cur.formatted()) of \(total.formatted()) files (\(ByteFormatter.string(fromByteCount: freed)) freed)..."
                }
            }

            self.isEvicting = false
            self.lastReport = report
            self.showReportAlert = true
            self.selectedItemIds.subtract(report.evictedItemIds)

            // Update state in memory immediately without restarting a slow full scan!
            if let pid = targetProviderId, !report.evictedItemIds.isEmpty {
                self.applyEvictionInMemory(providerId: pid, evictedIds: report.evictedItemIds)
            }
        }
    }

    /// Updates cached items and folder tree metrics in-memory in milliseconds after eviction.
    private func applyEvictionInMemory(providerId: String, evictedIds: Set<UUID>) {
        guard var st = providerStates[providerId] else { return }

        var freedByFolder: [String: (bytes: Int64, count: Int)] = [:]
        var totalFreedBytes: Int64 = 0
        var totalFreedCount = 0

        for i in 0..<st.items.count {
            if evictedIds.contains(st.items[i].id) {
                let freed = st.items[i].allocatedSize
                totalFreedBytes += freed
                totalFreedCount += 1

                let parentPath = st.items[i].parentFolderPath
                var entry = freedByFolder[parentPath] ?? (0, 0)
                entry.bytes += freed
                entry.count += 1
                freedByFolder[parentPath] = entry

                st.items[i].allocatedSize = 0
                st.items[i].isDataless = true
                st.items[i].syncStatus = .cloudOnly
            }
        }

        st.reclaimableBytes = max(0, st.reclaimableBytes - totalFreedBytes)
        st.downloadedCount = max(0, st.downloadedCount - totalFreedCount)
        if st.isPaused {
            st.scanProgressText = "Scan paused • \(st.items.count.formatted()) files (\(ByteFormatter.string(fromByteCount: st.reclaimableBytes)) reclaimable)"
        } else if !st.isScanning {
            st.scanProgressText = "Scan complete • \(st.items.count.formatted()) files (\(ByteFormatter.string(fromByteCount: st.reclaimableBytes)) reclaimable)"
        }

        // Recursively update folderNodes and flat allFolders
        func updateNode(_ node: inout CloudFolderNode) {
            let folderPath = node.path
            let folderPrefix = folderPath.hasSuffix("/") ? folderPath : (folderPath + "/")
            var bytesDelta: Int64 = 0
            var countDelta = 0
            for (dirPath, delta) in freedByFolder {
                if dirPath == folderPath || dirPath.hasPrefix(folderPrefix) {
                    bytesDelta += delta.bytes
                    countDelta += delta.count
                }
            }
            if bytesDelta > 0 || countDelta > 0 {
                node.reclaimableBytes = max(0, node.reclaimableBytes - bytesDelta)
                node.downloadedFilesCount = max(0, node.downloadedFilesCount - countDelta)
            }
            for idx in 0..<node.children.count {
                updateNode(&node.children[idx])
            }
            if node.children.count > 1 {
                node.children.sort { $0.reclaimableBytes > $1.reclaimableBytes }
            }
        }

        for idx in 0..<st.folderNodes.count {
            updateNode(&st.folderNodes[idx])
        }
        st.folderNodes.sort { $0.reclaimableBytes > $1.reclaimableBytes }

        for idx in 0..<st.allFolders.count {
            updateNode(&st.allFolders[idx])
        }

        providerStates[providerId] = st
        updateProviderSummary(
            providerId: providerId,
            totalCloudBytes: st.totalCloudBytes,
            reclaimableBytes: st.reclaimableBytes,
            totalFilesCount: st.items.count,
            downloadedCount: st.downloadedCount
        )

        if selectedProvider?.id == providerId {
            scheduleFilterAndSort(debounceSearch: false)
        }
    }

    public func downloadItem(item: CloudItem) {
        do {
            try EvictionService.shared.download(item: item)
            if let pid = selectedProvider?.id, var st = providerStates[pid] {
                st.scanProgressText = "Requested download for \(item.name)..."
                providerStates[pid] = st
            }
        } catch {
            errorMessage = "Failed to download: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    public func revealInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
