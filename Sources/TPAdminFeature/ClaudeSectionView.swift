import SwiftUI
import TPCore
import TPUI

struct ClaudeSectionView: View {
    @ObservedObject var store: AdminStore
    @Environment(\.openURL) private var openURL

    @State private var pendingStop: ClaudeSession?

    var body: some View {
        Group {
            if let list = store.claude {
                newSessionSection(directories: list.directories)
                if list.sessions.isEmpty {
                    Section {
                        Text("No Claude sessions running")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(list.sessions) { session in
                    sessionSection(session)
                }
            } else {
                AdminLoadingRow()
            }
        }
        .confirmationDialog(
            "Stop \(pendingStop?.name ?? "")?",
            isPresented: Binding(get: { pendingStop != nil }, set: { if !$0 { pendingStop = nil } }),
            titleVisibility: .visible,
            presenting: pendingStop
        ) { session in
            Button("Stop", role: .destructive) {
                Task { await store.stopClaudeSession(name: session.name) }
            }
        } message: { session in
            if session.isPrimary {
                Text("This is the session this panel was set up from. That conversation will end and you'll need to start it again.")
            } else {
                Text("The claude remote-control process will be closed. Any ongoing conversations will end.")
            }
        }
    }

    private func newSessionSection(directories: [String]) -> some View {
        let isStarting = directories.contains { store.busy.contains($0) }
        return Section {
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
                HStack {
                    Label("New Session…", systemImage: "plus")
                    Spacer()
                    if isStarting { ProgressView() }
                }
            }
            .disabled(isStarting)
        } header: {
            Text("New Session")
        } footer: {
            Text("Starts `claude remote-control` in the background in the chosen folder. Connect from the Claude app or claude.ai.")
        }
    }

    private func sessionSection(_ session: ClaudeSession) -> some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName(session.directory))
                        .font(.headline)
                    Text(session.name + (session.isPrimary ? " · this connection" : ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                stateBadge(session.state)
            }

            if session.state == .needsAttention {
                Button {
                    Task { await store.trustClaudeSessionFolder(name: session.name) }
                } label: {
                    HStack {
                        Label("Trust Folder", systemImage: "checkmark.shield")
                        Spacer()
                        if store.busy.contains(session.name) { ProgressView() }
                    }
                }
                .disabled(store.busy.contains(session.name))
            } else if let url = session.url.flatMap(URL.init(string:)) {
                Button("Open", systemImage: "arrow.up.right.square") { openURL(url) }
            }

            Button(role: .destructive) {
                pendingStop = session
            } label: {
                HStack {
                    Label("Stop", systemImage: "stop.fill")
                    Spacer()
                    if store.busy.contains(session.name), session.state != .needsAttention { ProgressView() }
                }
            }
            .disabled(store.busy.contains(session.name))
        } footer: {
            if session.state == .needsAttention {
                Text("Claude is asking whether you trust this folder before it can be used.")
            }
        }
    }

    private func stateBadge(_ state: ClaudeSession.State) -> StatusBadge {
        switch state {
        case .connected: return StatusBadge("Connected", tint: .green)
        case .connecting, .starting: return StatusBadge("Starting", tint: .orange)
        case .needsAttention: return StatusBadge("Waiting", tint: .orange)
        case .disconnected: return StatusBadge("Disconnected", tint: .red)
        }
    }

    /// "/home/u/workspace/tpstore" → "tpstore"; the workspace root itself → "workspace".
    private func displayName(_ directory: String) -> String {
        (directory as NSString).lastPathComponent
    }
}
