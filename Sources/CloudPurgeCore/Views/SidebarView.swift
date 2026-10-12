import SwiftUI

struct SidebarView: View {
    @ObservedObject var viewModel: AppViewModel

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
                ForEach(viewModel.providers) { provider in
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

                            if provider.totalCloudBytes > 0 {
                                Text("\(ByteFormatter.string(fromByteCount: provider.reclaimableBytes)) local / \(ByteFormatter.string(fromByteCount: provider.totalCloudBytes))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Ready to scan")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        if viewModel.selectedProvider?.id == provider.id && viewModel.isScanning {
                            ProgressView()
                                .controlSize(.small)
                        } else if provider.reclaimableBytes > 0 {
                            Text(ByteFormatter.string(fromByteCount: provider.reclaimableBytes))
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                .foregroundColor(.accentColor)
                        }
                    }
                    .tag(provider.id)
                    .padding(.vertical, 4)
                }
            }

            Section {
                Button(action: selectCustomFolder) {
                    Label("Add Custom Folder...", systemImage: "plus.circle")
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

                    Text("CloudPurge")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
            .background(.ultraThinMaterial)
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
        panel.prompt = "Choose Cloud Folder"
        panel.message = "Select a folder inside iCloud Drive, Google Drive, or any cloud sync directory."

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.addCustomFolder(url: url)
        }
    }
}
