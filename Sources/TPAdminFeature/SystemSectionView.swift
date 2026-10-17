import SwiftUI
import TPCore

struct SystemSectionView: View {
    @ObservedObject var store: AdminStore

    var body: some View {
        if let system = store.system {
            overview(system)
            if let throttled = system.throttled, !(throttled.now.isEmpty && throttled.sinceBoot.isEmpty) {
                throttling(throttled)
            }
            Section("Memory & Disks") {
                UsageRow(label: "RAM", used: system.memory.used, total: system.memory.total)
                if system.memory.swapTotal > 0 {
                    UsageRow(label: "Swap", used: system.memory.swapUsed, total: system.memory.swapTotal)
                }
                ForEach(system.disks) { disk in
                    UsageRow(label: disk.mount, used: disk.used, total: disk.total)
                }
            }
            if !store.fastfetch.isEmpty {
                Section("fastfetch") {
                    ForEach(store.fastfetch) { row in
                        LabeledContent(row.type, value: row.value)
                    }
                }
            }
        } else {
            AdminLoadingRow()
        }
    }

    private func overview(_ system: SystemStatus) -> some View {
        Section(system.hostname) {
            HStack(spacing: 12) {
                metric(
                    system.temperatureC.map { String(format: "%.1f °C", $0) } ?? "—",
                    label: "Temperature",
                    color: temperatureColor(system.temperatureC)
                )
                metric(
                    system.cpuPercent.map { String(format: "%.0f%%", $0) } ?? "—",
                    label: "CPU",
                    color: .primary
                )
                metric(
                    system.load.first.map { String(format: "%.2f", $0) } ?? "—",
                    label: "Load (1 min)",
                    color: loadColor(system.load.first, cores: system.cpuCount)
                )
            }
            .padding(.vertical, 4)
            LabeledContent("Uptime", value: formatDuration(system.uptimeSeconds))
            if system.load.count == 3 {
                LabeledContent("Load 1 / 5 / 15 min", value: system.load.map { String(format: "%.2f", $0) }.joined(separator: " / "))
            }
        }
    }

    private func metric(_ value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func throttling(_ throttled: SystemStatus.Throttled) -> some View {
        Section("Power & Temperature") {
            if !throttled.now.isEmpty {
                Label("Now: " + throttled.now.map(describe).joined(separator: ", "), systemImage: "bolt.trianglebadge.exclamationmark.fill")
                    .foregroundStyle(.red)
            }
            if !throttled.sinceBoot.isEmpty {
                Label("Since boot: " + throttled.sinceBoot.map(describe).joined(separator: ", "), systemImage: "clock.badge.exclamationmark")
                    .foregroundStyle(.orange)
            }
        }
    }

    private func describe(_ flag: String) -> String {
        switch flag {
        case "under_voltage": return "under-voltage (check the power supply)"
        case "arm_frequency_capped": return "frequency capped"
        case "throttled": return "CPU throttled"
        case "soft_temp_limit": return "soft temperature limit"
        default: return flag
        }
    }

    /// The Pi 5 starts throttling around 80–85 °C.
    private func temperatureColor(_ celsius: Double?) -> Color {
        guard let celsius else { return .primary }
        if celsius >= 75 { return .red }
        if celsius >= 60 { return .orange }
        return .green
    }

    private func loadColor(_ load: Double?, cores: Int?) -> Color {
        guard let load, let cores, cores > 0 else { return .primary }
        if load >= Double(cores) { return .red }
        if load >= Double(cores) * 0.7 { return .orange }
        return .primary
    }
}
