import SwiftUI

struct FolderAnalyzerView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var folderSortOption: FolderSortField = .reclaimableBytes

    enum FolderSortField: String, CaseIterable, Identifiable {
        case reclaimableBytes = "Most Reclaimable Space"
        case percentage = "Highest % Downloaded"
        case totalSize = "Largest Cloud Size"
        case name = "Folder Name"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar for Folder Analyzer
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Folder Space Breakdown")
                        .font(.headline)
                    Text("Identify which directories consume the most local disk space and recursively remove downloads.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Picker("Sort by:", selection: $folderSortOption) {
                    ForEach(FolderSortField.allCases) { opt in
                        Text(opt.rawValue).tag(opt)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 220)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if viewModel.folderNodes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No folders found")
                        .font(.headline)
                    Text("Scan a cloud drive to preview folder-level disk space consumption.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(sortedFolders(viewModel.folderNodes)) { node in
                        FolderRowView(node: node, viewModel: viewModel)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }

    private func sortedFolders(_ nodes: [CloudFolderNode]) -> [CloudFolderNode] {
        return nodes.sorted { lhs, rhs in
            switch folderSortOption {
            case .reclaimableBytes:
                return lhs.reclaimableBytes > rhs.reclaimableBytes
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
                    // Recursive remove downloads button
                    Button(action: { viewModel.promptEvictFolder(node: node) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.bin")
                            Text("Remove Downloads")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(node.reclaimableBytes == 0 || viewModel.isEvicting)
                    .help("Recursively evict all downloaded files in this folder")

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
