import Foundation
import SwiftUI
import TPCore

struct StoreFavorite: Codable, Identifiable, Equatable {
    let id: String
    let label: String
    let location: StoreLocation
    let path: String
}

/// Mirrors tpstore web's `useFavourites.js`: client-side only, one list per device, no server sync.
@MainActor
final class StoreFavoritesStore: ObservableObject {
    @Published private(set) var favorites: [StoreFavorite] = []

    private static let storageKey = "tpcloud-favourites"

    init() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([StoreFavorite].self, from: data) else { return }
        favorites = decoded
    }

    func addCurrentFolder(location: StoreLocation, path: String, rootPath: String) {
        let id = "\(location.rawValue):\(path)"
        guard !favorites.contains(where: { $0.id == id }) else { return }
        favorites.append(StoreFavorite(id: id, label: favoriteLabel(location: location, path: path, rootPath: rootPath), location: location, path: path))
        save()
    }

    func remove(_ id: String) {
        favorites.removeAll { $0.id == id }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(favorites) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func favoriteLabel(location: StoreLocation, path: String, rootPath: String) -> String {
        if path.isEmpty { return location == .server ? "Server Root" : "Disk Root" }
        if location == .external, path == rootPath { return "Home" }
        guard let last = path.split(separator: "/").last.map(String.init) else { return path }
        if last == "shared" { return "Shared" }
        return last.prefix(1).uppercased() + last.dropFirst()
    }
}

/// macOS-only navigation sidebar, mirroring tpstore web's `Sidebar.vue` Favorites + Locations sections.
struct StoreSidebarView: View {
    @ObservedObject var favoritesStore: StoreFavoritesStore
    let rootPath: String
    let isAdmin: Bool
    let currentLocation: StoreLocation
    let currentPath: String
    let onNavigate: (StoreLocation, String) -> Void
    let onAddFavorite: () -> Void

    @State private var favoritesOpen = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            favoritesHeader
            if favoritesOpen {
                if favoritesStore.favorites.isEmpty {
                    Text("No favorites yet")
                        .font(.system(size: 12))
                        .foregroundStyle(TPStoreTheme.textMuted)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 6)
                } else {
                    ForEach(favoritesStore.favorites) { favorite in
                        favoriteRow(favorite)
                    }
                }
            }

            Text("LOCATIONS")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(TPStoreTheme.textMuted)
                .padding(.horizontal, 14)
                .padding(.top, 18)
                .padding(.bottom, 6)

            locationRow(label: "Share", systemImage: "person.2.fill", location: .external, path: "shared")
            locationRow(label: "Home", systemImage: "house.fill", location: .external, path: rootPath)

            if isAdmin {
                locationRow(label: "Disk", systemImage: "internaldrive.fill", location: .external, path: "")
                locationRow(label: "System", systemImage: "server.rack", location: .server, path: "")
            }

            Spacer()
        }
        .padding(.top, 14)
        .frame(width: 200)
        .background(Color(red: 0.067, green: 0.067, blue: 0.075))
    }

    private var favoritesHeader: some View {
        HStack {
            Text("FAVORITES")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(TPStoreTheme.textMuted)
            Spacer()
            Button(action: onAddFavorite) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TPStoreTheme.textMuted)
            }
            .buttonStyle(.plain)
            .help("Add current folder")
            Button {
                favoritesOpen.toggle()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TPStoreTheme.textMuted)
                    .rotationEffect(.degrees(favoritesOpen ? 90 : 0))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }

    private func favoriteRow(_ favorite: StoreFavorite) -> some View {
        FavoriteRow(
            favorite: favorite,
            isActive: favorite.location == currentLocation && favorite.path == currentPath,
            onNavigate: { onNavigate(favorite.location, favorite.path) },
            onRemove: { favoritesStore.remove(favorite.id) }
        )
    }

    private func locationRow(label: String, systemImage: String, location: StoreLocation, path: String) -> some View {
        SidebarRow(
            label: label,
            systemImage: systemImage,
            isActive: location == currentLocation && path == currentPath,
            action: { onNavigate(location, path) }
        )
    }
}

private struct FavoriteRow: View {
    let favorite: StoreFavorite
    let isActive: Bool
    let onNavigate: () -> Void
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .trailing) {
            SidebarRow(label: favorite.label, systemImage: "folder.fill", isActive: isActive, action: onNavigate)
            if isHovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(TPStoreTheme.textMuted)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10)
            }
        }
        .onHover { isHovering = $0 }
    }
}

private struct SidebarRow: View {
    let label: String
    let systemImage: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13))
                    .foregroundStyle(TPStoreTheme.accentGray)
                    .frame(width: 18)
                Text(label)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(TPStoreTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isActive ? Color.white.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
    }
}
