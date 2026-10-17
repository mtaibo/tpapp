import Foundation
import TPCore

struct StoreFavorite: Codable, Identifiable, Equatable {
    let id: String
    let label: String
    let location: StoreLocation
    let path: String

    var folder: StoreFolder {
        StoreFolder(location: location, path: path, title: label)
    }
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

    func contains(_ folder: StoreFolder) -> Bool {
        favorites.contains { $0.id == Self.id(for: folder) }
    }

    func toggle(_ folder: StoreFolder) {
        let id = Self.id(for: folder)
        if favorites.contains(where: { $0.id == id }) {
            remove(id)
        } else {
            favorites.append(StoreFavorite(id: id, label: folder.title, location: folder.location, path: folder.path))
            save()
        }
    }

    func remove(_ id: String) {
        favorites.removeAll { $0.id == id }
        save()
    }

    private static func id(for folder: StoreFolder) -> String {
        "\(folder.location.rawValue):\(folder.path)"
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(favorites) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
