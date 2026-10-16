import SwiftUI
import TPCore

struct ClaudeSectionView: View {
    @ObservedObject var store: AdminStore
    @Environment(\.openURL) private var openURL

    @State private var pendingStop: ClaudeSession?

    var body: some View {
        VStack(spacing: 16) {
            if let list = store.claude {
                newSessionCard(directories: list.directories)
                if list.sessions.isEmpty {
                    Text("No hay sesiones de Claude en marcha")
                        .font(.system(size: 14))
                        .foregroundStyle(AdminTheme.muted)
                        .padding(.top, 8)
                }
                ForEach(list.sessions) { session in
                    sessionCard(session)
                }
            } else {
                ProgressView().tint(.white).padding(.top, 40)
            }
        }
        .confirmationDialog(
            "¿Detener \(pendingStop?.name ?? "")?",
            isPresented: Binding(get: { pendingStop != nil }, set: { if !$0 { pendingStop = nil } }),
            titleVisibility: .visible
        ) {
            Button("Detener", role: .destructive) {
                if let session = pendingStop {
                    Task { await store.stopClaudeSession(name: session.name) }
                }
            }
        } message: {
            if pendingStop?.isPrimary == true {
                Text("Es la sesión desde la que montaste este panel: se cortará esa conversación y tendrás que volver a arrancarla.")
            } else {
                Text("Se cerrará el proceso de claude remote-control. Las conversaciones en curso se cortarán.")
            }
        }
    }

    private func newSessionCard(directories: [String]) -> some View {
        adminCard(title: "Nueva sesión") {
            Text("Arranca `claude remote-control` en segundo plano en la carpeta elegida y conéctate desde la app de Claude o claude.ai.")
                .font(.system(size: 13))
                .foregroundStyle(AdminTheme.subtle)
            Menu {
                ForEach(directories, id: \.self) { directory in
                    Button(displayName(directory)) {
                        Task {
                            if let session = await store.startClaudeSession(directory: directory),
                               let url = session.url.flatMap(URL.init(string:)) {
                                openURL(url)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if directories.contains { store.busy.contains($0) } {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "plus")
                    }
                    Text("Elegir carpeta")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .menuIndicator(.hidden)
            .buttonStyle(.glass)
            .disabled(directories.contains { store.busy.contains($0) })
        }
    }

    private func sessionCard(_ session: ClaudeSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName(session.directory))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(session.name + (session.isPrimary ? " · esta conexión" : ""))
                        .font(.system(size: 11))
                        .foregroundStyle(AdminTheme.subtle)
                }
                Spacer()
                stateBadge(session.state)
            }

            if session.state == .needsAttention {
                Text("Claude pregunta si confías en esta carpeta antes de poder usarla.")
                    .font(.system(size: 13))
                    .foregroundStyle(AdminTheme.warning)
            }

            HStack(spacing: 10) {
                if session.state == .needsAttention {
                    actionButton("Confiar", systemImage: "checkmark.shield", busy: store.busy.contains(session.name)) {
                        Task { await store.trustClaudeSessionFolder(name: session.name) }
                    }
                } else if let url = session.url.flatMap(URL.init(string:)) {
                    actionButton("Abrir", systemImage: "arrow.up.right.square", busy: false) {
                        openURL(url)
                    }
                }
                actionButton("Detener", systemImage: "stop.fill", busy: store.busy.contains(session.name), role: .destructive) {
                    pendingStop = session
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 18))
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        busy: Bool,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            HStack(spacing: 6) {
                if busy {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(role == .destructive ? AdminTheme.danger : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.glass)
        .disabled(busy)
    }

    private func stateBadge(_ state: ClaudeSession.State) -> some View {
        switch state {
        case .connected: return adminBadge("Conectada", color: AdminTheme.success)
        case .connecting, .starting: return adminBadge("Arrancando", color: AdminTheme.warning)
        case .needsAttention: return adminBadge("Esperando", color: AdminTheme.warning)
        case .disconnected: return adminBadge("Desconectada", color: AdminTheme.danger)
        }
    }

    /// "/home/u/workspace/tpstore" → "tpstore"; the workspace root itself → "workspace".
    private func displayName(_ directory: String) -> String {
        (directory as NSString).lastPathComponent
    }
}
