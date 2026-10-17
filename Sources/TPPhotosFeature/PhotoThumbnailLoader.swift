import CoreGraphics
import TPCore

/// Shares one in-flight load per thumbnail between the grid's cells and its prefetcher, and
/// cancels it — download included — once nothing on or near the screen still wants it. Fast
/// scrolling past thousands of never-seen photos would otherwise queue thousands of downloads.
@MainActor
final class PhotoThumbnailLoader {
    /// A claim on one load, handed back to `release(_:)` when it's no longer wanted.
    struct Ticket {
        let key: String
        let generation: Int
        let task: Task<CGImage?, Never>
    }

    private struct Entry {
        let generation: Int
        let task: Task<CGImage?, Never>
        var interest: Int
    }

    private let client: PhotosClient
    private var entries: [String: Entry] = [:]
    private var nextGeneration = 0

    init(client: PhotosClient) {
        self.client = client
    }

    func request(_ photo: Photo, pixels: Int) -> Ticket {
        let key = "\(photo.checksum)-\(pixels)"
        if var entry = entries[key] {
            entry.interest += 1
            entries[key] = entry
            return Ticket(key: key, generation: entry.generation, task: entry.task)
        }
        nextGeneration += 1
        let generation = nextGeneration
        let client = self.client
        let task = Task<CGImage?, Never> { [weak self] in
            let image = await PhotoThumbnailCache.cgImage(for: photo, pixels: pixels, client: client)
            // Done: later requests hit the memory cache instead.
            if self?.entries[key]?.generation == generation { self?.entries[key] = nil }
            return image
        }
        entries[key] = Entry(generation: generation, task: task, interest: 1)
        return Ticket(key: key, generation: generation, task: task)
    }

    func release(_ ticket: Ticket) {
        // A ticket for a load that already finished (or was replaced) has nothing left to cancel.
        guard var entry = entries[ticket.key], entry.generation == ticket.generation else { return }
        entry.interest -= 1
        if entry.interest > 0 {
            entries[ticket.key] = entry
        } else {
            entry.task.cancel()
            entries[ticket.key] = nil
        }
    }
}
