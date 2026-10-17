import SwiftUI
import TPCore

struct ContainerLogsView: View {
    @ObservedObject var store: AdminStore
    let container: ContainerInfo

    @Environment(\.dismiss) private var dismiss
    @State private var lines: [String] = []
    @State private var errorMessage: String?
    @State private var isFollowing = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding()
                }
                ScrollViewReader { proxy in
                    ScrollView([.vertical, .horizontal]) {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                Text(displayLine(line))
                                    .font(.caption2.monospaced())
                                    .textSelection(.enabled)
                                    .fixedSize()
                                    .id(index)
                            }
                        }
                        .padding(12)
                    }
                    .onChange(of: lines.count) { _, count in
                        if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) }
                    }
                }
            }
            .navigationTitle(container.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Toggle(isOn: $isFollowing) {
                        Label("Live", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .help("Refresh every few seconds")
                }
            }
        }
        .task(id: isFollowing) {
            repeat {
                await load()
                guard isFollowing else { return }
                try? await Task.sleep(for: .seconds(3))
            } while !Task.isCancelled
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 480)
        #endif
    }

    private func load() async {
        do {
            lines = try await store.logs(container: container.name)
            errorMessage = nil
        } catch is CancellationError {
        } catch {
            errorMessage = apiErrorMessage(error)
        }
    }

    /// docker's `-t` timestamps are RFC 3339 with nanoseconds; keep just the time of day.
    private func displayLine(_ line: String) -> String {
        guard let space = line.firstIndex(of: " "),
              let t = line[..<space].firstIndex(of: "T") else { return line }
        let time = line[line.index(after: t)..<space].prefix(8)
        return "\(time) \(line[line.index(after: space)...])"
    }
}
