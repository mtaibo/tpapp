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

struct StoreBrowseView: View {
    let rootPath: String
    let isAdmin: Bool
    let cache: StoreDirectoryCache
    @ObservedObject var favorites: StoreFavoritesStore

    var body: some View {
        List {
            Section {
                ForEach(favorites.favorites) { favorite in
                    location(favorite.folder, label: favorite.label, systemImage: "folder")
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
            } header: {
                Text("Favorites")
            } footer: {
                if favorites.favorites.isEmpty {
                    Text("Add a folder from its ••• menu to keep it here.")
                }
            }

            Section("Locations") {
                location(.home(rootPath), label: "Home", systemImage: "house")
                location(.shared, label: "Shared", systemImage: "person.2")
                if isAdmin {
                    location(.disk, label: "Disk", systemImage: "internaldrive")
                    location(.system, label: "System", systemImage: "server.rack")
                }
            }

            // Last, under everything else.
            if let disk = cache.disk {
                Section("Storage") {
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
        .navigationTitle("Browse")
        .task {
            await cache.refreshDisk()
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 480)
        #endif
    }

    private func location(_ folder: StoreFolder, label: String, systemImage: String) -> some View {
        NavigationLink(value: folder) {
            Label(label, systemImage: systemImage)
        }
    }
}
