import SwiftUI

struct FilterBarView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        let isLocalOnly = viewModel.isActiveProviderLocalOnly

        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // View Switcher (Files vs Folders vs Duplicates)
                Picker("", selection: $viewModel.activeTab) {
                    ForEach(AppTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 480)

                Spacer()

                // Search Box
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField(
                        viewModel.activeTab == .folders
                            ? "Search folders (e.g. node_modules, .venv, build)..."
                            : (viewModel.activeTab == .duplicates
                                ? "Filter duplicate groups by file name or path..."
                                : "Search files by name or folder..."),
                        text: $viewModel.filterOptions.searchText
                    )
                    .textFieldStyle(.plain)
                    if !viewModel.filterOptions.searchText.isEmpty {
                        Button(action: { viewModel.filterOptions.searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                        )
                )
                .frame(maxWidth: 340)
            }

            if viewModel.activeTab != .duplicates {
                // Filters row
                HStack(spacing: 10) {
                    if !isLocalOnly {
                        // Status Filter (only applies to cloud-backed drives)
                        Picker("Status", selection: $viewModel.filterOptions.statusFilter) {
                            ForEach(StatusFilter.allCases) { status in
                                Text(status.rawValue).tag(status)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 160)
                    }

                    // Minimum Size Filter
                    Picker("Size", selection: $viewModel.filterOptions.sizeFilter) {
                        ForEach(SizeFilter.allCases) { size in
                            Text(size.rawValue).tag(size)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 130)

                    // Age Filter
                    Picker("Age", selection: $viewModel.filterOptions.ageFilter) {
                        ForEach(AgeFilter.allCases) { age in
                            Text(age.rawValue).tag(age)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 140)

                    // File Kind Filter
                    Picker("Kind", selection: $viewModel.filterOptions.kindFilter) {
                        ForEach(FileKindFilter.allCases) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 130)

                    Spacer()

                    // Sorting
                    HStack(spacing: 4) {
                        Text("Sort:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Picker("", selection: $viewModel.sortOption.field) {
                            ForEach(SortField.allCases) { field in
                                Text(sortFieldLabel(field, isLocalOnly: isLocalOnly)).tag(field)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 155)

                        Button(action: {
                            viewModel.sortOption.ascending.toggle()
                        }) {
                            Image(systemName: viewModel.sortOption.ascending ? "arrow.up" : "arrow.down")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .padding(4)
                        .help(viewModel.sortOption.ascending ? "Ascending" : "Descending")
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func sortFieldLabel(_ field: SortField, isLocalOnly: Bool) -> String {
        guard isLocalOnly else { return field.rawValue }
        switch field {
        case .allocatedSize: return "Size on Disk"
        case .fileSize: return "Logical Size"
        default: return field.rawValue
        }
    }
}
