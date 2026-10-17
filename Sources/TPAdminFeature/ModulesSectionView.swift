import SwiftUI
import TPCore
import TPUI

struct ModulesSectionView: View {
    @ObservedObject var store: AdminStore

    @State private var logsContainer: ContainerInfo?
    @State private var pendingStop: ContainerInfo?
    @State private var pendingDeploy: AdminModule?

    var body: some View {
        Group {
            if store.modules.isEmpty {
                AdminLoadingRow()
            } else {
                ForEach(store.modules) { module in
                    moduleSection(module)
                }
            }
        }
        .sheet(item: $logsContainer) { container in
            ContainerLogsView(store: store, container: container)
        }
        .confirmationDialog(
            "Stop \(pendingStop?.name ?? "")?",
            isPresented: Binding(get: { pendingStop != nil }, set: { if !$0 { pendingStop = nil } }),
            titleVisibility: .visible,
            presenting: pendingStop
        ) { container in
            Button("Stop", role: .destructive) {
                Task { await store.perform(.stop, container: container.name) }
            }
        } message: { _ in
            Text("It stays stopped until you start it from here or the Raspberry Pi reboots.")
        }
        .confirmationDialog(
            "Deploy \(pendingDeploy?.name ?? "")?",
            isPresented: Binding(get: { pendingDeploy != nil }, set: { if !$0 { pendingDeploy = nil } }),
            titleVisibility: .visible,
            presenting: pendingDeploy
        ) { module in
            Button("Deploy") {
                Task { await store.deploy(module: module.name) }
            }
        } message: { module in
            Text(deployMessage(for: module))
        }
    }

    private func deployMessage(for module: AdminModule) -> String {
        switch module.name {
        case "tpadmin": return "git pull and restart the panel. The connection will drop for a few seconds."
        case "tpcloud": return "git pull and rebuild. Includes the gateway and login, so this panel may stop responding briefly."
        default: return "git pull and docker compose up -d --build."
        }
    }

    private func moduleSection(_ module: AdminModule) -> some View {
        Section {
            if let state = module.serviceState {
                HStack(spacing: 10) {
                    StatusDot(state == "active" ? .green : .red, label: state)
                    Text("tpadmin.service")
                    Spacer()
                    Text(state)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(module.containers) { container in
                containerRow(container)
            }

            if module.installed {
                Button {
                    pendingDeploy = module
                } label: {
                    HStack {
                        Label("Deploy", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        if store.busy.contains(module.name) { ProgressView() }
                    }
                }
                .disabled(store.busy.contains(module.name))
            }
        } header: {
            Text(module.name)
        } footer: {
            if let repo = module.repo {
                Text("\(repo.branch ?? "?") · \(repo.commit) · \(repo.subject)")
                    .lineLimit(1)
            } else if !module.installed {
                Text("Not installed at \(module.path)")
                    .foregroundStyle(.orange)
            }
        }
    }

    private func containerRow(_ container: ContainerInfo) -> some View {
        HStack(spacing: 10) {
            StatusDot(color(for: container), label: container.state)
            VStack(alignment: .leading, spacing: 2) {
                Text(container.name)
                Text(container.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.busy.contains(container.name) {
                ProgressView()
            } else {
                Menu {
                    containerActions(container)
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .menuIndicator(.hidden)
                .buttonStyle(.borderless)
            }
        }
        .contextMenu { containerActions(container) }
    }

    @ViewBuilder
    private func containerActions(_ container: ContainerInfo) -> some View {
        Button("Logs", systemImage: "text.alignleft") { logsContainer = container }
        Divider()
        if container.isRunning {
            Button("Restart", systemImage: "arrow.clockwise") {
                Task { await store.perform(.restart, container: container.name) }
            }
            Button("Stop", systemImage: "stop.fill", role: .destructive) { pendingStop = container }
        } else {
            Button("Start", systemImage: "play.fill") {
                Task { await store.perform(.start, container: container.name) }
            }
        }
        if let service = container.service, let project = container.project {
            Divider()
            Button("Rebuild \(service) Only", systemImage: "hammer") {
                Task { await store.deploy(module: project, service: service) }
            }
        }
    }

    private func color(for container: ContainerInfo) -> Color {
        if container.health == "unhealthy" { return .red }
        switch container.state {
        case "running": return container.health == "starting" ? .orange : .green
        case "restarting", "paused", "created": return .orange
        default: return .red
        }
    }
}
