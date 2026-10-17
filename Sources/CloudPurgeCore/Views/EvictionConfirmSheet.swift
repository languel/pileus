import SwiftUI

struct EvictionConfirmSheet: View {
    @ObservedObject var viewModel: AppViewModel

    var isPermanentDelete: Bool {
        viewModel.pendingActionMode == .deleteEverywhere
    }

    var totalBytesToReclaim: Int64 {
        viewModel.pendingEvictionItems.reduce(0) { $0 + $1.allocatedSize }
    }

    var totalCloudBytesAffected: Int64 {
        viewModel.pendingEvictionItems.reduce(0) { $0 + $1.fileSize }
    }

    var body: some View {
        VStack(spacing: 18) {
            // Mode Switcher (Evict Local Only vs Delete from Mac & Cloud)
            Picker("", selection: $viewModel.pendingActionMode) {
                Text("Evict Local Copy (Safe)").tag(PurgeActionMode.evictLocalOnly)
                Text("Delete from Mac & Cloud").tag(PurgeActionMode.deleteEverywhere)
            }
            .pickerStyle(.segmented)
            .frame(width: 400)

            // Header
            VStack(spacing: 8) {
                Image(systemName: isPermanentDelete ? "exclamationmark.triangle.fill" : "arrow.up.to.line.circle.fill")
                    .font(.system(size: 42))
                    .foregroundColor(isPermanentDelete ? .red : .orange)

                Text(viewModel.pendingEvictionTitle)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(viewModel.pendingEvictionDescription)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }

            // Explicit Warning Banner when Permanent Cloud Deletion is selected
            if isPermanentDelete {
                HStack(spacing: 10) {
                    Image(systemName: "trash.slash.fill")
                        .font(.title3)
                        .foregroundColor(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Permanent Cloud & Local Deletion")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                        Text("These files/folders will be deleted from your Mac AND removed from iCloud Drive / Google Drive across all synced devices.")
                            .font(.caption2)
                            .foregroundColor(.primary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.red.opacity(0.4), lineWidth: 1)
                        )
                )
                .frame(maxWidth: 480)
            }

            // Highlight Box
            HStack(spacing: 24) {
                VStack(spacing: 2) {
                    Text("Local Disk Freed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(ByteFormatter.string(fromByteCount: totalBytesToReclaim))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                }

                Divider()
                    .frame(height: 36)

                VStack(spacing: 2) {
                    Text(isPermanentDelete ? "Files to Delete" : "Files to Evict")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(viewModel.pendingEvictionItems.count.formatted())
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }

                Divider()
                    .frame(height: 36)

                VStack(spacing: 2) {
                    Text("Cloud Status")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if isPermanentDelete {
                        Text("-\(ByteFormatter.string(fromByteCount: totalCloudBytesAffected)) Deleted")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                    } else {
                        Text("100% Preserved")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )

            // Preview of items
            VStack(alignment: .leading, spacing: 6) {
                if !viewModel.pendingEvictionFolderURLs.isEmpty {
                    Text("Target folders (\(viewModel.pendingEvictionFolderURLs.count)):")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Target files (first \(min(50, viewModel.pendingEvictionItems.count))):")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if !viewModel.pendingEvictionFolderURLs.isEmpty {
                            ForEach(viewModel.pendingEvictionFolderURLs.prefix(50), id: \.path) { folderURL in
                                HStack {
                                    Image(systemName: "folder.fill")
                                        .font(.caption)
                                        .foregroundColor(isPermanentDelete ? .red : .accentColor)
                                    Text(folderURL.path)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: .textBackgroundColor).opacity(0.5)))
                            }
                        } else {
                            ForEach(viewModel.pendingEvictionItems.prefix(50)) { item in
                                HStack {
                                    Image(systemName: item.kind.icon)
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Text(item.name)
                                        .font(.caption)
                                        .lineLimit(1)

                                    Spacer()

                                    Text(ByteFormatter.string(fromByteCount: isPermanentDelete ? item.fileSize : item.allocatedSize))
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(isPermanentDelete ? .red : .green)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: .textBackgroundColor).opacity(0.5)))
                            }
                        }
                    }
                    .padding(4)
                }
                .frame(maxHeight: 150)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
            }
            .frame(maxWidth: 480)

            // Bottom Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    viewModel.showConfirmationSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button(action: {
                    viewModel.executeConfirmedEviction()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: isPermanentDelete ? "trash.fill" : "arrow.up.to.line.compact")
                        Text(isPermanentDelete ? "Delete from Mac & Cloud" : "Evict Local Copies")
                    }
                    .fontWeight(.semibold)
                    .frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
                .tint(isPermanentDelete ? .red : .orange)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 560)
    }
}
