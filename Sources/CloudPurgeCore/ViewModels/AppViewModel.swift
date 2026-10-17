import Foundation
import SwiftUI
import AppKit

public enum AppTab: String, CaseIterable, Identifiable {
    case files = "Files List"
    case folders = "Folder Space Analyzer"
    case duplicates = "Duplicate Finder"

    public var id: String { rawValue }
    public var icon: String {
        switch self {
        case .files: return "list.bullet"
        case .folders: return "folder.badge.gearshape"
        case .duplicates: return "doc.on.doc.fill"
        }
    }
}

public enum DuplicateScanScope: String, CaseIterable, Identifiable, Sendable {
    case currentSource = "Current Source Only"
    case allScannedSources = "All Scanned Sources (Cross-Drive)"

    public var id: String { rawValue }
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
    @Published public var isEvictionPaused: Bool = false
    @Published public var evictionProgressCurrent: Int = 0
    @Published public var evictionProgressTotal: Int = 0
    @Published public var evictionProgressText: String = ""

    @Published public var selectedItemIds = Set<UUID>()
    @Published public var activeTab: AppTab = .files

    // Duplicate Finder State
    @Published public var duplicateGroups: [DuplicateGroup] = []
    @Published public var isScanningDuplicates: Bool = false
    @Published public var duplicateScanProgressText: String = "Ready to scan for exact duplicate files"
    @Published public var duplicateScanProcessed: Int = 0
    @Published public var duplicateScanTotal: Int = 0
    @Published public var duplicateScanScope: DuplicateScanScope = .currentSource
    @Published public var duplicateMinSizeBytes: Int64 = 10 * 1024 // Default >= 10 KB
    @Published public var duplicateIncludeCloudOnly: Bool = true
    @Published public var selectedDuplicateGroupIds = Set<String>()
    @Published public var excludeCloudFilesInLocalScans: Bool = true {
        didSet {
            if oldValue != excludeCloudFilesInLocalScans,
               let selected = selectedProvider,
               selected.isLocalOnly {
                startScan(for: selected, forceRestart: true)
            }
        }
    }

    // Duplicate Resolution Sheet State
    @Published public var showDuplicateResolveSheet: Bool = false
    @Published public var pendingDuplicateGroups: [DuplicateGroup] = []
    @Published public var selectedResolutionStrategy: DuplicateResolutionStrategy = .symlink
    @Published public var useRelativeSymlinks: Bool = true
    @Published public var relocatePrimaryToCustomFolder: Bool = false
    @Published public var relocatedPrimaryDirectoryURL: URL? = nil
    @Published public var lastDuplicateReport: DuplicateResolutionReport?
    @Published public var showDuplicateReportAlert: Bool = false

    // Confirmation Sheet State
    @Published public var showConfirmationSheet: Bool = false
    @Published public var pendingActionMode: PurgeActionMode = .evictLocalOnly
    @Published public var pendingEvictionItems: [CloudItem] = []
    @Published public var pendingEvictionFolderURLs: [URL] = []
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
    private var currentEvictControl: ScanSessionControl?
    private var duplicateScanTask: Task<Void, Never>?
    private var duplicateScanControl: ScanSessionControl?

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

    public var isActiveProviderLocalOnly: Bool {
        selectedProvider?.isLocalOnly ?? false
    }

