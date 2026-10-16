import SwiftUI
import TPCore

struct SystemSectionView: View {
    @ObservedObject var store: AdminStore

    var body: some View {
        if let system = store.system {
            VStack(spacing: 16) {
                overview(system)
                if let throttled = system.throttled, !(throttled.now.isEmpty && throttled.sinceBoot.isEmpty) {
                    throttling(throttled)
                }
                adminCard(title: "Memoria y discos") {
                    usageBar("RAM", used: system.memory.used, total: system.memory.total)
                    if system.memory.swapTotal > 0 {
                        usageBar("Swap", used: system.memory.swapUsed, total: system.memory.swapTotal)
                    }
                    ForEach(system.disks) { disk in
                        usageBar(disk.mount, used: disk.used, total: disk.total)
                    }
                }
                if !store.fastfetch.isEmpty {
                    adminCard(title: "fastfetch") {
                        ForEach(store.fastfetch) { row in
                            adminInfoRow(row.type, row.value)
                        }
                    }
                }
            }
        } else {
            ProgressView().tint(.white).padding(.top, 40)
        }
    }

    private func overview(_ system: SystemStatus) -> some View {
        adminCard(title: system.hostname) {
            HStack(spacing: 12) {
                metric(
                    system.temperatureC.map { String(format: "%.1f °C", $0) } ?? "—",
                    label: "Temperatura",
                    color: temperatureColor(system.temperatureC)
                )
                metric(
                    system.cpuPercent.map { String(format: "%.0f %%", $0) } ?? "—",
                    label: "CPU",
                    color: .white
                )
                metric(
                    system.load.first.map { String(format: "%.2f", $0) } ?? "—",
                    label: "Carga (1 min)",
                    color: loadColor(system.load.first, cores: system.cpuCount)
                )
            }
            adminInfoRow("Encendida desde hace", formatDuration(system.uptimeSeconds))
            if system.load.count == 3 {
                adminInfoRow("Carga 1 / 5 / 15 min", system.load.map { String(format: "%.2f", $0) }.joined(separator: " / "))
            }
        }
    }

    private func metric(_ value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(AdminTheme.subtle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func throttling(_ throttled: SystemStatus.Throttled) -> some View {
        adminCard(title: "Alimentación y temperatura") {
            if !throttled.now.isEmpty {
                Text("Ahora: " + throttled.now.map(describe).joined(separator: ", "))
                    .font(.system(size: 14))
                    .foregroundStyle(AdminTheme.danger)
            }
            if !throttled.sinceBoot.isEmpty {
                Text("Desde el arranque: " + throttled.sinceBoot.map(describe).joined(separator: ", "))
                    .font(.system(size: 14))
                    .foregroundStyle(AdminTheme.warning)
            }
        }
    }

    private func describe(_ flag: String) -> String {
        switch flag {
        case "under_voltage": return "subvoltaje (revisa la fuente)"
        case "arm_frequency_capped": return "frecuencia limitada"
        case "throttled": return "CPU ralentizada"
        case "soft_temp_limit": return "límite de temperatura"
        default: return flag
        }
    }

    /// The Pi 5 starts throttling around 80–85 °C.
    private func temperatureColor(_ celsius: Double?) -> Color {
        guard let celsius else { return .white }
        if celsius >= 75 { return AdminTheme.danger }
        if celsius >= 60 { return AdminTheme.warning }
        return AdminTheme.success
    }

    private func loadColor(_ load: Double?, cores: Int?) -> Color {
        guard let load, let cores, cores > 0 else { return .white }
        if load >= Double(cores) { return AdminTheme.danger }
        if load >= Double(cores) * 0.7 { return AdminTheme.warning }
        return .white
    }
}
