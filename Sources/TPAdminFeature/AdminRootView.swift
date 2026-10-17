import SwiftUI
import TPCore
import TPUI

/// The Raspberry Pi control panel, pushed from the More tab. A segmented control in the nav bar
/// picks the section; only the visible one is polled.
public struct AdminRootView: View {
    @ObservedObject var store: AdminStore

    @State private var section: AdminStore.Section = .system

    public init(store: AdminStore) {
        self.store = store
    }

    public var body: some View {
        List {
            if let error = store.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
            }
            switch section {
            case .system: SystemSectionView(store: store)
            case .modules: ModulesSectionView(store: store)
            case .claude: ClaudeSectionView(store: store)
            }
        }
        .navigationTitle("Admin")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Section", selection: $section) {
                    ForEach(AdminStore.Section.allCases, id: \.self) { item in
                        Text(title(for: item)).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
        .refreshable { await store.refresh(section) }
        // Polls only the visible section, and stops when the screen is left (the task is cancelled).
        .task(id: section) { await store.poll(section) }
        .sheet(item: $store.activeJob) { _ in
            DeployJobView(store: store)
        }
    }

    private func title(for item: AdminStore.Section) -> String {
        switch item {
        case .system: return "System"
        case .modules: return "Modules"
        case .claude: return "Claude"
        }
    }
}

/// Shown in place of a section's rows until its first response arrives.
struct AdminLoadingRow: View {
    var body: some View {
        Section {
            ProgressView()
                .frame(maxWidth: .infinity)
        }
    }
}