    public func isProviderLocalOnly(_ providerId: String) -> Bool {
        providers.first(where: { $0.id == providerId })?.isLocalOnly ?? false
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

    private func formatScanMetrics(files: Int, bytes: Int64, isLocalOnly: Bool) -> String {
        let sizeStr = ByteFormatter.string(fromByteCount: bytes)
        return isLocalOnly
            ? "\(files.formatted()) files (\(sizeStr) on disk)"
            : "\(files.formatted()) files (\(sizeStr) reclaimable)"
    }

    /// Starts or restarts a scan for a specific provider without cancelling scans of other providers.
    public func startScan(for providerOverride: CloudProvider? = nil, forceRestart: Bool = true) {
        guard let target = providerOverride ?? selectedProvider else { return }
        let providerId = target.id
        let isLocalOnly = target.isLocalOnly

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

        let shouldExcludeCloud = isLocalOnly && excludeCloudFilesInLocalScans

        scanTasks[providerId] = Task { [weak self] in
            guard let self = self else { return }
            do {
                let result = try await CloudScanner.shared.scanWithProgress(
                    rootURL: target.rootURL,
                    providerId: providerId,
                    excludeCloudStoragePaths: shouldExcludeCloud,
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

                        let summaryStr = self.formatScanMetrics(files: progress.scannedFiles, bytes: progress.reclaimableBytes, isLocalOnly: isLocalOnly)
                        if st.isPaused {
                            st.scanProgressText = "Scan paused • \(summaryStr)"
                        } else if st.isScanning {
                            st.scanProgressText = "Scanning \(target.name): \(summaryStr) — \(progress.currentPath)"
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

                let finalSummaryStr = self.formatScanMetrics(files: result.totalFilesCount, bytes: result.reclaimableBytes, isLocalOnly: isLocalOnly)
                if wasStopped {
                    completedState.scanProgressText = "Scan stopped • \(finalSummaryStr)"
                } else {
                    completedState.scanProgressText = "Scan complete • \(finalSummaryStr)"
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
        st.scanProgressText = "Scan paused • \(formatScanMetrics(files: st.scannedCount, bytes: st.reclaimableBytes, isLocalOnly: isProviderLocalOnly(targetId)))"
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
            st.scanProgressText = "Scan stopped • \(formatScanMetrics(files: st.scannedCount, bytes: st.reclaimableBytes, isLocalOnly: isProviderLocalOnly(targetId)))"
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

    // MARK: - Eviction & Permanent Cloud Deletion Actions

    public func evictSingle(item: CloudItem) {
        guard !isProviderLocalOnly(item.providerId) else {
            deleteSingle(item: item)
            return
        }
        guard item.isReclaimable else {
            errorMessage = "File is not eligible for eviction or is already cloud-only."
            showErrorAlert = true
            return
        }

        pendingActionMode = .evictLocalOnly
        pendingEvictionItems = [item]
        pendingEvictionFolderURLs = []
        pendingEvictionTitle = "Evict Local Copy: \(item.name)"
        pendingEvictionDescription = "Unloads '\(item.name)' from local storage (\(ByteFormatter.string(fromByteCount: item.allocatedSize))) while preserving it in the cloud."
        showConfirmationSheet = true
    }

    public func deleteSingle(item: CloudItem) {
        let isLocal = isProviderLocalOnly(item.providerId)
        pendingActionMode = .deleteEverywhere
        pendingEvictionItems = [item]
        pendingEvictionFolderURLs = []
        pendingEvictionTitle = isLocal ? "Delete File: \(item.name)" : "Delete from Mac & Cloud: \(item.name)"
        pendingEvictionDescription = isLocal
            ? "Permanently deletes '\(item.name)' (\(ByteFormatter.string(fromByteCount: item.allocatedSize))) from your disk."
            : "Permanently deletes '\(item.name)' (\(ByteFormatter.string(fromByteCount: item.fileSize))) from your Mac and cloud storage."
        showConfirmationSheet = true
    }

    public func promptEvictSelection() {
        if isActiveProviderLocalOnly {
            promptDeleteSelection()
            return
        }
        let items = allItems.filter { selectedItemIds.contains($0.id) && $0.isReclaimable }
        guard !items.isEmpty else {
            errorMessage = "No reclaimable downloaded files selected."
            showErrorAlert = true
            return
        }

        let totalFreed = items.reduce(0) { $0 + $1.allocatedSize }
        pendingActionMode = .evictLocalOnly
        pendingEvictionItems = items
        pendingEvictionFolderURLs = []
        pendingEvictionTitle = "Evict Local Copies (\(items.count) Files)"
        pendingEvictionDescription = "Unloads \(items.count) selected files (\(ByteFormatter.string(fromByteCount: totalFreed))) on your Mac while preserving them in the cloud."
        showConfirmationSheet = true
    }

    public func promptDeleteSelection() {
        let items = allItems.filter { selectedItemIds.contains($0.id) }
        guard !items.isEmpty else {
            errorMessage = "No files selected."
            showErrorAlert = true
            return
        }

        let isLocal = isActiveProviderLocalOnly
        let totalSize = items.reduce(0) { $0 + (isLocal ? $1.allocatedSize : $1.fileSize) }
        pendingActionMode = .deleteEverywhere
        pendingEvictionItems = items
        pendingEvictionFolderURLs = []
        pendingEvictionTitle = isLocal
            ? "Delete \(items.count) Selected Files"
            : "Delete \(items.count) Files from Mac & Cloud"
        pendingEvictionDescription = isLocal
            ? "Permanently deletes \(items.count) files (\(ByteFormatter.string(fromByteCount: totalSize))) from your disk."
            : "Permanently deletes \(items.count) files (\(ByteFormatter.string(fromByteCount: totalSize))) from your Mac and cloud storage."
        showConfirmationSheet = true
    }

    public func promptEvictAllFiltered() {
        if isActiveProviderLocalOnly {
            let items = filteredAndSortedItems
            guard !items.isEmpty else {
                errorMessage = "No files match current filters."
                showErrorAlert = true
                return
            }
            let totalSize = items.reduce(0) { $0 + $1.allocatedSize }
            pendingActionMode = .deleteEverywhere
            pendingEvictionItems = items
            pendingEvictionFolderURLs = []
            pendingEvictionTitle = "Delete All \(items.count) Filtered Files"
            pendingEvictionDescription = "Permanently deletes \(items.count) matching files (\(ByteFormatter.string(fromByteCount: totalSize))) from your disk."
            showConfirmationSheet = true
            return
        }

        let items = filteredAndSortedItems.filter { $0.isReclaimable }
        guard !items.isEmpty else {
            errorMessage = "No downloaded files match current filters."
            showErrorAlert = true
            return
        }

        let totalFreed = items.reduce(0) { $0 + $1.allocatedSize }
        pendingActionMode = .evictLocalOnly
        pendingEvictionItems = items
        pendingEvictionFolderURLs = []
        pendingEvictionTitle = "Evict All Matching Local Copies"
        pendingEvictionDescription = "Unloads local copies across \(items.count) matching files (\(ByteFormatter.string(fromByteCount: totalFreed))) while preserving them in the cloud."
        showConfirmationSheet = true
    }

    public func promptEvictFolder(node: CloudFolderNode) {
        if isProviderLocalOnly(node.providerId) {
            promptDeleteFolder(node: node)
            return
        }
        let folderPath = node.path
        let folderPrefix = folderPath.hasSuffix("/") ? folderPath : (folderPath + "/")
        let itemsInFolder = allItems.filter {
            $0.isReclaimable && ($0.parentFolderPath == folderPath || $0.path.hasPrefix(folderPrefix))
        }

        guard !itemsInFolder.isEmpty else {
            errorMessage = "Folder '\(node.name)' contains no downloaded files to evict."
            showErrorAlert = true
            return
        }

        let totalFreed = itemsInFolder.reduce(0) { $0 + $1.allocatedSize }
        pendingActionMode = .evictLocalOnly
        pendingEvictionItems = itemsInFolder
        pendingEvictionFolderURLs = [node.url]
        pendingEvictionTitle = "Evict Local Copies in '\(node.name)'"
        pendingEvictionDescription = "Recursively unloads \(itemsInFolder.count.formatted()) downloaded files in '\(node.name)' (\(ByteFormatter.string(fromByteCount: totalFreed))) while keeping them in the cloud."
        showConfirmationSheet = true
    }

    public func promptDeleteFolder(node: CloudFolderNode) {
        let folderPath = node.path
        let folderPrefix = folderPath.hasSuffix("/") ? folderPath : (folderPath + "/")
        let itemsInFolder = allItems.filter {
            $0.parentFolderPath == folderPath || $0.path.hasPrefix(folderPrefix)
        }

        guard !itemsInFolder.isEmpty else {
            errorMessage = "Folder '\(node.name)' is empty."
            showErrorAlert = true
            return
        }

        let isLocal = isProviderLocalOnly(node.providerId)
        let totalLocal = itemsInFolder.reduce(0) { $0 + $1.allocatedSize }
        let totalCloud = itemsInFolder.reduce(0) { $0 + $1.fileSize }
        pendingActionMode = .deleteEverywhere
        pendingEvictionItems = itemsInFolder
        pendingEvictionFolderURLs = [node.url]
        pendingEvictionTitle = isLocal
            ? "Delete Folder '\(node.name)'"
            : "Delete '\(node.name)' from Mac & Cloud"
        pendingEvictionDescription = isLocal
            ? "Permanently deletes '\(node.name)' (\(itemsInFolder.count.formatted()) files, \(ByteFormatter.string(fromByteCount: totalLocal))) from your disk."
            : "Permanently deletes '\(node.name)' (\(itemsInFolder.count.formatted()) files, \(ByteFormatter.string(fromByteCount: totalLocal)) local / \(ByteFormatter.string(fromByteCount: totalCloud)) cloud) from your Mac and cloud storage."
        showConfirmationSheet = true
    }

    /// Recursively evicts all downloaded files across a list of folders (e.g., all matching `node_modules` folders).
    public func promptEvictMultipleFolders(nodes: [CloudFolderNode], label: String) {
        if isActiveProviderLocalOnly {
            promptDeleteMultipleFolders(nodes: nodes, label: label)
            return
        }
        let reclaimableFolders = nodes.filter { $0.reclaimableBytes > 0 }
        guard !reclaimableFolders.isEmpty else {
            errorMessage = "No downloaded files to evict in the matching folders."
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
            errorMessage = "No downloaded files to evict in the matching folders."
            showErrorAlert = true
            return
        }

        let totalFreed = matchedItems.reduce(0) { $0 + $1.allocatedSize }
        pendingActionMode = .evictLocalOnly
        pendingEvictionItems = matchedItems
        pendingEvictionFolderURLs = reclaimableFolders.map { $0.url }
        pendingEvictionTitle = "Evict Local Copies in \(reclaimableFolders.count) Folders (\(label))"
        pendingEvictionDescription = "Recursively unloads \(matchedItems.count.formatted()) downloaded files across \(reclaimableFolders.count) folders (\(ByteFormatter.string(fromByteCount: totalFreed))) while keeping them in the cloud."
        showConfirmationSheet = true
    }

    /// Permanently deletes all matching folders (e.g., all `node_modules`) from both local disk and cloud storage.
    public func promptDeleteMultipleFolders(nodes: [CloudFolderNode], label: String) {
        guard !nodes.isEmpty else {
            errorMessage = "No folders selected to delete."
            showErrorAlert = true
            return
        }

        let exactPaths = Set(nodes.map { $0.path })
        let prefixes = nodes.map { $0.path.hasSuffix("/") ? $0.path : ($0.path + "/") }

        var matchedItems: [CloudItem] = []
        var seenIds = Set<UUID>()

        for item in allItems {
            if exactPaths.contains(item.parentFolderPath) || prefixes.contains(where: { item.path.hasPrefix($0) }) {
                if seenIds.insert(item.id).inserted {
                    matchedItems.append(item)
                }
            }
        }

        guard !matchedItems.isEmpty else {
            errorMessage = "No files found in the matching folders."
            showErrorAlert = true
            return
        }

        let isLocal = isActiveProviderLocalOnly
        let totalLocal = matchedItems.reduce(0) { $0 + $1.allocatedSize }
        let totalCloud = matchedItems.reduce(0) { $0 + $1.fileSize }
        pendingActionMode = .deleteEverywhere
        pendingEvictionItems = matchedItems
        pendingEvictionFolderURLs = nodes.map { $0.url }
        pendingEvictionTitle = isLocal
            ? "Delete All \(nodes.count) '\(label)' Folders"
            : "Delete All \(nodes.count) '\(label)' Folders from Mac & Cloud"
        pendingEvictionDescription = isLocal
            ? "Permanently deletes \(nodes.count) '\(label)' folders (\(matchedItems.count.formatted()) files, \(ByteFormatter.string(fromByteCount: totalLocal))) from your disk."
            : "Permanently deletes \(nodes.count) '\(label)' folders (\(matchedItems.count.formatted()) files, \(ByteFormatter.string(fromByteCount: totalLocal)) local / \(ByteFormatter.string(fromByteCount: totalCloud)) cloud) from your Mac and cloud storage."
        showConfirmationSheet = true
    }

    public func togglePauseEviction() {
        guard isEvicting, let ctrl = currentEvictControl else { return }
        if isEvictionPaused {
            isEvictionPaused = false
            ctrl.resume()
        } else {
            isEvictionPaused = true
            ctrl.pause()
        }
    }

    public func stopEviction() {
        guard isEvicting else { return }
        currentEvictControl?.stop()
        isEvictionPaused = false
        evictionProgressText = "Stopping safely after current operation..."
    }

    public func executeConfirmedEviction() {
        showConfirmationSheet = false
        let mode = pendingActionMode
        let itemsToProcess = pendingEvictionItems
        let folderURLsToProcess = pendingEvictionFolderURLs
        guard !itemsToProcess.isEmpty else { return }
        let targetProviderId = itemsToProcess.first?.providerId ?? selectedProvider?.id

        let control = ScanSessionControl()
        currentEvictControl = control
        isEvicting = true
        isEvictionPaused = false
        evictionProgressCurrent = 0
        evictionProgressTotal = itemsToProcess.count
        evictionProgressText = mode == .deleteEverywhere
            ? "Deleting files..."
            : "Evicting local copies..."

        currentEvictTask = Task { [weak self] in
            guard let self = self else { return }
            let report: EvictionReport
            if mode == .deleteEverywhere {
                report = await EvictionService.shared.deleteBatch(
                    items: itemsToProcess,
                    rootFolderURLs: folderURLsToProcess,
                    control: control
                ) { [weak self] cur, total, freed in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.evictionProgressCurrent = cur
                        self.evictionProgressTotal = total
                        self.evictionProgressText = "Deleted \(cur.formatted()) of \(total.formatted()) files (\(ByteFormatter.string(fromByteCount: freed)) freed)..."
                    }
                }
            } else {
                report = await EvictionService.shared.evictBatch(
                    items: itemsToProcess,
                    rootFolderURLs: folderURLsToProcess,
                    control: control
                ) { [weak self] cur, total, freed in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.evictionProgressCurrent = cur
                        self.evictionProgressTotal = total
                        if self.isEvictionPaused {
                            self.evictionProgressText = "Paused at \(cur.formatted()) of \(total.formatted()) files (\(ByteFormatter.string(fromByteCount: freed)) freed)"
                        } else {
                            self.evictionProgressText = "Evicted \(cur.formatted()) of \(total.formatted()) files (\(ByteFormatter.string(fromByteCount: freed)) freed)..."
                        }
                    }
                }
            }

            self.isEvicting = false
            self.isEvictionPaused = false
            self.currentEvictControl = nil
            self.lastReport = report
            self.showReportAlert = true
            self.selectedItemIds.subtract(report.evictedItemIds)

            // Update state in memory immediately without restarting a slow full scan!
            if let pid = targetProviderId, !report.evictedItemIds.isEmpty {
                if mode == .deleteEverywhere {
                    self.applyDeletionInMemory(
                        providerId: pid,
                        deletedIds: report.evictedItemIds,
                        deletedFolderPaths: report.deletedFolderPaths
                    )
                } else {
                    self.applyEvictionInMemory(providerId: pid, evictedIds: report.evictedItemIds)
                }
            }
        }
    }

    /// Updates cached items and folder tree metrics in-memory in milliseconds after permanent deletion.
    private func applyDeletionInMemory(providerId: String, deletedIds: Set<UUID>, deletedFolderPaths: [String]) {
        guard var st = providerStates[providerId] else { return }

        var deltaByFolder: [String: (cloudBytes: Int64, reclaimBytes: Int64, totalCount: Int, downloadedCount: Int)] = [:]
        var totalCloudDeleted: Int64 = 0
        var totalReclaimFreed: Int64 = 0
        var totalDownloadedDeleted = 0

        var remainingItems: [CloudItem] = []
        remainingItems.reserveCapacity(max(0, st.items.count - deletedIds.count))

        for item in st.items {
            if deletedIds.contains(item.id) {
                totalCloudDeleted += item.fileSize
                let reclaim = item.isReclaimable ? item.allocatedSize : 0
                let dlCount = item.isReclaimable ? 1 : 0
                totalReclaimFreed += reclaim
                totalDownloadedDeleted += dlCount

                let parentPath = item.parentFolderPath
                var entry = deltaByFolder[parentPath] ?? (0, 0, 0, 0)
                entry.cloudBytes += item.fileSize
                entry.reclaimBytes += reclaim
                entry.totalCount += 1
                entry.downloadedCount += dlCount
                deltaByFolder[parentPath] = entry
            } else {
                remainingItems.append(item)
            }
        }

        st.items = remainingItems
        st.scannedCount = remainingItems.count
        st.totalCloudBytes = max(0, st.totalCloudBytes - totalCloudDeleted)
        st.reclaimableBytes = max(0, st.reclaimableBytes - totalReclaimFreed)
        st.downloadedCount = max(0, st.downloadedCount - totalDownloadedDeleted)
        st.scanProgressText = "Scan complete • \(formatScanMetrics(files: st.items.count, bytes: st.reclaimableBytes, isLocalOnly: isProviderLocalOnly(providerId)))"

        let deletedFolderSet = Set(deletedFolderPaths)
        let deletedFolderPrefixes = deletedFolderPaths.map { $0.hasSuffix("/") ? $0 : ($0 + "/") }

        func isDeletedFolder(_ path: String) -> Bool {
            if deletedFolderSet.contains(path) { return true }
            return deletedFolderPrefixes.contains(where: { path.hasPrefix($0) })
        }

        func updateAndPruneNode(_ node: inout CloudFolderNode) -> Bool {
            if isDeletedFolder(node.path) {
                return false
            }
            let folderPath = node.path
            let folderPrefix = folderPath.hasSuffix("/") ? folderPath : (folderPath + "/")
            var cloudDelta: Int64 = 0
            var reclaimDelta: Int64 = 0
            var totalDelta = 0
            var dlDelta = 0

            for (dirPath, delta) in deltaByFolder {
                if dirPath == folderPath || dirPath.hasPrefix(folderPrefix) {
                    cloudDelta += delta.cloudBytes
                    reclaimDelta += delta.reclaimBytes
                    totalDelta += delta.totalCount
                    dlDelta += delta.downloadedCount
                }
            }

            node.totalCloudBytes = max(0, node.totalCloudBytes - cloudDelta)
            node.reclaimableBytes = max(0, node.reclaimableBytes - reclaimDelta)
            node.totalFilesCount = max(0, node.totalFilesCount - totalDelta)
            node.downloadedFilesCount = max(0, node.downloadedFilesCount - dlDelta)

            if node.totalFilesCount == 0 {
                return false
            }

            var keptChildren: [CloudFolderNode] = []
            for var child in node.children {
                if updateAndPruneNode(&child) {
                    keptChildren.append(child)
                }
            }
            keptChildren.sort { $0.reclaimableBytes > $1.reclaimableBytes }
            node.children = keptChildren
            return true
        }

        var keptTopFolders: [CloudFolderNode] = []
        for var node in st.folderNodes {
            if updateAndPruneNode(&node) {
                keptTopFolders.append(node)
            }
        }
        keptTopFolders.sort { $0.reclaimableBytes > $1.reclaimableBytes }
        st.folderNodes = keptTopFolders

        var keptAllFolders: [CloudFolderNode] = []
        for var node in st.allFolders {
            if updateAndPruneNode(&node) {
                keptAllFolders.append(node)
            }
        }
        st.allFolders = keptAllFolders

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
        let summaryStr = formatScanMetrics(files: st.items.count, bytes: st.reclaimableBytes, isLocalOnly: isProviderLocalOnly(providerId))
        if st.isPaused {
            st.scanProgressText = "Scan paused • \(summaryStr)"
        } else if !st.isScanning {
            st.scanProgressText = "Scan complete • \(summaryStr)"
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

    // MARK: - Duplicate Finder & Link Resolution

    public func providerName(for providerId: String) -> String {
        providers.first(where: { $0.id == providerId })?.name ?? "Drive"
    }

    public func providerType(for providerId: String) -> ProviderType {
        providers.first(where: { $0.id == providerId })?.type ?? .custom
    }

    /// Starts scanning for exact duplicate files across the current source or all scanned sources.
    public func startDuplicateScan() {
        duplicateScanControl?.stop()
        duplicateScanTask?.cancel()

        let sourceItems: [CloudItem]
        switch duplicateScanScope {
        case .currentSource:
            sourceItems = allItems
        case .allScannedSources:
            var combined: [CloudItem] = []
            for p in providers {
                if let st = providerStates[p.id], !st.items.isEmpty {
                    combined.append(contentsOf: st.items)
                }
            }
            sourceItems = combined
        }

        guard !sourceItems.isEmpty else {
            errorMessage = "Please scan at least one drive or folder first before running Duplicate Finder."
            showErrorAlert = true
            return
        }

        let control = ScanSessionControl()
        duplicateScanControl = control
        isScanningDuplicates = true
        duplicateGroups = []
        selectedDuplicateGroupIds.removeAll()
        duplicateScanProcessed = 0
        duplicateScanTotal = sourceItems.count
        duplicateScanProgressText = "Grouping \(sourceItems.count.formatted()) files by size..."

        let minSize = duplicateMinSizeBytes
        let includeCloud = duplicateIncludeCloudOnly

        duplicateScanTask = Task { [weak self] in
            guard let self = self else { return }
            let groups = await DuplicateService.shared.findDuplicates(
                items: sourceItems,
                minimumFileSize: minSize,
                includeCloudOnlyByNameAndSize: includeCloud,
                control: control
            ) { [weak self] prog in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.duplicateScanProcessed = prog.processedCount
                    self.duplicateScanTotal = max(1, prog.totalCandidates)
                    self.duplicateScanProgressText = "\(prog.phase.rawValue) (\(prog.processedCount.formatted()) / \(prog.totalCandidates.formatted()))"
                }
            }

            guard !Task.isCancelled else { return }
            self.isScanningDuplicates = false
            self.duplicateScanControl = nil
            self.duplicateGroups = groups
            let totalRedundant = groups.reduce(0) { $0 + $1.redundantLogicalBytes }
            let totalLocalReclaim = groups.reduce(0) { $0 + $1.reclaimableLocalBytes }
            if groups.isEmpty {
                self.duplicateScanProgressText = "No duplicate files found matching criteria."
            } else {
                self.duplicateScanProgressText = "Found \(groups.count.formatted()) duplicate groups • \(ByteFormatter.string(fromByteCount: totalLocalReclaim)) local (\(ByteFormatter.string(fromByteCount: totalRedundant)) total) redundant"
            }
        }
    }

    public func stopDuplicateScan() {
        duplicateScanControl?.stop()
        duplicateScanTask?.cancel()
        isScanningDuplicates = false
        duplicateScanControl = nil
        duplicateScanProgressText = "Duplicate scan stopped."
    }

    /// Sets the chosen Primary copy for a specific DuplicateGroup.
    public func setPrimaryItem(groupId: String, itemId: UUID) {
        if let idx = duplicateGroups.firstIndex(where: { $0.id == groupId }) {
            duplicateGroups[idx].primaryItemId = itemId
        }
        if let pIdx = pendingDuplicateGroups.firstIndex(where: { $0.id == groupId }) {
            pendingDuplicateGroups[pIdx].primaryItemId = itemId
        }
    }

    /// Smart default strategy based on whether duplicates reside in Cloud drives vs Local custom folders.
    private func recommendedStrategy(for groups: [DuplicateGroup]) -> DuplicateResolutionStrategy {
        let providersMap = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
        for group in groups {
            for dup in group.duplicateItems {
                if let p = providersMap[dup.providerId], p.type != .custom {
                    // For cloud drives (iCloud Drive, Google Drive, OneDrive, Dropbox), Finder Alias is cloud-safe
                    return .macOSAlias
                }
            }
        }
        return .symlink
    }

    public func promptResolveDuplicateGroup(_ group: DuplicateGroup) {
        pendingDuplicateGroups = [group]
        selectedResolutionStrategy = recommendedStrategy(for: [group])
        showDuplicateResolveSheet = true
    }

    public func promptResolveSelectedDuplicateGroups() {
        let targets: [DuplicateGroup]
        if selectedDuplicateGroupIds.isEmpty {
            targets = duplicateGroups
        } else {
            targets = duplicateGroups.filter { selectedDuplicateGroupIds.contains($0.id) }
        }
        guard !targets.isEmpty else {
            errorMessage = "No duplicate groups to resolve."
            showErrorAlert = true
            return
        }
        pendingDuplicateGroups = targets
        selectedResolutionStrategy = recommendedStrategy(for: targets)
        showDuplicateResolveSheet = true
    }

    public func currentDuplicateWarnings() -> [DuplicatePlatformWarning] {
        let providersMap = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
        return DuplicateService.shared.evaluateWarnings(
            strategy: selectedResolutionStrategy,
            groups: pendingDuplicateGroups,
            providersById: providersMap
        )
    }

    public func executeConfirmedDuplicateResolution() {
        let relocateDir: URL? = relocatePrimaryToCustomFolder ? relocatedPrimaryDirectoryURL : nil
        if relocatePrimaryToCustomFolder && relocateDir == nil {
            errorMessage = "Please choose a destination folder to move the Primary file(s) into."
            showErrorAlert = true
            return
        }

        showDuplicateResolveSheet = false
        let groupsToResolve = pendingDuplicateGroups
        let strategy = selectedResolutionStrategy
        let relativeSymlinks = useRelativeSymlinks
        guard !groupsToResolve.isEmpty else { return }

        let totalDups = groupsToResolve.reduce(0) { $0 + $1.duplicateItems.count }
        let control = ScanSessionControl()
        currentEvictControl = control
        isEvicting = true
        isEvictionPaused = false
        evictionProgressCurrent = 0
        evictionProgressTotal = max(1, totalDups)
        evictionProgressText = "Resolving \(totalDups) duplicates via \(strategy.shortTitle)..."

        currentEvictTask = Task { [weak self] in
            guard let self = self else { return }
            let report = await DuplicateService.shared.resolveDuplicates(
                groups: groupsToResolve,
                strategy: strategy,
                useRelativeSymlinksWhenSameSource: relativeSymlinks,
                relocatePrimaryToDirectory: relocateDir,
                control: control
            )

            self.isEvicting = false
            self.isEvictionPaused = false
            self.currentEvictControl = nil
            self.lastDuplicateReport = report
            self.showDuplicateReportAlert = true

            if !report.resolvedDuplicateIds.isEmpty || report.groupsResolved > 0 {
                // Remove resolved duplicate items from duplicateGroups
                var updatedGroups: [DuplicateGroup] = []
                for var group in self.duplicateGroups {
                    group.items.removeAll { report.resolvedDuplicateIds.contains($0.id) }
                    if group.items.count > 1 {
                        updatedGroups.append(group)
                    } else {
                        self.selectedDuplicateGroupIds.remove(group.id)
                    }
                }
                self.duplicateGroups = updatedGroups

                // Also update providerStates in memory for all affected providers
                let affectedProviders = Set(groupsToResolve.flatMap { $0.duplicateItems.map { $0.providerId } })
                for pid in affectedProviders {
                    self.applyDeletionInMemory(
                        providerId: pid,
                        deletedIds: report.resolvedDuplicateIds,
                        deletedFolderPaths: []
                    )
                }
            }
        }
    }
}
