import SwiftUI
import TPCore
import TPUI

/// One folder in the store, as a value a `NavigationStack` can push.
struct StoreFolder: Hashable {
    static let sharedPath = "shared"

    let location: StoreLocation
    let path: String
    let title: String

    static func home(_ rootPath: String) -> StoreFolder {
        StoreFolder(location: .external, path: rootPath, title: "Home")
    }

    static let shared = StoreFolder(location: .external, path: sharedPath, title: "Shared")
    static let disk = StoreFolder(location: .external, path: "", title: "Disk")
    static let system = StoreFolder(location: .server, path: "", title: "System")

    /// The shared folder's root also lists every share link, on top of its subfolders.
    var isSharedRoot: Bool { location == .external && path == Self.sharedPath }

    func entryPath(_ name: String) -> String {
        path.isEmpty ? name : "\(path)/\(name)"
    }

    func child(_ name: String) -> StoreFolder {
        StoreFolder(location: location, path: entryPath(name), title: name)
    }
}

/// The Store tab: a Files-style stack that opens straight into the user's Home folder, with a
/// "Browse" level above it for Shared, favorites and (for admins) the raw disk and system roots.
/// Shared lives here now instead of in its own tab.
///
/// Re-tapping the Store tab is left to the system, which pops the stack to Browse like the Files
/// app does. This used to also push Home back on top in the same tap, and that push racing the
/// system's own pop could leave the stack with nothing on screen — a black page.
public struct StoreRootView: View {
    let storeClient: StoreClient
    let rootPath: String
    let isAdmin: Bool

    @StateObject private var favorites = StoreFavoritesStore()
    @State private var cache: StoreDirectoryCache
    @State private var path: [StoreFolder]

    public init(storeClient: StoreClient, rootPath: String, isAdmin: Bool = false) {
        self.storeClient = storeClient
        self.rootPath = rootPath
        self.isAdmin = isAdmin
        _cache = State(initialValue: StoreDirectoryCache(storeClient: storeClient))
        _path = State(initialValue: [.home(rootPath)])
    }

    public var body: some View {
        NavigationStack(path: $path) {
            StoreBrowseView(rootPath: rootPath, isAdmin: isAdmin, cache: cache, favorites: favorites) { folder in
                path.append(folder)
            }
                .navigationDestination(for: StoreFolder.self) { folder in
                    FolderView(folder: folder, storeClient: storeClient, cache: cache, favorites: favorites) { child in
                        path.append(child)
                    }
                }
        }
    }
}

/// The top of the Store tab, laid out like the Files app's Browse screen: collapsible
/// Favorites / Locations / Storage sections in rounded cards, under a large title.
///
/// Hand-built rather than a `List`: a list can only fade rows in and out when a section
/// collapses, while here the card folds up into its header and unfolds down from it. Being a
/// plain stack also lets the rows take dragged files (a `List` swallows drops on iOS).
struct StoreBrowseView: View {
    let rootPath: String
    let isAdmin: Bool
    let cache: StoreDirectoryCache
    @ObservedObject var favorites: StoreFavoritesStore
    /// Pushes a folder; used when a drag spring-loads one of the rows.
    let openFolder: (StoreFolder) -> Void

    /// Saved to `UserDefaults` on change, so each section stays the way it was left.
    @State private var favoritesExpanded = Self.isExpanded("favorites")
    @State private var locationsExpanded = Self.isExpanded("locations")
    @State private var storageExpanded = Self.isExpanded("storage")
    @State private var moveError: String?
    /// Whether the big "Browse" heading has scrolled up under the bar, to show the small one.
    @State private var isHeadingHidden = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Drawn here rather than as the system large title, which iOS places noticeably
                // lower under the bar with no way to nudge it up.
                Text("Browse")
                    .font(.largeTitle.weight(.bold))
                    .padding(.horizontal, 4)
                    .accessibilityAddTraits(.isHeader)

