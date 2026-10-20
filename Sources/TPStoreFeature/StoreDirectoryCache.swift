import Foundation
import Observation
import TPCore

/// Folder listings kept in memory for the whole Store tab, so a folder opens with its contents
/// already in place and slides in full instead of as a spinner that fills in afterwards.
///
/// Every listing is shown from here first and refreshed in the background (stale-while-revalidate),
/// and opening a folder also fetches its subfolders' listings ahead of time, which is what makes the
/// next tap instant — and what gives folder rows their "N items" count, like the Files app.
@MainActor
@Observable
final class StoreDirectoryCache {
    private let storeClient: StoreClient

    /// Keyed by location + path only: the same folder reached as a favorite or by browsing has a
    /// different title but the same contents.
    private struct Key: Hashable {
        let location: StoreLocation
        let path: String
        init(_ folder: StoreFolder) {
            location = folder.location
            path = folder.path
        }
    }

    private var listings: [Key: [FileEntry]] = [:]
    private(set) var disk: DiskInfo?

    @ObservationIgnored private var inFlight: [Key: Task<[FileEntry], Error>] = [:]
    @ObservationIgnored private var diskFetchedAt: Date?

    /// How many subfolders of an opened folder get prefetched, and how many requests at once.
    private static let prefetchLimit = 32
    private static let prefetchConcurrency = 4

    init(storeClient: StoreClient) {
        self.storeClient = storeClient
    }

    func entries(for folder: StoreFolder) -> [FileEntry]? {
        listings[Key(folder)]
    }

    /// Item count shown under a folder row, once its listing has been seen or prefetched.
    func itemCount(for folder: StoreFolder) -> Int? {
        listings[Key(folder)]?.count
    }

    /// Fetches a folder's listing, sharing a request already running for the same folder. The
    /// request isn't tied to the calling view, so leaving a folder mid-load still caches it.
    @discardableResult
    func load(_ folder: StoreFolder) async throws -> [FileEntry] {
        let key = Key(folder)
        if let task = inFlight[key] {
            return try await task.value
        }
        let storeClient = storeClient
        let task = Task {
            let listing = try await storeClient.listDirectory(path: folder.path, location: folder.location)
            return Self.sorted(listing.entries)
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        let entries = try await task.value
        if listings[key] != entries {
            listings[key] = entries
        }
        return entries
    }

    /// Loads the listings of the first few subfolders that aren't cached yet, a few at a time.
    func prefetchChildren(of folder: StoreFolder) async {
        guard let entries = listings[Key(folder)] else { return }
        let children = entries
            .filter(\.isDirectory)
            .map { folder.child($0.name) }
            .filter { listings[Key($0)] == nil && inFlight[Key($0)] == nil }
            .prefix(Self.prefetchLimit)

        await withTaskGroup(of: Void.self) { group in
            var pending = children.makeIterator()
            for _ in 0..<Self.prefetchConcurrency {
                guard let child = pending.next() else { break }
                group.addTask { _ = try? await self.load(child) }
            }
            while await group.next() != nil {
                guard !Task.isCancelled, let child = pending.next() else { continue }
                group.addTask { _ = try? await self.load(child) }
            }
        }
    }

    /// Disk usage changes slowly; one request a minute is plenty for every folder's ••• menu.
    func refreshDisk() async {
        if let diskFetchedAt, Date.now.timeIntervalSince(diskFetchedAt) < 60 { return }
        diskFetchedAt = .now
        if let fetched = try? await storeClient.diskInfo() {
            disk = fetched
        } else {
            diskFetchedAt = nil
        }
    }

    /// Whether dropping `item` on `folder` would move it anywhere: same storage location, not the
    /// folder it's already in, and not a folder into itself or one of its own subfolders.
    func canMove(_ item: StoreDragItem, into folder: StoreFolder) -> Bool {
        guard item.location == folder.location, item.parentPath != folder.path else { return false }
        if item.isDirectory, folder.path == item.path || folder.path.hasPrefix(item.path + "/") { return false }
        return true
    }

    /// Moves a dragged file or folder into `folder`, taking it out of its old listing right away
    /// and then refreshing both folders from the server.
    func move(_ item: StoreDragItem, into folder: StoreFolder) async throws {
        try await storeClient.move(path: item.path, destDir: folder.path, location: item.location)
        let source = StoreFolder(location: item.location, path: item.parentPath, title: "")
        let name = String(item.path.split(separator: "/").last ?? "")
        listings[Key(source)]?.removeAll { $0.name == name }
        if item.isDirectory { invalidate(source.child(name)) }
        async let refreshedSource: Void = refresh(source)
        async let refreshedTarget: Void = refresh(folder)
        _ = await (refreshedSource, refreshedTarget)
    }

    /// Reloads a folder only if it's cached; one nobody has opened yet loads when it's opened.
    private func refresh(_ folder: StoreFolder) async {
        guard listings[Key(folder)] != nil else { return }
        _ = try? await load(folder)
    }

    func remove(_ entry: FileEntry, from folder: StoreFolder) {
        listings[Key(folder)]?.removeAll { $0.id == entry.id }
        if entry.isDirectory { invalidate(folder.child(entry.name)) }
    }

    /// Drops a folder and everything cached under it, e.g. after it was renamed or deleted.
    func invalidate(_ folder: StoreFolder) {
        let prefix = folder.path + "/"
        for key in Array(listings.keys) where key.location == folder.location && (key.path == folder.path || key.path.hasPrefix(prefix)) {
            listings[key] = nil
        }
    }

    private nonisolated static func sorted(_ entries: [FileEntry]) -> [FileEntry] {
        entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
