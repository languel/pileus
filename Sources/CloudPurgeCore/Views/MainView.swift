import SwiftUI

public struct MainView: View {
    @StateObject private var viewModel = AppViewModel()

    public init() {}

    public var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            ZStack {
                VStack(spacing: 0) {
                    MetricsHeaderView(viewModel: viewModel)

                    Divider()

                    FilterBarView(viewModel: viewModel)

                    Divider()

                    Group {
                        switch viewModel.activeTab {
                        case .files:
                            FilesTableView(viewModel: viewModel)
                        case .folders:
                            FolderAnalyzerView(viewModel: viewModel)
                        case .duplicates:
                            DuplicateFinderView(viewModel: viewModel)
                        }
                    }
                }
                .frame(minWidth: 800, minHeight: 550)

                // Eviction in progress overlay
                if viewModel.isEvicting {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()

                    VStack(spacing: 14) {
                        ProgressView(
                            value: Double(viewModel.evictionProgressCurrent),
                            total: Double(max(1, viewModel.evictionProgressTotal))
                        ) {
                            Text(viewModel.isEvictionPaused ? "Operation Paused" : "Processing Files...")
                                .font(.headline)
                        }
                        .progressViewStyle(.linear)
                        .frame(width: 340)

                        Text(viewModel.evictionProgressText)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("Safe to pause or stop anytime — each file is processed atomically.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(width: 340)

                        HStack(spacing: 12) {
                            Button(action: { viewModel.togglePauseEviction() }) {
                                Label(
                                    viewModel.isEvictionPaused ? "Resume" : "Pause",
                                    systemImage: viewModel.isEvictionPaused ? "play.fill" : "pause.fill"
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(viewModel.isEvictionPaused ? .green : .orange)
                            .controlSize(.small)

                            Button(action: { viewModel.stopEviction() }) {
                                Label("Stop Safely (Keep Progress)", systemImage: "stop.fill")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.top, 2)
                    }
                    .padding(28)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(nsColor: .windowBackgroundColor))
                            .shadow(radius: 12)
                    )
                }
            }
        }
        .sheet(isPresented: $viewModel.showConfirmationSheet) {
            EvictionConfirmSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showDuplicateResolveSheet) {
            DuplicateResolveSheet(viewModel: viewModel)
        }
        .alert(viewModel.lastReport?.actionMode == .deleteEverywhere ? "Deletion Report" : "Eviction Report", isPresented: $viewModel.showReportAlert) {
            Button("Done", role: .cancel) {}
        } message: {
            if let report = viewModel.lastReport {
                if report.actionMode == .deleteEverywhere {
                    Text("Permanently deleted \(report.successfullyEvicted.formatted()) files from your Mac and cloud storage.\nFreed \(ByteFormatter.string(fromByteCount: report.bytesReclaimed)) on your Mac and \(ByteFormatter.string(fromByteCount: report.cloudBytesDeleted)) in the cloud.")
                } else if report.wasCancelled {
                    Text("Stopped safely after evicting \(report.successfullyEvicted.formatted()) of \(report.totalRequested.formatted()) files.\nReclaimed \(ByteFormatter.string(fromByteCount: report.bytesReclaimed)) of local disk space.\nAll files remain safely preserved in cloud storage.")
                } else {
                    Text("Successfully evicted \(report.successfullyEvicted.formatted()) local copies.\nReclaimed \(ByteFormatter.string(fromByteCount: report.bytesReclaimed)) of disk space on your Mac.\nFiles remain safely preserved in cloud storage.")
                }
            } else {
                Text("Operation finished.")
            }
        }
        .alert("Duplicate Resolution Report", isPresented: $viewModel.showDuplicateReportAlert) {
            Button("Done", role: .cancel) {}
        } message: {
            if let rep = viewModel.lastDuplicateReport {
                let failNote = rep.failedItems.isEmpty ? "" : "\nSkipped/Failed: \(rep.failedItems.count) (\(rep.failedItems.first?.reason ?? ""))"
                Text("Resolved \(rep.groupsResolved.formatted()) duplicate groups using \(rep.strategy.shortTitle).\nReplaced \(rep.duplicatesReplaced.formatted()) duplicate copies and reclaimed \(ByteFormatter.string(fromByteCount: rep.localBytesReclaimed)) of local disk space.\(failNote)")
            } else {
                Text("Duplicate resolution complete.")
            }
        }
        .alert("Notice", isPresented: $viewModel.showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "An error occurred.")
        }
        .navigationTitle(viewModel.selectedProvider?.name ?? "CloudPurge")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if viewModel.isScanning {
                    Button(action: { viewModel.togglePauseScan() }) {
                        Label(
                            viewModel.isPaused ? "Resume Scan" : "Pause Scan",
                            systemImage: viewModel.isPaused ? "play.fill" : "pause.fill"
                        )
                    }
                    .help(viewModel.isPaused ? "Resume scanning where it left off" : "Pause scan without losing progress")
                }

                Button(action: { viewModel.startScan(forceRestart: true) }) {
                    Label("Scan Drive", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isScanning && !viewModel.isPaused)
                .help("Rescan current source")
            }
        }
    }
}
