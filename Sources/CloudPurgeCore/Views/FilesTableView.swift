import SwiftUI

struct FilesTableView: View {
    @ObservedObject var viewModel: AppViewModel

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Optional active folder filter banner
            if let folderPrefix = viewModel.filterOptions.selectedFolderPrefix, !folderPrefix.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.accentColor)
                    Text("Filtered to folder:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(folderPrefix)
                        .font(.caption)
                        .fontWeight(.semibold)
                    Spacer()
                    Button("Clear Folder Filter") {
                        viewModel.filterOptions.selectedFolderPrefix = nil
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.08))
                Divider()
            }

            if viewModel.allItems.isEmpty && viewModel.isScanning {
                VStack(spacing: 14) {
                    if viewModel.isPaused {
                        Image(systemName: "pause.circle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.orange)
                        Text("Scan Paused (\(viewModel.selectedProvider?.name ?? "cloud files"))")
                            .font(.headline)
                    } else {
                        ProgressView()
                            .controlSize(.regular)
                        Text("Scanning \(viewModel.selectedProvider?.name ?? "cloud files")...")
                            .font(.headline)
                    }
                    Text(viewModel.scanProgressText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 500)

                    HStack(spacing: 10) {
                        Button(viewModel.isPaused ? "Resume Scan" : "Pause Scan") {
                            viewModel.togglePauseScan()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(viewModel.isPaused ? .green : .orange)
                        .controlSize(.small)

                        Button("Stop Scan") {
                            viewModel.cancelScan()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.displayedItems.isEmpty && viewModel.isFiltering {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Loading files for \(viewModel.selectedProvider?.name ?? "source")...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.displayedItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No files match the active filters")
                        .font(.headline)
                    Text("Try clearing search or adjusting your status, size, and age filters.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button("Reset All Filters") {
                        viewModel.filterOptions = FilterOptions()
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(viewModel.displayedItems, selection: $viewModel.selectedItemIds) {
                    TableColumn("Name") { item in
                        HStack(spacing: 8) {
                            Image(systemName: item.kind.icon)
                                .foregroundColor(.secondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                Text(item.relativePath)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .width(min: 220, ideal: 300)

                    TableColumn("Local Disk") { item in
                        HStack(spacing: 4) {
                            if item.isReclaimable {
                                Text(ByteFormatter.string(fromByteCount: item.allocatedSize))
                                    .fontWeight(.bold)
                                    .foregroundColor(.green)
                            } else {
                                Text("0 B")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .width(min: 90, ideal: 110)

                    TableColumn("Cloud Size") { item in
                        Text(ByteFormatter.string(fromByteCount: item.fileSize))
                            .foregroundColor(.secondary)
                    }
                    .width(min: 80, ideal: 100)

                    TableColumn("Status") { item in
                        StatusBadge(status: item.syncStatus)
                    }
                    .width(min: 130, ideal: 150)

                    TableColumn("Modified") { item in
                        Text(formattedDate(item.modificationDate))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .width(min: 110, ideal: 130)

                    TableColumn("Actions") { item in
                        HStack(spacing: 8) {
                            if item.isReclaimable {
                                Button(action: { viewModel.evictSingle(item: item) }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "xmark.bin")
                                        Text("Remove")
                                    }
                                    .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                                .help("Remove local download to free disk space")
                            } else if item.syncStatus == .cloudOnly {
                                Button(action: { viewModel.downloadItem(item: item) }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.down.circle")
                                        Text("Download")
                                    }
                                    .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .help("Download file from cloud")
                            }

                            Button(action: { viewModel.revealInFinder(url: item.url) }) {
                                Image(systemName: "folder")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .help("Reveal in Finder")
                        }
                    }
                    .width(min: 140, ideal: 160)
                }
                .contextMenu(forSelectionType: UUID.self) { selectedIds in
                    let selectedItems = viewModel.displayedItems.filter { selectedIds.contains($0.id) }
                    let reclaimable = selectedItems.filter { $0.isReclaimable }

                    if !reclaimable.isEmpty {
                        Button("Remove Downloads (\(reclaimable.count) files)") {
                            viewModel.promptEvictSelection()
                        }
                    }

                    if selectedItems.count == 1, let single = selectedItems.first {
                        if single.syncStatus == .cloudOnly {
                            Button("Download Now") {
                                viewModel.downloadItem(item: single)
                            }
                        }
                        Button("Reveal in Finder") {
                            viewModel.revealInFinder(url: single.url)
                        }
                        Button("Copy File Path") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(single.path, forType: .string)
                        }
                    }
                }
            }

            // Table Footer summary
            HStack(spacing: 10) {
                if viewModel.totalMatchingCount > viewModel.displayedItems.count {
                    Text("Showing top \(viewModel.displayedItems.count.formatted()) of \(viewModel.totalMatchingCount.formatted()) matching files")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button("Load More (+1,000)") {
                        viewModel.loadMoreItems()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                } else {
                    Text("\(viewModel.totalMatchingCount.formatted()) of \(viewModel.allItems.count.formatted()) files shown")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if !viewModel.selectedItemIds.isEmpty {
                    Text("•  \(viewModel.selectedItemIds.count) selected")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }

                Spacer()

                if viewModel.isScanning {
                    HStack(spacing: 8) {
                        if viewModel.isPaused {
                            Image(systemName: "pause.circle.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(viewModel.scanProgressText)
                            .font(.caption2)
                            .foregroundColor(viewModel.isPaused ? .orange : .secondary)
                            .lineLimit(1)

                        Button(viewModel.isPaused ? "Resume" : "Pause") {
                            viewModel.togglePauseScan()
                        }
                        .font(.caption2)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                } else {
                    Text(viewModel.scanProgressText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date = date else { return "--" }
        return Self.dateFormatter.string(from: date)
    }
}

struct StatusBadge: View {
    let status: SyncStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.iconName)
                .font(.caption2)
            Text(status.rawValue)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(color(for: status).opacity(0.12))
        )
        .foregroundColor(color(for: status))
    }

    private func color(for status: SyncStatus) -> Color {
        switch status {
        case .downloaded: return .green
        case .cloudOnly: return .blue
        case .uploading, .downloading: return .orange
        case .conflict, .unsynced: return .red
        }
    }
}
