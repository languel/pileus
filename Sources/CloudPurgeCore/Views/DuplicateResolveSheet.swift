import SwiftUI
import AppKit

struct DuplicateResolveSheet: View {
    @ObservedObject var viewModel: AppViewModel

    private var totalDuplicatesToReplace: Int {
        viewModel.pendingDuplicateGroups.reduce(0) { $0 + $1.duplicateItems.count }
    }

    private var totalLocalBytesFreed: Int64 {
        viewModel.pendingDuplicateGroups.reduce(0) { $0 + $1.reclaimableLocalBytes }
    }

    private var totalCloudBytesFreed: Int64 {
        viewModel.pendingDuplicateGroups.reduce(0) { $0 + $1.redundantLogicalBytes }
    }

    private var warnings: [DuplicatePlatformWarning] {
        viewModel.currentDuplicateWarnings()
    }

    var body: some View {
        VStack(spacing: 14) {
            // Header
            VStack(spacing: 4) {
                Image(systemName: viewModel.selectedResolutionStrategy.icon)
                    .font(.system(size: 30))
                    .foregroundColor(viewModel.selectedResolutionStrategy == .trashDuplicates ? .red : .teal)

                Text("Resolve Duplicate Files")
                    .font(.title3)
                    .fontWeight(.bold)

                Text("Keep 1 Primary file per group and replace \(totalDuplicatesToReplace.formatted()) duplicate \(totalDuplicatesToReplace == 1 ? "copy" : "copies") across \(viewModel.pendingDuplicateGroups.count) \(viewModel.pendingDuplicateGroups.count == 1 ? "group" : "groups").")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Primary Relocation Option ("Move Primary to a new folder of choice and link everything from there")
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Toggle("Move Primary file(s) to a canonical folder and link all locations to it", isOn: $viewModel.relocatePrimaryToCustomFolder)
                        .toggleStyle(.checkbox)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .help("Moves the Primary copy into your chosen folder and places links at both the Primary's original path and all duplicate paths.")
                }

                if viewModel.relocatePrimaryToCustomFolder {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.teal)

                        if let destURL = viewModel.relocatedPrimaryDirectoryURL {
                            Text(destURL.path)
                                .font(.caption)
                                .fontWeight(.medium)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(destURL.path)
                        } else {
                            Text("Select a destination folder...")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }

                        Spacer()

                        Button(action: selectCanonicalDestinationFolder) {
                            Label(viewModel.relocatedPrimaryDirectoryURL == nil ? "Choose Folder..." : "Change Folder...", systemImage: "folder.badge.plus")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.08))
                    )
                }
            }
            .padding(10)
            .frame(maxWidth: 560, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
                    )
            )

            // Strategy Picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Resolution Method:")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                ForEach(DuplicateResolutionStrategy.allCases) { strategy in
                    let isSelected = (viewModel.selectedResolutionStrategy == strategy)
                    Button(action: {
                        viewModel.selectedResolutionStrategy = strategy
                    }) {
                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                .foregroundColor(isSelected ? .teal : .secondary)

                            Image(systemName: strategy.icon)
                                .foregroundColor(strategy == .trashDuplicates ? .red : .secondary)
                                .frame(width: 18)

                            Text(strategy.rawValue)
                                .font(.subheadline)
                                .fontWeight(isSelected ? .semibold : .regular)
                                .foregroundColor(.primary)

                            Spacer()

                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .help(strategy.summaryDescription)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(isSelected ? Color.teal.opacity(0.10) : Color(nsColor: .controlBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .stroke(isSelected ? Color.teal.opacity(0.55) : Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .help(strategy.summaryDescription)
                }

                if viewModel.selectedResolutionStrategy == .symlink {
                    Toggle("Use relative symlink paths (e.g. `../shared/file`) when possible", isOn: $viewModel.useRelativeSymlinks)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                        .padding(.top, 2)
                        .help("Relative symlinks remain valid if the parent folder is moved intact.")
                }
            }
            .frame(maxWidth: 560)

            // Platform & Cloud Compatibility Warnings
            if !warnings.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(warnings) { warning in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: warningIcon(warning.severity))
                                .foregroundColor(warningColor(warning.severity))
                                .font(.subheadline)
                                .padding(.top, 1)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(warning.title)
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(warningColor(warning.severity))

                                Text(warning.message)
                                    .font(.caption2)
                                    .foregroundColor(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(warningColor(warning.severity).opacity(0.10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(warningColor(warning.severity).opacity(0.35), lineWidth: 1)
                                )
                        )
                    }
                }
                .frame(maxWidth: 560)
            }

            // Metrics Summary Box
            HStack(spacing: 22) {
                VStack(spacing: 2) {
                    Text("Disk Space Saved")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(ByteFormatter.string(fromByteCount: totalLocalBytesFreed))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.teal)
                }

                Divider().frame(height: 28)

                VStack(spacing: 2) {
                    Text("Logical Size Saved")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(ByteFormatter.string(fromByteCount: totalCloudBytesFreed))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }

                Divider().frame(height: 28)

                VStack(spacing: 2) {
                    Text("Duplicates Replaced")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(totalDuplicatesToReplace.formatted())")
                        .font(.title3)
                        .fontWeight(.bold)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )

            // Preview of Primary <- Duplicate mappings
            VStack(alignment: .leading, spacing: 4) {
                Text("Link Preview (first \(min(25, viewModel.pendingDuplicateGroups.count)) groups):")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.pendingDuplicateGroups.prefix(25)) { group in
                            if let primary = group.primaryItem {
                                VStack(alignment: .leading, spacing: 3) {
                                    if viewModel.relocatePrimaryToCustomFolder, let destDir = viewModel.relocatedPrimaryDirectoryURL {
                                        HStack(spacing: 5) {
                                            Image(systemName: "folder.fill.badge.plus")
                                                .foregroundColor(.teal)
                                                .font(.caption2)
                                            Text("NEW PRIMARY:")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(.teal)
                                            Text(destDir.appendingPathComponent(primary.name).path)
                                                .font(.caption)
                                                .fontWeight(.medium)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }

                                        HStack(spacing: 5) {
                                            Image(systemName: "arrow.turn.down.right")
                                                .foregroundColor(.secondary)
                                                .font(.caption2)
                                            Text("LINK AT OLD PRIMARY:")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundColor(.secondary)
                                            Text("[\(viewModel.providerName(for: primary.providerId))] \(primary.relativePath)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                        .padding(.leading, 14)
                                    } else {
                                        HStack(spacing: 5) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.teal)
                                                .font(.caption2)
                                            Text("PRIMARY:")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(.teal)
                                            Text("[\(viewModel.providerName(for: primary.providerId))] \(primary.relativePath)")
                                                .font(.caption)
                                                .fontWeight(.medium)
                                                .lineLimit(1)
                                        }
                                    }

                                    ForEach(group.duplicateItems) { dup in
                                        HStack(spacing: 5) {
                                            Image(systemName: "arrow.turn.down.right")
                                                .foregroundColor(.secondary)
                                                .font(.caption2)
                                            Text(viewModel.selectedResolutionStrategy.shortTitle.uppercased() + ":")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundColor(.secondary)
                                            Text("[\(viewModel.providerName(for: dup.providerId))] \(dup.relativePath)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                        .padding(.leading, 14)
                                    }
                                }
                                .padding(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor).opacity(0.6)))
                            }
                        }
                    }
                    .padding(4)
                }
                .frame(maxHeight: 110)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
            }
            .frame(maxWidth: 560)

            // Action Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    viewModel.showDuplicateResolveSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button(action: {
                    viewModel.executeConfirmedDuplicateResolution()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: viewModel.selectedResolutionStrategy.icon)
                        Text(viewModel.relocatePrimaryToCustomFolder
                            ? "Move Primary & Link All (\(totalDuplicatesToReplace + viewModel.pendingDuplicateGroups.count) Locations)"
                            : "Replace \(totalDuplicatesToReplace) \(totalDuplicatesToReplace == 1 ? "Duplicate" : "Duplicates") with \(viewModel.selectedResolutionStrategy.shortTitle)")
                    }
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.selectedResolutionStrategy == .trashDuplicates ? .red : .teal)
                .disabled(viewModel.relocatePrimaryToCustomFolder && viewModel.relocatedPrimaryDirectoryURL == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 620)
    }

    private func selectCanonicalDestinationFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Canonical Folder"
        panel.message = "Choose a folder where Primary files will be moved (all original locations will be linked to it)."

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.relocatedPrimaryDirectoryURL = url
        }
    }

    private func warningIcon(_ severity: DuplicatePlatformWarning.Severity) -> String {
        switch severity {
        case .info: return "info.circle.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .danger: return "exclamationmark.octagon.fill"
        }
    }

    private func warningColor(_ severity: DuplicatePlatformWarning.Severity) -> Color {
        switch severity {
        case .info: return .teal
        case .caution: return .orange
        case .danger: return .red
        }
    }
}
