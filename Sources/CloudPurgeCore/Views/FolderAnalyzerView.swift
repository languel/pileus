import SwiftUI

struct FolderAnalyzerView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var folderSortOption: FolderSortField = .reclaimableBytes

    private static let quickPresets = [
        "node_modules",
        ".venv",
        ".build",
        "build",
        "dist",
        "__pycache__",
        "Pods",
        ".git"
    ]

    enum FolderSortField: String, CaseIterable, Identifiable {
        case reclaimableBytes = "Most Reclaimable Space"
        case percentage = "Highest % Downloaded"
        case totalSize = "Largest Cloud Size"
        case name = "Folder Name"

        var id: String { rawValue }

        func label(isLocalOnly: Bool) -> String {
            guard isLocalOnly else { return rawValue }
            switch self {
            case .reclaimableBytes: return "Largest Size on Disk"
            case .percentage: return "Highest Disk Ratio"
            case .totalSize: return "Largest Logical Size"
            case .name: return "Folder Name"
            }
        }
    }

    private var activeQuery: String {
        viewModel.filterOptions.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !activeQuery.isEmpty ||
        viewModel.filterOptions.statusFilter != .all ||
        viewModel.filterOptions.sizeFilter != .any
    }

    private var displayedFolders: [CloudFolderNode] {
        let baseNodes: [CloudFolderNode]
        if isSearching {
            let q = activeQuery
            let minBytes = viewModel.filterOptions.sizeFilter.minimumBytes
            let status = viewModel.filterOptions.statusFilter

            baseNodes = viewModel.allFolders.filter { node in
                if !q.isEmpty {
                    let matchesName = node.name.range(of: q, options: .caseInsensitive) != nil
                    let matchesPath = node.relativePath.range(of: q, options: .caseInsensitive) != nil
                    if !matchesName && !matchesPath {
                        return false
                    }
                }
                if !viewModel.isActiveProviderLocalOnly {
                    if status == .downloadedOnly && node.reclaimableBytes == 0 {
                        return false
                    }
                    if status == .cloudOnly && node.reclaimableBytes > 0 {
                        return false
                    }
                }
                if minBytes > 0 && max(node.reclaimableBytes, node.totalCloudBytes) < minBytes {
                    return false
                }
                return true
            }
        } else {
            baseNodes = viewModel.folderNodes
        }
        return sortedFolders(baseNodes)
    }

    private var matchingReclaimableFolders: [CloudFolderNode] {
        displayedFolders.filter { $0.reclaimableBytes > 0 }
    }

    private var matchingTotalReclaimableBytes: Int64 {
        matchingReclaimableFolders.reduce(0) { $0 + $1.reclaimableBytes }
    }

    var body: some View {
        let isLocalOnly = viewModel.isActiveProviderLocalOnly

        VStack(spacing: 0) {
            // Header bar for Folder Analyzer + Quick Presets
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Text("Folders")
                            .font(.headline)
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .help(isLocalOnly
                                ? "Search for heavy folders like node_modules or .venv at any depth, or browse the folder tree to inspect disk usage."
                                : "Search for heavy folders like node_modules or .venv at any depth, or browse the folder tree to recursively evict local copies or delete from cloud.")
                    }

                    // Quick Folder Search Presets inline
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(Self.quickPresets, id: \.self) { preset in
                                let isSelected = activeQuery.caseInsensitiveCompare(preset) == .orderedSame
                                Button(action: {
                                    if isSelected {
                                        viewModel.filterOptions.searchText = ""
                                    } else {
                                        viewModel.filterOptions.searchText = preset
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "folder")
                                            .font(.system(size: 9))
                                        Text(preset)
                                            .font(.caption2)
                                            .fontWeight(isSelected ? .semibold : .regular)
                                    }
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule()
                                            .fill(isSelected ? Color.accentColor.opacity(0.18) : Color(nsColor: .windowBackgroundColor))
                                    )
                                    .foregroundColor(isSelected ? .accentColor : .primary)
                                    .overlay(
                                        Capsule()
                                            .stroke(isSelected ? Color.accentColor.opacity(0.6) : Color(nsColor: .separatorColor), lineWidth: 0.5)
                                    )
                                }
                                .buttonStyle(.plain)
                                .help("Filter folders matching '\(preset)'")
                            }

                            if !activeQuery.isEmpty {
                                Button("Clear") {
                                    viewModel.filterOptions.searchText = ""
                                }
                                .font(.caption2)
                                .buttonStyle(.plain)
                                .foregroundColor(.secondary)
                                .padding(.leading, 4)
                            }
                        }
                    }

                    Spacer()

                    if isSearching && !displayedFolders.isEmpty {
                        let label = activeQuery.isEmpty ? "Filtered Folders" : activeQuery

                        if !isLocalOnly && !matchingReclaimableFolders.isEmpty {
                            Button(action: {
                                viewModel.promptEvictMultipleFolders(nodes: matchingReclaimableFolders, label: label)
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.up.to.line.compact")
                                    Text("Evict All \(matchingReclaimableFolders.count) (\(ByteFormatter.string(fromByteCount: matchingTotalReclaimableBytes)))")
                                }
                                .font(.caption)
                                .fontWeight(.medium)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.teal)
                            .controlSize(.small)
                            .disabled(viewModel.isEvicting)
                            .help("Evict local copies across all matching folders while keeping cloud copies intact.")
                        }

                        Button(action: {
                            viewModel.promptDeleteMultipleFolders(nodes: displayedFolders, label: label)
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "trash")
                                Text(isLocalOnly
                                    ? "Delete All \(displayedFolders.count) (\(ByteFormatter.string(fromByteCount: matchingTotalReclaimableBytes)))"
                                    : "Delete All \(displayedFolders.count)")
                            }
                            .font(.caption)
                            .fontWeight(.medium)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .controlSize(.small)
                        .disabled(viewModel.isEvicting)
                        .help(isLocalOnly
                            ? "Permanently delete all \(displayedFolders.count) matching folders from your disk."
                            : "Permanently delete all \(displayedFolders.count) matching folders from Mac and Cloud storage.")
                    }

                    Picker("Sort", selection: $folderSortOption) {
                        ForEach(FolderSortField.allCases) { opt in
                            Text(opt.label(isLocalOnly: isLocalOnly)).tag(opt)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 195)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if viewModel.allFolders.isEmpty && viewModel.isScanning {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Scanning folders in \(viewModel.selectedProvider?.name ?? "location")...")
                        .font(.headline)
                    Text(viewModel.scanProgressText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 500)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if displayedFolders.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "folder")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.6))
                    if isSearching {
                        Text("No matching folders")
                            .font(.headline)
                        Button("Reset Filters") {
                            viewModel.filterOptions.searchText = ""
                            viewModel.filterOptions.statusFilter = .all
                            viewModel.filterOptions.sizeFilter = .any
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Text("No folders indexed")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(displayedFolders) { node in
                        FolderRowView(node: node, viewModel: viewModel)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }

            // Footer summary bar for Folder Analyzer
            HStack(spacing: 10) {
                if isSearching {
                    Text(isLocalOnly
                        ? "\(displayedFolders.count.formatted()) matching folders (\(ByteFormatter.string(fromByteCount: matchingTotalReclaimableBytes)) on disk)"
                        : "\(displayedFolders.count.formatted()) matching folders (\(ByteFormatter.string(fromByteCount: matchingTotalReclaimableBytes)) reclaimable)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("\(viewModel.allFolders.count.formatted()) folders across \(viewModel.folderNodes.count) top-level directories")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(viewModel.scanProgressText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    private func sortedFolders(_ nodes: [CloudFolderNode]) -> [CloudFolderNode] {
        return nodes.sorted { lhs, rhs in
            switch folderSortOption {
            case .reclaimableBytes:
                if lhs.reclaimableBytes != rhs.reclaimableBytes {
                    return lhs.reclaimableBytes > rhs.reclaimableBytes
                }
                return lhs.totalCloudBytes > rhs.totalCloudBytes
            case .percentage:
                return lhs.percentageReclaimable > rhs.percentageReclaimable
            case .totalSize:
                return lhs.totalCloudBytes > rhs.totalCloudBytes
            case .name:
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }
    }
}

struct FolderRowView: View {
    let node: CloudFolderNode
    @ObservedObject var viewModel: AppViewModel
    @State private var isExpanded: Bool = false

    var body: some View {
        let isLocalOnly = viewModel.isActiveProviderLocalOnly

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                // Disclosure button if has children
                if !node.children.isEmpty {
                    Button(action: { isExpanded.toggle() }) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 12)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 12)
                }

                // Reveal in Finder icon BEFORE folder name
                Button(action: { viewModel.revealInFinder(url: node.url) }) {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Reveal '\(node.name)' in Finder")

                Image(systemName: "folder.fill")
                    .font(.system(size: 17))
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(node.name)
                        .font(.body)
                        .fontWeight(.medium)

                    Text(node.relativePath)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .help(node.url.path)
                }

                Spacer()

                // Stats breakdown
                VStack(alignment: .trailing, spacing: 2) {
                    if isLocalOnly {
                        HStack(spacing: 6) {
                            Text(ByteFormatter.string(fromByteCount: node.reclaimableBytes))
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)

                            Text("on disk")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Text("\(node.totalFilesCount.formatted()) files • \(ByteFormatter.string(fromByteCount: node.totalCloudBytes)) logical")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        HStack(spacing: 6) {
                            Text(ByteFormatter.string(fromByteCount: node.reclaimableBytes))
                                .fontWeight(.semibold)
                                .foregroundColor(node.reclaimableBytes > 0 ? .teal : .secondary)

                            Text("/ \(ByteFormatter.string(fromByteCount: node.totalCloudBytes))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Text("\(node.percentageString) local (\(node.downloadedFilesCount)/\(node.totalFilesCount) files)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(minWidth: 165, alignment: .trailing)

                if !isLocalOnly {
                    // Visual Mini-Bar for Cloud vs Local
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(nsColor: .separatorColor).opacity(0.3))
                            .frame(width: 64, height: 5)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(node.reclaimableBytes > 0 ? Color.teal.opacity(0.85) : Color.clear)
                            .frame(width: max(0, min(64, 64 * CGFloat(node.percentageReclaimable / 100.0))), height: 5)
                    }
                    .frame(width: 64)
                    .help("\(node.percentageString) of this folder's cloud size is currently stored on local disk.")
                }

                // Actions
                HStack(spacing: 6) {
                    if !isLocalOnly {
                        // Recursive evict local copies button
                        Button(action: { viewModel.promptEvictFolder(node: node) }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.to.line.compact")
                                Text("Evict")
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(.teal)
                        .controlSize(.small)
                        .disabled(node.reclaimableBytes == 0 || viewModel.isEvicting)
                        .help("Evict downloaded files in '\(node.name)' to reclaim local space (remains in cloud)")
                    }

                    // Delete button
                    Button(action: { viewModel.promptDeleteFolder(node: node) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Delete")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)
                    .disabled(viewModel.isEvicting)
                    .help(isLocalOnly
                        ? "Permanently delete '\(node.name)' from your Mac"
                        : "Permanently delete '\(node.name)' from your Mac and Cloud storage")

                    // Filter files to this folder
                    Button(action: {
                        viewModel.filterOptions.selectedFolderPrefix = node.relativePath
                        viewModel.activeTab = .files
                    }) {
                        Image(systemName: "list.bullet")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Inspect individual files in '\(node.name)'")
                }
            }
            .contextMenu {
                if !isLocalOnly && node.reclaimableBytes > 0 {
                    Button {
                        viewModel.promptEvictFolder(node: node)
                    } label: {
                        Label("Evict Local Copies (\(ByteFormatter.string(fromByteCount: node.reclaimableBytes)))", systemImage: "arrow.up.to.line.compact")
                    }
                }

                Button(role: .destructive) {
                    viewModel.promptDeleteFolder(node: node)
                } label: {
                    Label(isLocalOnly ? "Delete '\(node.name)'..." : "Delete '\(node.name)' from Mac & Cloud...", systemImage: "trash")
                }

                Divider()

                Button {
                    viewModel.filterOptions.selectedFolderPrefix = node.relativePath
                    viewModel.activeTab = .files
                } label: {
                    Label("View Files in Folder", systemImage: "list.bullet")
                }

                Button {
                    viewModel.revealInFinder(url: node.url)
                } label: {
                    Label("Reveal in Finder", systemImage: "arrow.up.forward.square")
                }
            }

            // Expanded Subfolders
            if isExpanded && !node.children.isEmpty {
                VStack(spacing: 6) {
                    ForEach(node.children) { child in
                        FolderRowView(node: child, viewModel: viewModel)
                            .padding(.leading, 22)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 5)
    }
}
