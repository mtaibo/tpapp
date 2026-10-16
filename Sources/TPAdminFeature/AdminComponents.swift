import SwiftUI

/// Shared building blocks for the admin sections, matching AccountView's cards and badges.
enum AdminTheme {
    static let muted = Color(white: 0.5)
    static let subtle = Color(white: 0.45)
    static let success = Color(red: 0.525, green: 0.937, blue: 0.675)
    static let warning = Color(red: 1.0, green: 0.776, blue: 0.392)
    static let danger = Color(red: 0.988, green: 0.647, blue: 0.647)
}

func adminCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 14) {
        Text(title.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .tracking(1)
            .foregroundStyle(AdminTheme.muted)
        content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(18)
    .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 18))
}

func adminInfoRow(_ label: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
        Text(label).foregroundStyle(AdminTheme.subtle)
        Spacer(minLength: 12)
        Text(value)
            .foregroundStyle(.white)
            .multilineTextAlignment(.trailing)
    }
    .font(.system(size: 14))
}

func adminBadge(_ text: String, color: Color) -> some View {
    Text(text.uppercased())
        .font(.system(size: 10, weight: .semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(color)
        .glassEffect(.regular, in: .capsule)
}

func statusDot(_ color: Color) -> some View {
    Circle().fill(color).frame(width: 8, height: 8)
}

/// A labelled usage bar, e.g. memory or a disk.
func usageBar(_ label: String, used: Int, total: Int) -> some View {
    let fraction = total > 0 ? Double(used) / Double(total) : 0
    return VStack(alignment: .leading, spacing: 6) {
        HStack {
            Text(label).foregroundStyle(AdminTheme.subtle)
            Spacer()
            Text("\(formatBytes(used)) / \(formatBytes(total))")
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .font(.system(size: 13))
        ProgressView(value: fraction)
            .tint(fraction > 0.9 ? AdminTheme.danger : fraction > 0.75 ? AdminTheme.warning : .white)
    }
}

func formatBytes(_ count: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .memory)
}

func formatDuration(_ seconds: Double) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = seconds >= 86_400 ? [.day, .hour] : [.hour, .minute]
    formatter.unitsStyle = .abbreviated
    return formatter.string(from: seconds) ?? ""
}
