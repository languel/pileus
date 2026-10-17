import SwiftUI

struct DuplicateFinderView: View {
    @ObservedObject var viewModel: AppViewModel

    private let minSizeOptions: [(label: String, bytes: Int64)] = [
        ("≥ 1 KB", 1024),
        ("≥ 10 KB", 10 * 1024),
        ("≥ 100 KB", 100 * 1024),
        ("≥ 1 MB", 1024 * 1024),
        ("≥ 10 MB", 10 * 1024 * 1024),
        ("≥ 50 MB", 50 * 1024 * 1024)
    ]

    private var filteredDuplicateGroups: [DuplicateGroup] {
        let query = viewModel.filterOptions.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return viewModel.duplicateGroups }
        return viewModel.duplicateGroups.filter { group in
            group.items.contains {
                $0.name.localizedCaseInsensitiveContains(query) ||
                $0.relativePath.localizedCaseInsensitiveContains(query)
            }
        }
    }

    private var totalRedundantLocalBytes: Int64 {
        filteredDuplicateGroups.reduce(0) { $0 + $1.reclaimableLocalBytes }
    }

    private var totalRedundantLogicalBytes: Int64 {
        filteredDuplicateGroups.reduce(0) { $0 + $1.redundantLogicalBytes }
    }

    var body: some View {
        let isLocalOnly = viewModel.isActiveProviderLocalOnly

        VStack(spacing: 0) {
            // Top Duplicate Controls Bar
            HStack(spacing: 12) {
                Picker("Scope", selection: $viewModel.duplicateScanScope) {
                    ForEach(DuplicateScanScope.allCases) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 260)
                .help("Choose whether to scan only the selected location or across all scanned drives and folders.")

                Picker("Min Size", selection: $viewModel.duplicateMinSizeBytes) {
                    ForEach(minSizeOptions, id: \.bytes) { opt in
                        Text(opt.label).tag(opt.bytes)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 135)
                .help("Minimum file size to include in duplicate detection.")

                if !isLocalOnly || viewModel.duplicateScanScope == .allScannedSources {
                    Toggle("Include Cloud-Only", isOn: $viewModel.duplicateIncludeCloudOnly)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                        .help("Downloaded files are verified via 3-stage SHA-256 hashing without downloading cloud-only files. Enable this to also group cloud-only placeholders that share identical byte size and filename.")
                }

                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .help("Select a Primary (Keep) file in each group, then replace duplicates with a POSIX Symbolic Link, macOS Finder Alias, APFS Copy-on-Write Clone, or move Primary files to a canonical folder.")

                Spacer()

                if viewModel.isScanningDuplicates {
                    ProgressView(
                        value: Double(viewModel.duplicateScanProcessed),
                        total: Double(max(1, viewModel.duplicateScanTotal))
                    )
                    .frame(width: 100)

                    Button(action: { viewModel.stopDuplicateScan() }) {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button(action: { viewModel.startDuplicateScan() }) {
                        Label("Find Duplicates", systemImage: "doc.on.doc")
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                    .controlSize(.small)
                    .help("Run 3-stage SHA-256 duplicate scan (Stage 1: exact size, Stage 2: 64 KB head/tail hash, Stage 3: full SHA-256).")
                }

                if !filteredDuplicateGroups.isEmpty {
                    Button(action: {
                        viewModel.promptResolveSelectedDuplicateGroups()
                    }) {
                        let count = viewModel.selectedDuplicateGroupIds.isEmpty
                            ? filteredDuplicateGroups.count
                            : viewModel.selectedDuplicateGroupIds.count
                        Label(
                            viewModel.selectedDuplicateGroupIds.isEmpty
                                ? "Resolve All (\(count))..."
                                : "Resolve Selected (\(count))...",
                            systemImage: "link"
                        )
                        .fontWeight(.medium)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Replace duplicate copies with links, aliases, APFS clones, or move to Trash.")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Duplicate Groups Content
            if viewModel.isScanningDuplicates && viewModel.duplicateGroups.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text(viewModel.duplicateScanProgressText)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredDuplicateGroups.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 38))
                        .foregroundColor(.secondary.opacity(0.6))

                    Text(viewModel.duplicateGroups.isEmpty ? "Find Duplicate Files" : "No Matching Duplicates")
                        .font(.headline)

                    Text("3-stage SHA-256 verification across local and cloud files.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .help("Stage 1: Exact byte size grouping → Stage 2: 64 KB head/tail fingerprint → Stage 3: Full SHA-256 verification. Never triggers unwanted cloud downloads.")

                    Button(action: { viewModel.startDuplicateScan() }) {
                        Label("Start Duplicate Scan", systemImage: "doc.on.doc")
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                    .controlSize(.regular)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredDuplicateGroups) { group in
                            DuplicateGroupCard(
                                group: group,
                                viewModel: viewModel,
                                isSelected: viewModel.selectedDuplicateGroupIds.contains(group.id)
                            )
                        }
                    }
                    .padding(16)
                }
            }

            Divider()

            // Bottom Summary Bar
            HStack(spacing: 16) {
                Text(viewModel.duplicateScanProgressText)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if !filteredDuplicateGroups.isEmpty {
                    if !viewModel.selectedDuplicateGroupIds.isEmpty {
                        Button("Clear Selection (\(viewModel.selectedDuplicateGroupIds.count))") {
                            viewModel.selectedDuplicateGroupIds.removeAll()
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    } else {
                        Button("Select All (\(filteredDuplicateGroups.count))") {
                            viewModel.selectedDuplicateGroupIds = Set(filteredDuplicateGroups.map { $0.id })
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }

                    if totalRedundantLocalBytes == totalRedundantLogicalBytes {
                        Text("Redundant Space: **\(ByteFormatter.string(fromByteCount: totalRedundantLocalBytes))** on disk")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Redundant Space: **\(ByteFormatter.string(fromByteCount: totalRedundantLocalBytes))** on disk • **\(ByteFormatter.string(fromByteCount: totalRedundantLogicalBytes))** logical")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}

struct DuplicateGroupCard: View {
    let group: DuplicateGroup
    @ObservedObject var viewModel: AppViewModel
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Card Header
            HStack(spacing: 10) {
                Button(action: {
                    if isSelected {
                        viewModel.selectedDuplicateGroupIds.remove(group.id)
                    } else {
                        viewModel.selectedDuplicateGroupIds.insert(group.id)
                    }
                }) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)

                Image(systemName: group.kind.icon)
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))

                Text(group.sampleName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Text("\(group.items.count) copies • \(ByteFormatter.string(fromByteCount: group.fileSize)) each")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if group.isVerifiedFullHash {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.shield")
                        Text("SHA-256")
                    }
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
                    .foregroundColor(.secondary)
                    .help("Verified identical via full SHA-256 content hash: \(group.contentHash)")
                } else {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Size + Name Match")
                    }
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.15)))
                    .foregroundColor(.orange)
                    .help("Includes cloud-only placeholder files matched by exact byte size and filename without downloading.")
                }

                Spacer()

                if group.reclaimableLocalBytes > 0 {
                    if group.reclaimableLocalBytes == group.redundantLogicalBytes {
                        Text("\(ByteFormatter.string(fromByteCount: group.reclaimableLocalBytes)) redundant on disk")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.teal)
                    } else {
                        Text("\(ByteFormatter.string(fromByteCount: group.reclaimableLocalBytes)) on disk (\(ByteFormatter.string(fromByteCount: group.redundantLogicalBytes)) logical)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.teal)
                    }
                } else {
                    Text("\(ByteFormatter.string(fromByteCount: group.redundantLogicalBytes)) in cloud")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }

                Button(action: {
                    viewModel.promptResolveDuplicateGroup(group)
                }) {
                    Label("Link / Resolve...", systemImage: "link")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Replace duplicate copies in this group with links, aliases, or APFS clones")

                Button(action: {
                    viewModel.promptDeleteGroupDuplicates(group)
                }) {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)
                .disabled(viewModel.isEvicting)
                .help("Delete all \(group.duplicateItems.count) duplicate \(group.duplicateItems.count == 1 ? "copy" : "copies") in this group (keeps Primary copy)")
            }

            Divider()

            // Copies List (Radio button to choose Primary)
            VStack(spacing: 3) {
                ForEach(group.items) { item in
                    let isPrimary = (item.id == group.primaryItem?.id)
                    let provName = viewModel.providerName(for: item.providerId)
                    let provType = viewModel.providerType(for: item.providerId)
                    let isItemLocalOnly = viewModel.isProviderLocalOnly(item.providerId)

                    HStack(spacing: 8) {
                        Button(action: {
                            viewModel.setPrimaryItem(groupId: group.id, itemId: item.id)
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: isPrimary ? "largecircle.fill.circle" : "circle")
                                    .foregroundColor(isPrimary ? .teal : .secondary)
                                Text(isPrimary ? "Primary (Keep)" : "Duplicate")
                                    .font(.system(size: 10, weight: isPrimary ? .semibold : .regular))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule().fill(isPrimary ? Color.teal.opacity(0.14) : Color.secondary.opacity(0.10))
                                    )
                                    .foregroundColor(isPrimary ? .teal : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(width: 120, alignment: .leading)
                        .help(isPrimary ? "Preserved as the Primary target." : "Click to set this copy as the Primary file to keep.")

                        // Source Drive Badge
                        HStack(spacing: 4) {
                            Image(systemName: provType.systemIcon)
                                .font(.caption2)
                            Text(provName)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.10)))
                        .foregroundColor(.secondary)

                        // Reveal in Finder icon BEFORE file name/path
                        Button(action: {
                            viewModel.revealInFinder(url: item.url)
                        }) {
                            Image(systemName: "arrow.up.forward.square")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Reveal '\(item.name)' in Finder")

                        // Relative Path
                        Text(item.relativePath)
                            .font(.caption)
                            .foregroundColor(isPrimary ? .primary : .secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(item.path)

                        Spacer()

                        if item.isDataless {
                            Text("Cloud-Only")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .help("Dataless cloud placeholder (0 bytes on local disk)")
                        } else {
                            Text("\(ByteFormatter.string(fromByteCount: item.allocatedSize)) on disk")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        // Delete this specific instance button (with confirmation sheet & warning)
                        Button(action: {
                            viewModel.promptDeleteDuplicateInstance(item: item, in: group)
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundColor(isPrimary ? .secondary.opacity(0.5) : .red.opacity(0.85))
                                .frame(width: 22, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isEvicting)
                        .help(isItemLocalOnly
                            ? "Delete this duplicate instance (\(item.relativePath)) from disk..."
                            : "Delete this duplicate instance (\(item.relativePath)) from Mac & Cloud...")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isPrimary ? Color.teal.opacity(0.05) : Color.clear)
                    )
                    .contextMenu {
                        if !isPrimary {
                            Button {
                                viewModel.setPrimaryItem(groupId: group.id, itemId: item.id)
                            } label: {
                                Label("Set as Primary (Keep)", systemImage: "checkmark.circle")
                            }
                        }

                        Button {
                            viewModel.revealInFinder(url: item.url)
                        } label: {
                            Label("Reveal in Finder", systemImage: "arrow.up.forward.square")
                        }

                        Divider()

                        Button(role: .destructive) {
                            viewModel.promptDeleteDuplicateInstance(item: item, in: group)
                        } label: {
                            Label(isItemLocalOnly ? "Delete This Instance..." : "Delete This Instance from Mac & Cloud...", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor.opacity(0.6) : Color(nsColor: .separatorColor).opacity(0.5), lineWidth: isSelected ? 1.5 : 0.5)
                )
        )
    }
}
