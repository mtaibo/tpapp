import SwiftUI

/// A labelled usage bar, e.g. memory or a disk, colored by how full it is.
struct UsageRow: View {
    let label: String
    let used: Int
    let total: Int

    private var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                Spacer()
                Text("\(formatMemory(used)) of \(formatMemory(total))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            ProgressView(value: fraction)
                .tint(fraction > 0.9 ? .red : fraction > 0.75 ? .orange : .accentColor)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

func formatMemory(_ count: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .memory)
}

func formatDuration(_ seconds: Double) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = seconds >= 86_400 ? [.day, .hour] : [.hour, .minute]
    formatter.unitsStyle = .abbreviated
    return formatter.string(from: seconds) ?? ""
}
