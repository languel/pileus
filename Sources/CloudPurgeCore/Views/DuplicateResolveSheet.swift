import SwiftUI

struct DuplicateResolveSheet: View {
    @ObservedObject var viewModel: AppViewModel

    private var totalDuplicatesToReplace: Int {
        viewModel.pendingDuplicateGroups.reduce(0) { $0 + $1.duplicateItems.count }
    }

    private var totalLocalBytesFreed: Int64 {
        viewModel.pendingDuplicateGroups.reduce(0) { $0 + $1.reclaimableLocalBytes }
    }

    private var warnings: [DuplicatePlatformWarning] {
        viewModel.currentDuplicateWarnings()
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            VStack(spacing: 6) {
                Image(systemName: viewModel.selectedResolutionStrategy.icon)
                    .font(.system(size: 38))
                    .foregroundColor(viewModel.selectedResolutionStrategy == .trashDuplicates ? .red : .purple)

                Text("Resolve Duplicate Files")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Keep your chosen Primary file in each group and replace \(totalDuplicatesToReplace.formatted()) duplicate \(totalDuplicatesToReplace == 1 ? "copy" : "copies") across \(viewModel.pendingDuplicateGroups.count) \(viewModel.pendingDuplicateGroups.count == 1 ? "group" : "groups").")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
            }

            // Strategy Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Link / Resolution Method:")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                ForEach(DuplicateResolutionStrategy.allCases) { strategy in
                    let isSelected = (viewModel.selectedResolutionStrategy == strategy)
                    Button(action: {
                        viewModel.selectedResolutionStrategy = strategy
                    }) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                .foregroundColor(isSelected ? .purple : .secondary)
                                .padding(.top, 2)

                            Image(systemName: strategy.icon)
                                .foregroundColor(strategy == .trashDuplicates ? .red : .purple)
                                .frame(width: 18)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(strategy.rawValue)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)

                                Text(strategy.summaryDescription)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isSelected ? Color.purple.opacity(0.10) : Color(nsColor: .controlBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isSelected ? Color.purple.opacity(0.55) : Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }

                if viewModel.selectedResolutionStrategy == .symlink {
                    Toggle("Use relative symlink paths (e.g. `../shared/file`) when Primary and Duplicate are in the same source", isOn: $viewModel.useRelativeSymlinks)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: 540)

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
                        .padding(9)
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
                .frame(maxWidth: 540)
            }

            // Metrics Summary Box
            HStack(spacing: 24) {
                VStack(spacing: 2) {
                    Text("Local Space Freed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(ByteFormatter.string(fromByteCount: totalLocalBytesFreed))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                }

                Divider().frame(height: 32)

                VStack(spacing: 2) {
                    Text("Duplicates Replaced")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(totalDuplicatesToReplace.formatted())")
                        .font(.title3)
                        .fontWeight(.bold)
                }

                Divider().frame(height: 32)

                VStack(spacing: 2) {
                    Text("Primary Copies Kept")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(viewModel.pendingDuplicateGroups.count.formatted()) (100% Intact)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
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
                                    HStack(spacing: 5) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.caption2)
                                        Text("PRIMARY:")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.green)
                                        Text("[\(viewModel.providerName(for: primary.providerId))] \(primary.relativePath)")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .lineLimit(1)
                                    }

                                    ForEach(group.duplicateItems) { dup in
                                        HStack(spacing: 5) {
                                            Image(systemName: "arrow.turn.down.right")
                                                .foregroundColor(.purple)
                                                .font(.caption2)
                                            Text(viewModel.selectedResolutionStrategy.shortTitle.uppercased() + ":")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(.purple)
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
                .frame(maxHeight: 120)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
            }
            .frame(maxWidth: 540)

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
                        Text("Replace \(totalDuplicatesToReplace) \(totalDuplicatesToReplace == 1 ? "Duplicate" : "Duplicates") with \(viewModel.selectedResolutionStrategy.shortTitle)")
                    }
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.selectedResolutionStrategy == .trashDuplicates ? .red : .purple)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 600)
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
        case .info: return .blue
        case .caution: return .orange
        case .danger: return .red
        }
    }
}
