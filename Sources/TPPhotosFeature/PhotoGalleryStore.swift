import Foundation
import TPCore

/// The gallery's photo list. Like the Photos app, it shows what's stored on the device straight
/// away and syncs with the server in the background:
///
/// - Each filter's list is saved to disk, so opening the tab (or switching filter) shows the last
///   known photos instantly, with no network round trip.
/// - A sync pulls every page, but publishes once at the end (plus the first page when nothing was
///   on screen yet). Publishing after every page used to re-render the whole grid dozens of times
///   while it loaded.
/// - Once the list is in, any photo without an on-device thumbnail gets one downloaded in the
///   background.
@MainActor
public final class PhotoGalleryStore: ObservableObject {
    @Published public private(set) var photos: [Photo] = []
    /// True only while there's nothing to show yet; a sync behind an existing list is silent.
    @Published public private(set) var isLoading = false
    @Published public private(set) var isSyncing = false
    @Published public var errorMessage: String?
    @Published public var filter: PhotosClient.Filter = .all {
        didSet {
            guard oldValue != filter else { return }
            photos = []
            Task { await reload() }
        }
    }

    private let client: PhotosClient
    private var generation = 0
    private var thumbnailTask: Task<Void, Never>?
    private var tableTask: Task<Void, Never>?
    /// The server's maximum page size.
    private static let pageSize = 200

    public init(client: PhotosClient) {
        self.client = client
    }

    public func reload() async {
        generation += 1
        let myGeneration = generation
        let requestedFilter = filter
        thumbnailTask?.cancel()

        if photos.isEmpty {
            // Off the main thread: a big library's list is several megabytes of JSON.
            let cached = await Task.detached(priority: .userInitiated) { PhotoIndexCache.load(filter: requestedFilter) }.value
            guard myGeneration == generation else { return }
            if let cached {
                photos = cached
                fillThumbnailTable(cached)
            }
        }
        isLoading = photos.isEmpty
        isSyncing = true
        errorMessage = nil
        defer {
            if myGeneration == generation {
                isLoading = false
                isSyncing = false
            }
        }

        var all: [Photo] = []
        var cursor: String?
        do {
            repeat {
                let page = try await client.list(filter: requestedFilter, cursor: cursor, limit: Self.pageSize)
                guard myGeneration == generation else { return }
                all.append(contentsOf: page.items)
                cursor = page.nextCursor
                if photos.isEmpty {
                    photos = all
                    isLoading = false
                }
            } while cursor != nil
        } catch {
            guard myGeneration == generation else { return }
            // Keep showing the stored list; only report the error if there's nothing at all.
            if photos.isEmpty { errorMessage = apiErrorMessage(error) }
            return
        }

        if all != photos { photos = all }
        Task.detached(priority: .utility) { PhotoIndexCache.save(all, filter: requestedFilter) }

        fillThumbnailTable(all)
        let client = self.client
        thumbnailTask = Task.detached(priority: .utility) {
            await PhotoThumbnailCache.downloadMissing(all, client: client)
        }
    }

    /// Converts stored thumbnails into the grid's ready-to-draw table — started as soon as a list
    /// is on screen, not after a sync that may never come back (offline, server unreachable).
    private func fillThumbnailTable(_ photos: [Photo]) {
        tableTask?.cancel()
        tableTask = Task.detached(priority: .utility) {
            await PhotoThumbnailCache.fillTable(photos)
        }
    }

    public func delete(_ photo: Photo) async {
        do {
            try await client.delete(id: photo.id)
            photos.removeAll { $0.id == photo.id }
            let remaining = photos
            let filter = self.filter
            Task.detached(priority: .utility) { PhotoIndexCache.save(remaining, filter: filter) }
        } catch {
            errorMessage = apiErrorMessage(error)
        }
    }
}

/// Each filter's last synced photo list, as a file in Application Support.
enum PhotoIndexCache {
    private static func url(for filter: PhotosClient.Filter) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("PhotoIndex-\(filter.rawValue).json")
    }

    static func load(filter: PhotosClient.Filter) -> [Photo]? {
        guard let data = try? Data(contentsOf: url(for: filter)) else { return nil }
        return try? JSONDecoder().decode([Photo].self, from: data)
    }

    static func save(_ photos: [Photo], filter: PhotosClient.Filter) {
        guard let data = try? JSONEncoder().encode(photos) else { return }
        try? data.write(to: url(for: filter), options: .atomic)
    }
}
