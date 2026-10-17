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
public struct StoreRootView: View {
    let storeClient: StoreClient
    let rootPath: String
    let isAdmin: Bool
    let resetSignal: Int

    @StateObject private var favorites = StoreFavoritesStore()
    @State private var path: [StoreFolder]

    public init(storeClient: StoreClient, rootPath: String, isAdmin: Bool = false, resetSignal: Int = 0) {
        self.storeClient = storeClient
        self.rootPath = rootPath
        self.isAdmin = isAdmin
        self.resetSignal = resetSignal
        _path = State(initialValue: [.home(rootPath)])
    }

    public var body: some View {
        NavigationStack(path: $path) {
            StoreBrowseView(storeClient: storeClient, rootPath: rootPath, isAdmin: isAdmin, favorites: favorites)
                .navigationDestination(for: StoreFolder.self) { folder in
                    FolderView(folder: folder, storeClient: storeClient, favorites: favorites)
                }
        }
        // Re-tapping the Store tab goes back to Home, wherever the stack currently is.
        .onChange(of: resetSignal) {
            path = [.home(rootPath)]
        }
    }
}

struct StoreBrowseView: View {
    let storeClient: StoreClient
    let rootPath: String
    let isAdmin: Bool
    @ObservedObject var favorites: StoreFavoritesStore

    @State private var disk: DiskInfo?

    var body: some View {
        List {
            Section("Locations") {
                NavigationLink(value: StoreFolder.home(rootPath)) {
                    Label("Home", systemImage: "house")
                }
                NavigationLink(value: StoreFolder.shared) {
                    Label("Shared", systemImage: "person.2")
                }
                if isAdmin {
                    NavigationLink(value: StoreFolder.disk) {
                        Label("Disk", systemImage: "internaldrive")
                    }
                    NavigationLink(value: StoreFolder.system) {
                        Label("System", systemImage: "server.rack")
                    }
                }
            }

            Section {
                ForEach(favorites.favorites) { favorite in
                    NavigationLink(value: favorite.folder) {
                        Label(favorite.label, systemImage: "folder")
                    }
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

            if let disk {
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
        .navigationTitle("Store")
        .task {
            disk = try? await storeClient.diskInfo()
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 480)
        #endif
    }
}
