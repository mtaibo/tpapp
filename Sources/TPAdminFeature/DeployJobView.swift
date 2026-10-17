import SwiftUI
import TPCore

/// Live output of the deploy started from the modules section.
struct DeployJobView: View {
    @ObservedObject var store: AdminStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(store.activeJob?.output ?? "")
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    Color.clear.frame(height: 1).id("bottom")
                }
                .onChange(of: store.activeJob?.output) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .navigationTitle(store.activeJob?.title ?? "Deploy")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(store.activeJob?.status == .running ? "Hide" : "Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    switch store.activeJob?.status {
                    case .running: ProgressView()
                    case .succeeded: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Succeeded")
                    case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red).accessibilityLabel("Failed")
                    case nil: EmptyView()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 480)
        #endif
    }
}
