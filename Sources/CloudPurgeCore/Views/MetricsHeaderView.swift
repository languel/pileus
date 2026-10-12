import SwiftUI

struct MetricsHeaderView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: 16) {
            // Card 1: Reclaimable Space
            MetricCard(
                title: "Reclaimable Disk Space",
                value: ByteFormatter.string(fromByteCount: viewModel.totalReclaimableBytes),
                subtitle: "\(viewModel.totalDownloadedCount) files downloaded locally",
                systemImage: "arrow.down.to.line.compact",
                tintColor: .green
            )

            // Card 2: Local vs Cloud Size
            MetricCard(
                title: "Cloud Total",
                value: ByteFormatter.string(fromByteCount: viewModel.totalCloudBytes),
                subtitle: "\(viewModel.allItems.count) files in cloud index",
                systemImage: "icloud",
                tintColor: .blue
            )

            // Card 3: Storage Breakdown & Gauge
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Reclaimable Content")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1f%%", viewModel.reclaimablePercentage))
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(nsColor: .separatorColor).opacity(0.3))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [.green, .mint],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(viewModel.reclaimablePercentage / 100.0))), height: 8)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text("\(ByteFormatter.string(fromByteCount: viewModel.totalReclaimableBytes)) on Mac")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(ByteFormatter.string(fromByteCount: max(0, viewModel.totalCloudBytes - viewModel.totalReclaimableBytes))) cloud-only")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: Color.black.opacity(0.04), radius: 2, y: 1)
            )

            // Card 4: Action Button
            VStack(spacing: 8) {
                if !viewModel.selectedItemIds.isEmpty {
                    Button(action: { viewModel.promptEvictSelection() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.bin.fill")
                            Text("Remove (\(viewModel.selectedItemIds.count))")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button(action: { viewModel.promptEvictAllFiltered() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                            Text("Remove All Downloads")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(viewModel.totalReclaimableBytes == 0 || viewModel.isEvicting)
                }

                Button(action: { viewModel.startScan() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Rescan")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isScanning)
            }
            .frame(width: 170)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String
    let tintColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 22))
                .foregroundColor(tintColor)
                .frame(width: 28, height: 28)
                .padding(6)
                .background(Circle().fill(tintColor.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(12)
        .frame(minWidth: 170)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.04), radius: 2, y: 1)
        )
    }
}
