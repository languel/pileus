import SwiftUI

struct EvictionConfirmSheet: View {
    @ObservedObject var viewModel: AppViewModel

    var totalBytesToReclaim: Int64 {
        viewModel.pendingEvictionItems.reduce(0) { $0 + $1.allocatedSize }
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "arrow.down.to.line.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.green)

                Text(viewModel.pendingEvictionTitle)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(viewModel.pendingEvictionDescription)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }

            // Highlight Box
            HStack(spacing: 24) {
                VStack(spacing: 2) {
                    Text("Disk Space to Reclaim")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(ByteFormatter.string(fromByteCount: totalBytesToReclaim))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                }

                Divider()
                    .frame(height: 36)

                VStack(spacing: 2) {
                    Text("Files to Evict")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(viewModel.pendingEvictionItems.count)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }

                Divider()
                    .frame(height: 36)

                VStack(spacing: 2) {
                    Text("Cloud Status")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("100% Preserved")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )

            // Preview of items being evicted
            VStack(alignment: .leading, spacing: 6) {
                Text("Files to be evicted (first \(min(50, viewModel.pendingEvictionItems.count))):")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.pendingEvictionItems.prefix(50)) { item in
                            HStack {
                                Image(systemName: item.kind.icon)
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Text(item.name)
                                    .font(.caption)
                                    .lineLimit(1)

                                Spacer()

                                Text(ByteFormatter.string(fromByteCount: item.allocatedSize))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.green)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: .textBackgroundColor).opacity(0.5)))
                        }
                    }
                    .padding(4)
                }
                .frame(maxHeight: 180)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
            }
            .frame(maxWidth: 480)

            // Bottom Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    viewModel.showConfirmationSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button(action: {
                    viewModel.executeConfirmedEviction()
                }) {
                    Text("Evict Local Copies")
                        .fontWeight(.semibold)
                        .frame(minWidth: 150)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 540)
    }
}
