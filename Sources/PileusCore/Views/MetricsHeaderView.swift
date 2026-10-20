import SwiftUI

struct MetricsHeaderView: View {
    @ObservedObject var viewModel: AppViewModel

    private var isLocalOnly: Bool {
        viewModel.isActiveProviderLocalOnly
    }

    var body: some View {
        HStack(spacing: 14) {
            if isLocalOnly {
                // Local Folder Metrics
                MetricCard(
                    title: "Disk Space Used",
                    value: ByteFormatter.string(fromByteCount: viewModel.totalReclaimableBytes),
                    subtitle: "\(viewModel.scannedCount.formatted()) local files",
                    systemImage: "internaldrive",
                    tintColor: .teal.opacity(0.85)
                )
                .help("Physical disk space allocated by files in this local folder.")

                MetricCard(
                    title: "Logical Size",
                    value: ByteFormatter.string(fromByteCount: viewModel.totalCloudBytes),
                    subtitle: "\(viewModel.allFolders.count.formatted()) subfolders indexed",
                    systemImage: "folder",
                    tintColor: .secondary
                )
                .help("Total logical byte size across all files in this folder.")

                // Card 3: Local Scan Options / Filter Summary
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Local Folder Mode")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .help("This folder is stored locally on disk (not inside a cloud sync provider). Use Folder Space Analyzer to clean heavy build/dependency directories, or Duplicate Finder to link duplicate files.")
                    }

                    Toggle("Exclude Cloud Mounts & Stubs", isOn: $viewModel.excludeCloudFilesInLocalScans)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .help("Skip iCloud Drive, Google Drive, OneDrive, Dropbox, and cloud placeholder files if they exist inside this local folder.")

                    Text("Matching filter: \(viewModel.totalMatchingCount.formatted()) files (\(ByteFormatter.string(fromByteCount: viewModel.matchingReclaimableBytes)))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.5)
                        )
                )
            } else {
                // Cloud Provider Metrics
                MetricCard(
                    title: "Reclaimable Disk Space",
                    value: ByteFormatter.string(fromByteCount: viewModel.totalReclaimableBytes),
                    subtitle: "\(viewModel.totalDownloadedCount.formatted()) files downloaded locally",
                    systemImage: "arrow.down.to.line.compact",
                    tintColor: .teal.opacity(0.85)
                )
                .help("Local disk space on your Mac that can be safely freed by evicting downloaded copies back to the cloud.")

                MetricCard(
                    title: "Cloud Total",
                    value: ByteFormatter.string(fromByteCount: viewModel.totalCloudBytes),
                    subtitle: "\(viewModel.scannedCount.formatted()) files in cloud index",
                    systemImage: "icloud",
                    tintColor: .blue.opacity(0.8)
                )
                .help("Total logical size of all files in this cloud drive (both downloaded and cloud-only).")

                // Card 3: Storage Breakdown & Gauge
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Downloaded Locally")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.1f%%", viewModel.reclaimablePercentage))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(nsColor: .separatorColor).opacity(0.35))
                                .frame(height: 7)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.teal.opacity(0.75))
                                .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(viewModel.reclaimablePercentage / 100.0))), height: 7)
                        }
                    }
                    .frame(height: 7)

                    HStack {
                        Text("\(ByteFormatter.string(fromByteCount: viewModel.totalReclaimableBytes)) on Mac")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(ByteFormatter.string(fromByteCount: max(0, viewModel.totalCloudBytes - viewModel.totalReclaimableBytes))) cloud-only")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.5)
                        )
                )
            }

            // Card 4: Action Button
            VStack(spacing: 8) {
                if isLocalOnly {
                    if !viewModel.selectedItemIds.isEmpty {
                        Button(action: { viewModel.promptDeleteSelection() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                Text("Delete (\(viewModel.selectedItemIds.count))")
                                    .fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red.opacity(0.85))
                        .help("Permanently delete the selected local files from disk")
                    } else {
                        Button(action: {
                            viewModel.activeTab = .duplicates
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.on.doc")
                                Text("Find Duplicates")
                                    .fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                        .help("Switch to Duplicate Finder to locate and link duplicate files in this folder")
                    }
                } else {
                    if !viewModel.selectedItemIds.isEmpty {
                        Button(action: { viewModel.promptEvictSelection() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.to.line.compact")
                                Text("Evict (\(viewModel.selectedItemIds.count))")
                                    .fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.teal)
                        .help("Unload selected local copies to free Mac space while keeping them in the cloud")
                    } else {
                        Button(action: { viewModel.promptEvictAllFiltered() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.to.line.compact")
                                Text("Evict All Local")
                                    .fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.teal)
                        .disabled(viewModel.matchingReclaimableBytes == 0 || viewModel.isEvicting || (viewModel.isScanning && !viewModel.isPaused))
                        .help("Unload all downloaded files matching current filters (files remain in the cloud)")
                    }
                }

                if viewModel.isScanning {
                    HStack(spacing: 12) {
                        Button(action: { viewModel.togglePauseScan() }) {
                            HStack(spacing: 4) {
                                Image(systemName: viewModel.isPaused ? "play.circle.fill" : "pause.circle.fill")
                                Text(viewModel.isPaused ? "Resume" : "Pause")
                            }
                            .font(.caption)
                            .foregroundColor(viewModel.isPaused ? .teal : .orange)
                        }
                        .buttonStyle(.plain)
                        .help(viewModel.isPaused ? "Resume scanning where it left off" : "Pause scan without losing progress")

                        Button(action: { viewModel.cancelScan() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "stop.circle")
                                Text("Stop")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Stop scanning and keep files discovered so far")
                    }
                } else {
                    Button(action: { viewModel.startScan(forceRestart: true) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Rescan")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Rescan current folder or drive")
                }
            }
            .frame(width: 165)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String
    let tintColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 19))
                .foregroundColor(tintColor)
                .frame(width: 26, height: 26)
                .padding(5)
                .background(Circle().fill(tintColor.opacity(0.10)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(12)
        .frame(minWidth: 165)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.5)
                )
        )
    }
}
