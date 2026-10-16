import SwiftUI
import TPCore

/// Live output of the deploy started from the modules section.
struct DeployJobView: View {
    @ObservedObject var store: AdminStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if let job = store.activeJob {
                    switch job.status {
                    case .running: ProgressView().controlSize(.small)
                    case .succeeded: Image(systemName: "checkmark.circle.fill").foregroundStyle(AdminTheme.success)
                    case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(AdminTheme.danger)
                    }
                    Text(job.title)
                        .font(.system(size: 15, weight: .semibold))
                }
                Spacer()
                Button(store.activeJob?.status == .running ? "Ocultar" : "Cerrar") { dismiss() }
            }
            .padding(16)

            ScrollViewReader { proxy in
                ScrollView {
                    Text(store.activeJob?.output ?? "")
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    Color.clear.frame(height: 1).id("bottom")
                }
                .onChange(of: store.activeJob?.output) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 480)
        #endif
    }
}
