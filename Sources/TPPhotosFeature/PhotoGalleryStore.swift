import Foundation
import TPCore

@MainActor
public final class PhotoGalleryStore: ObservableObject {
    @Published public private(set) var photos: [Photo] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var isLoadingMore = false
    @Published public var errorMessage: String?
    @Published public var filter: PhotosClient.Filter = .all {
        didSet {
            guard oldValue != filter else { return }
            Task { await reload() }
        }
    }

    private let client: PhotosClient
    private var nextCursor: String?
    private var hasMore = true
    private var generation = 0
    private var backgroundFetchTask: Task<Void, Never>?

    public init(client: PhotosClient) {
        self.client = client
    }

    public func reload() async {
        // Cancel any in-flight background drain unconditionally — not just on filter change —
        // since "Backup now"/"Check" call reload() directly for the *same* filter while a prior
        // drain may still be running; without this, a stale page from the old drain could land
        // after this reload has already reset nextCursor/hasMore/photos.
        backgroundFetchTask?.cancel()
        generation += 1
        let myGeneration = generation
        let requestedFilter = filter
        isLoading = true
        errorMessage = nil
        nextCursor = nil
        hasMore = true
        defer { isLoading = false }

        do {
            let page = try await client.list(filter: requestedFilter, cursor: nil)
            guard myGeneration == generation else { return }
            photos = page.items
            nextCursor = page.nextCursor
            hasMore = page.nextCursor != nil
            if hasMore {
                backgroundFetchTask = Task { [weak self] in
                    await self?.drainRemainingPages(generation: myGeneration)
                }
            }
        } catch {
            guard myGeneration == generation else { return }
            hasMore = false // nothing left to retry without a cursor until the next reload()
            errorMessage = apiErrorMessage(error)
        }
    }

    /// Runs after every successful reload(), independent of scrolling/onAppear, until hasMore is
    /// false — this is what guarantees the full list is always reached, not viewport timing.
    /// Metadata-only pages (no image bytes): a plain sequential loop with no artificial delay is
    /// fine, each iteration already waits on a real network round trip.
    private func drainRemainingPages(generation myGeneration: Int) async {
        while !Task.isCancelled, myGeneration == generation, hasMore {
            let cursorBeforeFetch = nextCursor
            await loadMore()
            guard myGeneration == generation else { return }
            if nextCursor == cursorBeforeFetch {
                // loadMore() made no progress (errorMessage already set) — stop instead of
                // spinning; a later onAppear-triggered loadMoreIfNeeded can still retry.
                break
            }
        }
    }

    /// Optional optimization only: completeness no longer depends on this firing — the
    /// background drain started by reload() guarantees the full list is reached regardless of
    /// scrolling. This just lets a near-bottom scroll nudge a fetch sooner than the drain would
    /// get to it on its own.
    private static let prefetchWindow = 40

    public func loadMoreIfNeeded(currentIndex index: Int) async {
        guard hasMore, !isLoadingMore, !isLoading else { return }
        guard index >= photos.count - Self.prefetchWindow else { return }
        await loadMore()
    }

    private func loadMore() async {
        guard let cursor = nextCursor, hasMore, !isLoadingMore else { return }
        let myGeneration = generation
        let requestedFilter = filter
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await client.list(filter: requestedFilter, cursor: cursor)
            guard myGeneration == generation else { return }
            photos.append(contentsOf: page.items)
            nextCursor = page.nextCursor
            hasMore = page.nextCursor != nil
        } catch {
            guard myGeneration == generation else { return }
            errorMessage = apiErrorMessage(error)
        }
    }

    public func delete(_ photo: Photo) async {
        do {
            try await client.delete(id: photo.id)
            photos.removeAll { $0.id == photo.id }
        } catch {
            errorMessage = apiErrorMessage(error)
        }
    }
}
