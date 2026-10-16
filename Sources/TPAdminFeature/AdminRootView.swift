import SwiftUI
import TPCore

public struct AdminRootView: View {
    @ObservedObject var store: AdminStore

    @State private var section: AdminStore.Section = .system
    @State private var topBarHeight: CGFloat = 110

    public init(store: AdminStore) {
        self.store = store
    }

    public var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    if let error = store.errorMessage {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(AdminTheme.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    switch section {
                    case .system: SystemSectionView(store: store)
                    case .modules: ModulesSectionView(store: store)
                    case .claude: ClaudeSectionView(store: store)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, topBarHeight + 8)
                .padding(.bottom, 24)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await store.refresh(section) }
            toolbar
        }
        // Polls only the visible section, and stops when the tab is left (the task is cancelled).
        .task(id: section) { await store.poll(section) }
        .sheet(item: $store.activeJob) { _ in
            DeployJobView(store: store)
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 600)
        #endif
    }

    private var toolbar: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Admin")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                HStack(spacing: 8) {
                    ForEach(AdminStore.Section.allCases, id: \.self) { item in
                        chip(for: item)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { topBarHeight = $0 }
    }

    private func chip(for item: AdminStore.Section) -> some View {
        Button {
            section = item
        } label: {
            Text(label(for: item))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(section == item ? .black : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .background(section == item ? Color.white : Color.white.opacity(0.1))
        .clipShape(Capsule())
    }

    private func label(for item: AdminStore.Section) -> String {
        switch item {
        case .system: return "Sistema"
        case .modules: return "Módulos"
        case .claude: return "Claude"
        }
    }
}
