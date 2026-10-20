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
            StoreBrowseView(rootPath: rootPath, isAdmin: isAdmin, cache: cache, favorites: favorites)
                .navigationDestination(for: StoreFolder.self) { folder in
                    FolderView(folder: folder, storeClient: storeClient, cache: cache, favorites: favorites) { child in
                        path.append(child)
                    }
                }
        }
    }
}

/// The top of the Store tab, laid out like the Files app's Browse screen: collapsible
/// Favorites / Locations / Storage sections in rounded cards, with a large title. The
/// `.sidebar` list style is what gives sections their disclosure chevron on iPhone.
struct StoreBrowseView: View {
    let rootPath: String
    let isAdmin: Bool
    let cache: StoreDirectoryCache
    @ObservedObject var favorites: StoreFavoritesStore

    /// Plain `@State`, saved to `UserDefaults` on change: bound straight to `@AppStorage`, the
    /// change reached the list outside any animation and sections snapped open and shut.
    @State private var favoritesExpanded = Self.isExpanded("favorites")
    @State private var locationsExpanded = Self.isExpanded("locations")
    @State private var storageExpanded = Self.isExpanded("storage")

    var body: some View {
        List {
            Section("Favorites", isExpanded: $favoritesExpanded.animation(.smooth)) {
                ForEach(favorites.favorites) { favorite in
                    location(favorite.folder, label: favorite.label, systemImage: Self.symbol(forFavorite: favorite))
                        .swipeActions {
                            Button("Remove", systemImage: "star.slash") {
                                favorites.remove(favorite.id)
                            }
                            .tint(.orange)
                        }
                        .contextMenu {
                            Button("Remove from Favorites", systemImage: "star.slash") {
                                favorites.remove(favorite.id)
                            }
                        }
                }
                if favorites.favorites.isEmpty {
                    Text("Add a folder from its ••• menu to keep it here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Locations", isExpanded: $locationsExpanded.animation(.smooth)) {
                location(.home(rootPath), label: "Home", systemImage: "house")
                location(.shared, label: "Shared", systemImage: "person.2")
                if isAdmin {
                    location(.disk, label: "Disk", systemImage: "internaldrive")
                    location(.system, label: "System", systemImage: "server.rack")
                }
            }

            // Last, under everything else.
            if let disk = cache.disk {
                Section("Storage", isExpanded: $storageExpanded.animation(.smooth)) {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: Double(disk.used), total: Double(max(disk.total, 1)))
                        Text("\(formatBytes(disk.used)) of \(formatBytes(disk.total)) used")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: favoritesExpanded) { _, expanded in Self.setExpanded("favorites", expanded) }
        .onChange(of: locationsExpanded) { _, expanded in Self.setExpanded("locations", expanded) }
        .onChange(of: storageExpanded) { _, expanded in Self.setExpanded("storage", expanded) }
        .navigationTitle("Browse")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .task {
            await cache.refreshDisk()
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 480)
        #endif
    }

    private static func isExpanded(_ section: String) -> Bool {
        UserDefaults.standard.object(forKey: "store.browse.\(section)Expanded") as? Bool ?? true
    }

    private static func setExpanded(_ section: String, _ expanded: Bool) {
        UserDefaults.standard.set(expanded, forKey: "store.browse.\(section)Expanded")
    }

    private func location(_ folder: StoreFolder, label: String, systemImage: String) -> some View {
        NavigationLink(value: folder) {
            Label(label, systemImage: systemImage)
        }
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
