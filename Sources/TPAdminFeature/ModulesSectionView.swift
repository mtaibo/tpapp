import SwiftUI
import TPCore

struct ModulesSectionView: View {
    @ObservedObject var store: AdminStore

    @State private var logsContainer: ContainerInfo?
    @State private var pendingStop: ContainerInfo?
    @State private var pendingDeploy: AdminModule?

    var body: some View {
        Group {
            if store.modules.isEmpty {
                ProgressView().tint(.white).padding(.top, 40)
            } else {
                VStack(spacing: 16) {
                    ForEach(store.modules) { module in
                        moduleCard(module)
                    }
                }
            }
        }
        .sheet(item: $logsContainer) { container in
            ContainerLogsView(store: store, container: container)
        }
        .confirmationDialog(
            "¿Detener \(pendingStop?.name ?? "")?",
            isPresented: Binding(get: { pendingStop != nil }, set: { if !$0 { pendingStop = nil } }),
            titleVisibility: .visible
        ) {
            Button("Detener", role: .destructive) {
                if let container = pendingStop {
                    Task { await store.perform(.stop, container: container.name) }
                }
            }
        } message: {
            Text("Seguirá parado hasta que lo arranques desde aquí o se reinicie la Raspberry.")
        }
        .confirmationDialog(
            "¿Desplegar \(pendingDeploy?.name ?? "")?",
            isPresented: Binding(get: { pendingDeploy != nil }, set: { if !$0 { pendingDeploy = nil } }),
            titleVisibility: .visible
        ) {
            Button("Desplegar") {
                if let module = pendingDeploy {
                    Task { await store.deploy(module: module.name) }
                }
            }
        } message: {
            Text(deployMessage(for: pendingDeploy))
        }
    }

    private func deployMessage(for module: AdminModule?) -> String {
        switch module?.name {
        case "tpadmin": return "git pull y reinicio del panel. Se cortará la conexión unos segundos."
        case "tpcloud": return "git pull y reconstrucción. Incluye el gateway y el login: el panel puede dejar de responder un momento."
        default: return "git pull y docker compose up -d --build."
        }
    }

    private func moduleCard(_ module: AdminModule) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(module.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    if let repo = module.repo {
                        Text("\(repo.branch ?? "?") · \(repo.commit) · \(repo.subject)")
                            .font(.system(size: 11))
                            .foregroundStyle(AdminTheme.subtle)
                            .lineLimit(1)
                    } else if !module.installed {
                        Text("No instalado en \(module.path)")
                            .font(.system(size: 11))
                            .foregroundStyle(AdminTheme.warning)
                    }
                }
                Spacer()
                if module.installed {
                    Button {
                        pendingDeploy = module
                    } label: {
                        if store.busy.contains(module.name) {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            Label("Desplegar", systemImage: "arrow.triangle.2.circlepath")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.glass)
                    .disabled(store.busy.contains(module.name))
                }
            }

            if let state = module.serviceState {
                HStack(spacing: 10) {
                    statusDot(state == "active" ? AdminTheme.success : AdminTheme.danger)
                    Text("tpadmin.service")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(state)
                        .font(.system(size: 12))
                        .foregroundStyle(AdminTheme.subtle)
                }
            }

            ForEach(module.containers) { container in
                containerRow(container)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 18))
    }

    private func containerRow(_ container: ContainerInfo) -> some View {
        HStack(spacing: 10) {
            statusDot(color(for: container))
            VStack(alignment: .leading, spacing: 2) {
                Text(container.name)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                Text(container.status)
                    .font(.system(size: 11))
                    .foregroundStyle(AdminTheme.subtle)
            }
            Spacer()
            if store.busy.contains(container.name) {
                ProgressView().controlSize(.small).tint(.white)
            } else {
                Menu {
                    Button {
                        logsContainer = container
                    } label: {
                        Label("Logs", systemImage: "text.alignleft")
                    }
                    Divider()
                    if container.isRunning {
                        Button {
                            Task { await store.perform(.restart, container: container.name) }
                        } label: {
                            Label("Reiniciar", systemImage: "arrow.clockwise")
                        }
                        Button(role: .destructive) {
                            pendingStop = container
                        } label: {
                            Label("Detener", systemImage: "stop.fill")
                        }
                    } else {
                        Button {
                            Task { await store.perform(.start, container: container.name) }
                        } label: {
                            Label("Arrancar", systemImage: "play.fill")
                        }
                    }
                    if let service = container.service, let project = container.project {
                        Divider()
                        Button {
                            Task { await store.deploy(module: project, service: service) }
                        } label: {
                            Label("Reconstruir solo \(service)", systemImage: "hammer")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                }
                .menuIndicator(.hidden)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            }
        }
    }

    private func color(for container: ContainerInfo) -> Color {
        if container.health == "unhealthy" { return AdminTheme.danger }
        switch container.state {
        case "running": return container.health == "starting" ? AdminTheme.warning : AdminTheme.success
        case "restarting", "paused", "created": return AdminTheme.warning
        default: return AdminTheme.danger
        }
    }
}
