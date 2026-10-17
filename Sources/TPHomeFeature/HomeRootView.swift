import SwiftUI
import TPUI

public struct HomeRootView: View {
    @ObservedObject var store: HomeStore
    @AppStorage("home.section") private var section: Section = .blueprint

    private enum Section: String, CaseIterable, Hashable {
        case blueprint, blinds

        var title: String {
            switch self {
            case .blueprint: return "Blueprint"
            case .blinds: return "Blinds"
            }
        }
    }

    public init(store: HomeStore) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            Group {
                switch section {
                case .blueprint: BlueprintView(store: store)
                case .blinds: BlindsSectionView(store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
            .safeAreaInset(edge: .top) {
                if let loadError = store.loadError {
                    LoadErrorBanner(message: loadError) {
                        Task { await store.refresh() }
                    }
                }
            }
            .navigationTitle(section.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                // Same segmented switcher on iPhone, iPad and Mac — the old macOS-only sidebar
                // and iOS-only "…" menu are gone.
                ToolbarItem(placement: .principal) {
                    Picker("Section", selection: $section.animation(.snappy)) {
                        ForEach(Section.allCases, id: \.self) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
            .errorAlert($store.commandError, title: "Command Failed")
        }
        // The floor plan is thin white line art designed for a black background.
        .preferredColorScheme(.dark)
    }
}

private struct LoadErrorBanner: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Retry", action: onRetry)
                .buttonStyle(.glass)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding(.horizontal)
    }
}
