import SwiftUI

public struct HomeRootView: View {
    @ObservedObject var store: HomeStore
    @State private var section: Section = .blueprint

    private enum Section: CaseIterable, Hashable {
        case blueprint, blinds

        var title: String {
            switch self {
            case .blueprint: return "Blueprint"
            case .blinds: return "Blinds"
            }
        }

        var icon: String {
            switch self {
            case .blueprint: return "square.grid.3x3.fill"
            case .blinds: return "blinds.horizontal.closed"
            }
        }
    }

    private static let accent = Color(red: 0 / 255, green: 122 / 255, blue: 255 / 255)
    private static let sidebarBackground = Color(red: 17 / 255, green: 17 / 255, blue: 19 / 255)
    private static let activePill = Color(white: 0.11)

    public init(store: HomeStore) {
        self.store = store
    }

    public var body: some View {
        #if os(iOS)
        ZStack(alignment: .top) {
            content
            sectionMenu
        }
        .background(Color.black.ignoresSafeArea())
        .colorScheme(.dark)
        #else
        HStack(spacing: 0) {
            sidebar
            content
        }
        .background(Color.black.ignoresSafeArea())
        .colorScheme(.dark)
        #endif
    }

    private var content: some View {
        VStack(spacing: 0) {
            if let loadError = store.loadError {
                HStack {
                    Text(loadError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Retry") { Task { await store.refresh() } }
                }
                .padding()
            }

            switch section {
            case .blueprint: BlueprintView(store: store)
            case .blinds: BlindsSectionView(store: store)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    #if os(iOS)
    /// iOS has no room for the macOS sidebar, so the map/section picker collapses into
    /// a single Store-style "..." glass button (top-trailing) with a checkmarked list
    /// of sections inside -- new sections just need a new `Section` case, no UI changes.
    private var sectionMenu: some View {
        GlassEffectContainer {
            HStack {
                Spacer()
                Menu {
                    Picker("Section", selection: $section) {
                        ForEach(Section.allCases, id: \.self) { item in
                            Label(item.title, systemImage: item.icon).tag(item)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                }
                .menuIndicator(.hidden)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Change section")
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
        }
    }
    #endif

    /// Mirrors tphome's `Sidebar.vue`/`NavButton.vue`: dark panel (`#111113`), accent-colored icon
    /// regardless of selection, active row highlighted with a `#1c1c1e` rounded pill and bold label.
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Section.allCases, id: \.self) { item in
                Button {
                    section = item
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: item.icon)
                            .font(.system(size: 18))
                            .foregroundStyle(Self.accent)
                            .frame(width: 20, height: 20)
                        Text(item.title)
                            .font(.system(size: 14, weight: section == item ? .bold : .medium))
                            .foregroundStyle(.white)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .background(section == item ? Self.activePill : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: 240, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Self.sidebarBackground)
    }
}
