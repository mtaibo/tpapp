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

    public init(client: PhotosClient) {
        self.client = client
    }

    public func reload() async {
        isLoading = true
        errorMessage = nil
        nextCursor = nil
        hasMore = true
        defer { isLoading = false }

        do {
            let page = try await client.list(filter: filter, cursor: nil)
            photos = page.items
            nextCursor = page.nextCursor
            hasMore = page.nextCursor != nil
        } catch {
            errorMessage = apiErrorMessage(error)
        }
    }

    public func loadMoreIfNeeded(currentItem: Photo) async {
        guard hasMore, !isLoadingMore, !isLoading else { return }
        guard let index = photos.firstIndex(where: { $0.id == currentItem.id }) else { return }
        guard index >= photos.count - 12 else { return }
        await loadMore()
    }

    private func loadMore() async {
        guard let cursor = nextCursor, hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await client.list(filter: filter, cursor: cursor)
            photos.append(contentsOf: page.items)
            nextCursor = page.nextCursor
            hasMore = page.nextCursor != nil
        } catch {
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
