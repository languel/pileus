import SwiftUI

struct SidebarView: View {
    @ObservedObject var viewModel: AppViewModel

    private var builtInProviders: [CloudProvider] {
        viewModel.providers.filter { $0.type != .custom }
    }

    private var customProviders: [CloudProvider] {
        viewModel.providers.filter { $0.type == .custom }
    }

    var body: some View {
        List(selection: Binding(
            get: { viewModel.selectedProvider?.id },
            set: { newId in
                if let p = viewModel.providers.first(where: { $0.id == newId }) {
                    viewModel.selectProvider(p)
                }
            }
        )) {
            Section(header: Text("Cloud Services").font(.subheadline).foregroundColor(.secondary)) {
                ForEach(builtInProviders) { provider in
                    providerRow(provider)
                }
            }

            if !customProviders.isEmpty {
                Section(header: Text("Local & Custom Folders").font(.subheadline).foregroundColor(.secondary)) {
                    ForEach(customProviders) { provider in
                        providerRow(provider)
                    }
                }
            }

            Section {
                Button(action: selectCustomFolder) {
                    Label("Add Local or Cloud Folder...", systemImage: "plus.circle")
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Divider()
                HStack {
                    Button(action: { viewModel.loadProviders() }) {
                        Label("Refresh Drives", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)

                    Spacer()

                    Button(action: {
                        for p in viewModel.providers {
                            viewModel.startScan(for: p, forceRestart: false)
                        }
                    }) {
                        Text("Scan All")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
            .background(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private func providerRow(_ provider: CloudProvider) -> some View {
        let pState = viewModel.state(for: provider.id)
        HStack(spacing: 10) {
            Image(systemName: provider.type.systemIcon)
                .font(.system(size: 18))
                .foregroundColor(providerColor(provider.type))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if pState.isScanning && pState.isPaused {
                    Text("Paused (\(pState.scannedCount.formatted()) files) • \(ByteFormatter.string(fromByteCount: pState.reclaimableBytes))")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .lineLimit(1)
                } else if pState.isScanning {
                    Text("Scanning (\(pState.scannedCount.formatted()) files) • \(ByteFormatter.string(fromByteCount: pState.reclaimableBytes))")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                        .lineLimit(1)
                } else if pState.hasCompletedScan || !pState.items.isEmpty || provider.totalCloudBytes > 0 {
                    Text("\(ByteFormatter.string(fromByteCount: pState.reclaimableBytes)) local / \(ByteFormatter.string(fromByteCount: pState.totalCloudBytes))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Click to scan")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 4)

            if pState.isScanning {
                Button(action: {
                    viewModel.togglePauseScan(for: provider.id)
                }) {
                    Image(systemName: pState.isPaused ? "play.circle.fill" : "pause.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(pState.isPaused ? .green : .orange)
                }
                .buttonStyle(.plain)
                .help(pState.isPaused ? "Resume Scan" : "Pause Scan")

                if !pState.isPaused {
                    ProgressView()
                        .controlSize(.small)
                }
            } else if pState.reclaimableBytes > 0 {
                Text(ByteFormatter.string(fromByteCount: pState.reclaimableBytes))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .foregroundColor(.accentColor)
            } else if pState.hasCompletedScan {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }

            if provider.type == .custom {
                Button(action: {
                    viewModel.removeCustomProvider(provider)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary.opacity(0.75))
                }
                .buttonStyle(.plain)
                .help("Remove Custom Folder from List")
            }
        }
        .tag(provider.id)
        .padding(.vertical, 4)
        .contextMenu {
            if pState.isScanning {
                if pState.isPaused {
                    Button {
                        viewModel.resumeScan(for: provider.id)
                    } label: {
                        Label("Resume Scan", systemImage: "play.fill")
                    }
                } else {
                    Button {
                        viewModel.pauseScan(for: provider.id)
                    } label: {
                        Label("Pause Scan", systemImage: "pause.fill")
                    }
                }

                Button {
                    viewModel.cancelScan(for: provider.id)
                } label: {
                    Label("Stop Scan (Keep Results)", systemImage: "stop.fill")
                }
            } else {
                Button {
                    viewModel.startScan(for: provider, forceRestart: true)
                } label: {
                    Label("Rescan \(provider.name)", systemImage: "arrow.clockwise")
                }
            }

            Button {
                viewModel.revealInFinder(url: provider.rootURL)
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }

            if provider.type == .custom {
                Divider()
                Button(role: .destructive) {
                    viewModel.removeCustomProvider(provider)
                } label: {
                    Label("Remove from List", systemImage: "trash")
                }
            }
        }
    }

    private func providerColor(_ type: ProviderType) -> Color {
        switch type {
        case .iCloud:
            return .blue
        case .googleDrive:
            return .red
        case .oneDrive:
            return .teal
        case .dropbox:
            return .indigo
        case .custom:
            return .orange
        }
    }

    private func selectCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"
        panel.message = "Select any folder on your Mac, an external local drive, or a cloud sync directory."

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.addCustomFolder(url: url)
        }
    }
}
