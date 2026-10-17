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
        VStack(spacing: 0) {
            // Top Duplicate Controls Bar
            HStack(spacing: 12) {
                Picker("Scope", selection: $viewModel.duplicateScanScope) {
                    ForEach(DuplicateScanScope.allCases) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 265)

                Picker("Min Size", selection: $viewModel.duplicateMinSizeBytes) {
                    ForEach(minSizeOptions, id: \.bytes) { opt in
                        Text(opt.label).tag(opt.bytes)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 145)

                Toggle("Match Cloud-Only by Name+Size", isOn: $viewModel.duplicateIncludeCloudOnly)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .help("Downloaded files are verified via SHA-256 content hashes without downloading cloud-only files. Enable this to also group cloud-only placeholders that share identical byte size and filename.")

                Spacer()

                if viewModel.isScanningDuplicates {
                    ProgressView(
                        value: Double(viewModel.duplicateScanProcessed),
                        total: Double(max(1, viewModel.duplicateScanTotal))
                    )
                    .frame(width: 110)

                    Button(action: { viewModel.stopDuplicateScan() }) {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button(action: { viewModel.startDuplicateScan() }) {
                        Label("Find Duplicates", systemImage: "sparkle.magnifyingglass")
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .controlSize(.small)
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
                                ? "Resolve All (\(count) Groups)..."
                                : "Resolve Selected (\(count))...",
                            systemImage: "link.badge.plus"
                        )
                        .fontWeight(.medium)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))

            Divider()

            // Platform Compatibility Guidance Banner
            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.purple)
                Text("Select a **Primary (Keep)** file in each duplicate group, then replace the remaining copies with a **POSIX Symbolic Link** (best for local drives & code/CLI), a **macOS Finder Alias** (cloud-safe for iCloud Drive & Google Drive), or an **APFS Copy-on-Write Clone** (0 extra local SSD space).")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 7)
            .background(Color.purple.opacity(0.06))

            Divider()

            // Duplicate Groups Content
            if viewModel.isScanningDuplicates && viewModel.duplicateGroups.isEmpty {
                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.large)
                    Text(viewModel.duplicateScanProgressText)
                        .font(.headline)
                    Text("Stage 1: Exact byte size grouping → Stage 2: 64 KB head/tail fingerprint → Stage 3: Full SHA-256 verification")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredDuplicateGroups.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 42))
                        .foregroundColor(.secondary.opacity(0.6))

                    Text(viewModel.duplicateGroups.isEmpty ? "Ready to Find Duplicate Files" : "No Duplicates Match Search Filter")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("Click **Find Duplicates** above to scan your current drive or across all scanned drives (both Cloud Drives and Local Custom Folders). CloudPurge uses a 3-stage SHA-256 pipeline and never triggers unwanted cloud downloads.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 500)

                    Button(action: { viewModel.startDuplicateScan() }) {
                        Label("Start Duplicate Scan", systemImage: "sparkle.magnifyingglass")
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
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
                        .foregroundColor(.accentColor)
                    } else {
                        Button("Select All (\(filteredDuplicateGroups.count))") {
                            viewModel.selectedDuplicateGroupIds = Set(filteredDuplicateGroups.map { $0.id })
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    }

                    Text("Redundant Space: **\(ByteFormatter.string(fromByteCount: totalRedundantLocalBytes))** local / **\(ByteFormatter.string(fromByteCount: totalRedundantLogicalBytes))** total")
                        .font(.caption)
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
                    .foregroundColor(.indigo)
                    .font(.system(size: 15))

                Text(group.sampleName)
                    .font(.headline)
                    .lineLimit(1)

                Text("\(group.items.count) identical copies • \(ByteFormatter.string(fromByteCount: group.fileSize)) each")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if group.isVerifiedFullHash {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.shield.fill")
                        Text("SHA-256 Verified")
                    }
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.green.opacity(0.14)))
                    .foregroundColor(.green)
                    .help("SHA-256: \(group.contentHash)")
                } else {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Cloud Size+Name Match")
                    }
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.14)))
                    .foregroundColor(.orange)
                    .help("Matched by exact byte size and filename without downloading cloud-only files.")
                }

                Spacer()

                if group.reclaimableLocalBytes > 0 {
                    Text("Saves \(ByteFormatter.string(fromByteCount: group.reclaimableLocalBytes)) local (\(ByteFormatter.string(fromByteCount: group.redundantLogicalBytes)) cloud)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                } else {
                    Text("Saves \(ByteFormatter.string(fromByteCount: group.redundantLogicalBytes)) cloud")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }

                Button(action: {
                    viewModel.promptResolveDuplicateGroup(group)
                }) {
                    Label("Link / Resolve...", systemImage: "link")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .controlSize(.small)
            }

            Divider()

            // Copies List (Radio button to choose Primary)
            VStack(spacing: 4) {
                ForEach(group.items) { item in
                    let isPrimary = (item.id == group.primaryItem?.id)
                    let provName = viewModel.providerName(for: item.providerId)
                    let provType = viewModel.providerType(for: item.providerId)

                    HStack(spacing: 10) {
                        Button(action: {
                            viewModel.setPrimaryItem(groupId: group.id, itemId: item.id)
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: isPrimary ? "largecircle.fill.circle" : "circle")
                                    .foregroundColor(isPrimary ? .green : .secondary)
                                Text(isPrimary ? "PRIMARY (KEEP)" : "DUPLICATE (LINK)")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule().fill(isPrimary ? Color.green.opacity(0.18) : Color.purple.opacity(0.14))
                                    )
                                    .foregroundColor(isPrimary ? .green : .purple)
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(width: 142, alignment: .leading)
                        .help(isPrimary ? "This copy will be preserved as the Primary target." : "Click to make this copy the Primary file to keep.")

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
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.12)))
                        .foregroundColor(.secondary)

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
                                .foregroundColor(.blue)
                        } else {
                            Text("\(ByteFormatter.string(fromByteCount: item.allocatedSize)) on disk")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Button(action: {
                            viewModel.revealInFinder(url: item.url)
                        }) {
                            Image(systemName: "magnifyingglass.circle")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Reveal in Finder")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isPrimary ? Color.green.opacity(0.06) : Color.clear)
                    )
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color.accentColor.opacity(0.6) : Color(nsColor: .separatorColor).opacity(0.5), lineWidth: isSelected ? 1.5 : 0.5)
                )
        )
    }
}
