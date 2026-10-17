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
                        }
                    }
                }
                .frame(minWidth: 800, minHeight: 550)

                // Eviction in progress overlay
                if viewModel.isEvicting {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        ProgressView(
                            value: Double(viewModel.evictionProgressCurrent),
                            total: Double(max(1, viewModel.evictionProgressTotal))
                        ) {
                            Text("Evicting Downloads...")
                                .font(.headline)
                        }
                        .progressViewStyle(.linear)
                        .frame(width: 320)

                        Text(viewModel.evictionProgressText)
                            .font(.caption)
                            .foregroundColor(.secondary)
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
        .alert("Eviction Report", isPresented: $viewModel.showReportAlert) {
            Button("Done", role: .cancel) {}
        } message: {
            if let report = viewModel.lastReport {
                Text("Successfully evicted \(report.successfullyEvicted) files.\nReclaimed \(ByteFormatter.string(fromByteCount: report.bytesReclaimed)) of disk space on your Mac.\nFiles remain safely preserved in cloud storage.")
            } else {
                Text("Eviction finished.")
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
