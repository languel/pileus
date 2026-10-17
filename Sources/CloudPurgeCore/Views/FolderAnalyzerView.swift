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
                if status == .downloadedOnly && node.reclaimableBytes == 0 {
                    return false
                }
                if status == .cloudOnly && node.reclaimableBytes > 0 {
                    return false
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
        VStack(spacing: 0) {
            // Header bar for Folder Analyzer + Quick Presets
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Folder Space Breakdown")
                            .font(.headline)
                        Text("Search for heavy folders like node_modules or .venv at any depth, or browse the folder tree to recursively evict local copies.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if isSearching && !matchingReclaimableFolders.isEmpty {
                        Button(action: {
                            let label = activeQuery.isEmpty ? "Filtered Folders" : activeQuery
                            viewModel.promptEvictMultipleFolders(nodes: matchingReclaimableFolders, label: label)
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.up.to.line.compact")
                                Text("Evict All \(matchingReclaimableFolders.count) Folders (\(ByteFormatter.string(fromByteCount: matchingTotalReclaimableBytes)))")
                            }
                            .font(.caption)
                            .fontWeight(.medium)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(viewModel.isEvicting)
                    }

                    Picker("Sort by:", selection: $folderSortOption) {
                        ForEach(FolderSortField.allCases) { opt in
                            Text(opt.rawValue).tag(opt)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 220)
                }

                // Quick Folder Search Presets
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Text("Quick Find:")
                            .font(.caption2)
                            .foregroundColor(.secondary)

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
                                    Image(systemName: "folder.badge.gearshape")
                                        .font(.system(size: 10))
                                    Text(preset)
                                        .font(.caption2)
                                        .fontWeight(isSelected ? .semibold : .regular)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? Color.accentColor : Color(nsColor: .windowBackgroundColor))
                                )
                                .foregroundColor(isSelected ? .white : .primary)
                                .overlay(
                                    Capsule()
                                        .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: 0.5)
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if !activeQuery.isEmpty {
                            Button("Clear Search") {
                                viewModel.filterOptions.searchText = ""
                            }
                            .font(.caption2)
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)
                            .padding(.leading, 4)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if viewModel.allFolders.isEmpty && viewModel.isScanning {
                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Scanning folders in \(viewModel.selectedProvider?.name ?? "drive")...")
                        .font(.headline)
                    Text(viewModel.scanProgressText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 500)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if displayedFolders.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    if isSearching {
                        Text("No folders match '\(activeQuery)'")
                            .font(.headline)
                        Text("Try clearing the folder search or adjusting your status and size filters.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Button("Clear Folder Filters") {
                            viewModel.filterOptions.searchText = ""
                            viewModel.filterOptions.statusFilter = .all
                            viewModel.filterOptions.sizeFilter = .any
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Text("No folders found")
                            .font(.headline)
                        Text("Scan a cloud drive to preview folder-level disk space consumption.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
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
                    Text("\(displayedFolders.count.formatted()) matching folders (\(ByteFormatter.string(fromByteCount: matchingTotalReclaimableBytes)) reclaimable)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("\(viewModel.allFolders.count.formatted()) total folders indexed across \(viewModel.folderNodes.count) top-level directories")
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Folder icon & disclosure button if has children
                if !node.children.isEmpty {
                    Button(action: { isExpanded.toggle() }) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 14)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 14)
                }

                Image(systemName: "folder.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(node.name)
                        .font(.body)
                        .fontWeight(.semibold)

                    Text(node.relativePath)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Stats breakdown
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(ByteFormatter.string(fromByteCount: node.reclaimableBytes))
                            .fontWeight(.bold)
                            .foregroundColor(node.reclaimableBytes > 0 ? .green : .secondary)

                        Text("/ \(ByteFormatter.string(fromByteCount: node.totalCloudBytes))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text("\(node.percentageString) downloaded (\(node.downloadedFilesCount)/\(node.totalFilesCount) files)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(minWidth: 160, alignment: .trailing)

                // Visual Mini-Bar
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(nsColor: .separatorColor).opacity(0.3))
                        .frame(width: 70, height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(node.reclaimableBytes > 0 ? Color.green : Color.clear)
                        .frame(width: max(0, min(70, 70 * CGFloat(node.percentageReclaimable / 100.0))), height: 6)
                }
                .frame(width: 70)

                // Actions
                HStack(spacing: 8) {
                    // Recursive evict local copies button
                    Button(action: { viewModel.promptEvictFolder(node: node) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.to.line.compact")
                            Text("Evict Local")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .disabled(node.reclaimableBytes == 0 || viewModel.isEvicting)
                    .help("Recursively evict all downloaded files in this folder (remains in cloud)")

                    // Filter files to this folder
                    Button(action: {
                        viewModel.filterOptions.selectedFolderPrefix = node.relativePath
                        viewModel.activeTab = .files
                    }) {
                        Image(systemName: "list.bullet")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .help("View files in this folder")

                    // Reveal in Finder
                    Button(action: { viewModel.revealInFinder(url: node.url) }) {
                        Image(systemName: "folder")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Reveal in Finder")
                }
            }

            // Expanded Subfolders
            if isExpanded && !node.children.isEmpty {
                VStack(spacing: 6) {
                    ForEach(node.children) { child in
                        FolderRowView(node: child, viewModel: viewModel)
                            .padding(.leading, 24)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 6)
    }
}