                BrowseSection("Favorites", isExpanded: $favoritesExpanded) {
                    if favorites.favorites.isEmpty {
                        Text("Add a folder from its ••• menu or by holding it to keep it here.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(favorites.favorites) { favorite in
                        row(favorite.folder, label: favorite.label, systemImage: Self.symbol(forFavorite: favorite), isLast: favorite.id == favorites.favorites.last?.id)
                            .swipeActions {
                                Button("Remove", systemImage: "star.slash") {
                                    withAnimation { favorites.remove(favorite.id) }
                                }
                                .tint(.orange)
                            }
                            .contextMenu {
                                Button("Remove from Favorites", systemImage: "star.slash") {
                                    withAnimation { favorites.remove(favorite.id) }
                                }
                            }
                    }
                }

                BrowseSection("Locations", isExpanded: $locationsExpanded) {
                    row(.home(rootPath), label: "Home", systemImage: "house", isLast: false)
                    row(.shared, label: "Shared", systemImage: "person.2", isLast: !isAdmin)
                    if isAdmin {
                        row(.disk, label: "Disk", systemImage: "internaldrive", isLast: false)
                        row(.system, label: "System", systemImage: "server.rack", isLast: true)
                    }
                }

                // Last, under everything else.
                if let disk = cache.disk {
                    BrowseSection("Storage", isExpanded: $storageExpanded) {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: Double(disk.used), total: Double(max(disk.total, 1)))
                            Text("\(formatBytes(disk.used)) of \(formatBytes(disk.total)) used")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .swipeActionsContainer()
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 34
        } action: { _, hidden in
            withAnimation(.easeInOut(duration: 0.2)) { isHeadingHidden = hidden }
        }
        // Still set, for the back button ("< Browse") of the folders pushed from here.
        .navigationTitle("Browse")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Browse")
                    .font(.headline)
                    .opacity(isHeadingHidden ? 1 : 0)
                    .accessibilityHidden(!isHeadingHidden)
            }
        }
        .onChange(of: favoritesExpanded) { _, expanded in Self.setExpanded("favorites", expanded) }
        .onChange(of: locationsExpanded) { _, expanded in Self.setExpanded("locations", expanded) }
        .onChange(of: storageExpanded) { _, expanded in Self.setExpanded("storage", expanded) }
        .errorAlert($moveError)
        .task {
            await cache.refreshDisk()
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 480)
        #endif
    }

    /// One row of a card: tinted symbol, name, chevron, and a separator under it that starts at
    /// the name, like the Files app. Takes dragged items and opens when a drag lingers on it.
    private func row(_ folder: StoreFolder, label: String, systemImage: String, isLast: Bool) -> some View {
        NavigationLink(value: folder) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 30)
                Text(label)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(.rect)
        }
        .buttonStyle(BrowseRowButtonStyle())
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider().padding(.leading, 20 + 30 + 16)
            }
        }
        .folderDropTarget(folder, cache: cache, springLoad: { openFolder(folder) }) { moveError = $0 }
    }

    private static func isExpanded(_ section: String) -> Bool {
        UserDefaults.standard.object(forKey: "store.browse.\(section)Expanded") as? Bool ?? true
    }

    private static func setExpanded(_ section: String, _ expanded: Bool) {
        UserDefaults.standard.set(expanded, forKey: "store.browse.\(section)Expanded")
    }

    /// A favorite wears the same glyph its folder gets in the Files-style icon (Downloads,
    /// Documents…), or a plain folder.
    private static func symbol(forFavorite favorite: StoreFavorite) -> String {
        if favorite.location == .external, favorite.path.split(separator: "/").count == 2, favorite.path.hasPrefix("users/") {
            return "house"
        }
        return FolderIcon.glyph(forFolderNamed: favorite.label) ?? "folder"
    }
}

/// A Files-style collapsible section: a bold header with a chevron, over a rounded card that
/// slides up behind the header when folded and back down out of it when unfolded.
private struct BrowseSection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content

    init(_ title: String, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.title = title
        _isExpanded = isExpanded
        self.content = content()
    }

    private static var cardCornerRadius: CGFloat { 26 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.35)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .padding(.horizontal, 20)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            VStack(spacing: 0) {
                content
            }
            .background(browseCardBackground, in: .rect(cornerRadius: Self.cardCornerRadius))
            .clipShape(.rect(cornerRadius: Self.cardCornerRadius))
            // The card always keeps its full height (so its rows never squash), pinned to the
            // bottom of a window that shrinks to nothing under the header: folding slides the
            // whole card up behind the title, and unfolding slides it back down out of it.
            .fixedSize(horizontal: false, vertical: true)
            .frame(height: isExpanded ? nil : 0, alignment: .bottom)
            .clipped()
            // Clipping only hides the folded card: its rows would still take taps (and drops)
            // in the gap between the headers.
            .allowsHitTesting(isExpanded)
            .accessibilityHidden(!isExpanded)
        }
    }
}

private var browseCardBackground: Color {
    #if os(iOS)
    Color(uiColor: .secondarySystemGroupedBackground)
    #else
    Color(nsColor: .controlBackgroundColor)
    #endif
}

/// The pressed look of a card row: the gray wash a list row gets when tapped. Opaque card color
/// otherwise, so a favorite's swipe actions stay hidden under the row until it slides.
private struct BrowseRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(browseCardBackground)
            .overlay {
                if configuration.isPressed {
                    Rectangle().fill(.fill.tertiary)
                }
            }
    }
}
