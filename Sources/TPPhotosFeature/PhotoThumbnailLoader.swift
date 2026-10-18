import CoreGraphics
import Foundation
import TPCore

/// Schedules the grid's thumbnail loads so the tiles on screen always come first.
///
/// Each load used to be its own task, all started at once: a fast fling queued hundreds of disk
/// reads (and downloads) for tiles already gone, none of them checked for cancellation before
/// starting, and the tiles actually on screen waited behind them. Now:
///
/// - loads wait in a queue and only a few run at a time; the next one picked is the most urgent
///   (tiles on screen before look-ahead) and, within that, the newest request — where the user
///   is now, not where they were half a second ago;
/// - a load nobody wants any more is dropped before it starts, or cancelled (download included)
///   if it's running;
/// - reading a stored thumbnail and downloading a missing one run in separate lanes, so a slow
///   network request never holds up thumbnails that are already on the phone.
@MainActor
final class PhotoThumbnailLoader {
    enum Priority: Int, Comparable {
        /// Ahead of the scroll, not on screen yet.
        case lookahead
        /// A tile on screen.
        case visible

        static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// A claim on one load, handed back to `release(_:)` when it's no longer wanted.
    struct Ticket: Hashable {
        let key: String
        let id: Int
    }

    private final class Job {
        let id: Int
        let photo: Photo
        let pixels: Int
        var priority: Priority
        var sequence: Int
        var waiters: [Int: (CGImage?) -> Void] = [:]
        var task: Task<Void, Never>?

        init(id: Int, photo: Photo, pixels: Int, priority: Priority, sequence: Int) {
            self.id = id
            self.photo = photo
            self.pixels = pixels
            self.priority = priority
            self.sequence = sequence
        }
    }

    private let client: PhotosClient
    private var jobs: [String: Job] = [:]
    private var waitingToRead: [String] = []
    private var waitingToDownload: [String] = []
    private var reading = 0
    private var downloading = 0
    private var nextID = 0
    /// Disk reads are fast but CPU-bound (decoding); a couple fewer than the cores keeps the main
    /// thread free to scroll.
    private let maxReads = max(ProcessInfo.processInfo.activeProcessorCount - 2, 2)
    private let maxDownloads = 4

    init(client: PhotosClient) {
        self.client = client
    }

    /// Calls `completion` on the main thread with the image, or `nil` if it couldn't be loaded.
    /// It's never called after the ticket is released.
    func request(_ photo: Photo, pixels: Int, priority: Priority, completion: @escaping (CGImage?) -> Void) -> Ticket {
        let key = "\(photo.checksum)-\(pixels)"
        nextID += 1
        let ticket = Ticket(key: key, id: nextID)
        if let job = jobs[key] {
            job.waiters[ticket.id] = completion
            job.priority = max(job.priority, priority)
            job.sequence = nextID
        } else {
            let job = Job(id: nextID, photo: photo, pixels: pixels, priority: priority, sequence: nextID)
            job.waiters[ticket.id] = completion
            jobs[key] = job
            // A dropped job's key can still be queued; don't let it start this one twice.
            waitingToRead.removeAll { $0 == key }
            waitingToDownload.removeAll { $0 == key }
            waitingToRead.append(key)
            pump()
        }
        return ticket
    }

    func release(_ ticket: Ticket) {
        guard let job = jobs[ticket.key], job.waiters.removeValue(forKey: ticket.id) != nil, job.waiters.isEmpty else { return }
        // Nobody wants it any more: drop it if it's still queued, stop it if it's running.
        jobs[ticket.key] = nil
        job.task?.cancel()
    }

    // MARK: Scheduling

    private func pump() {
        while reading < maxReads, let key = takeMostUrgent(from: &waitingToRead) {
            if let job = jobs[key], job.task == nil { startReading(job, key: key) }
        }
        while downloading < maxDownloads, let key = takeMostUrgent(from: &waitingToDownload) {
            if let job = jobs[key], job.task == nil { startDownloading(job, key: key) }
        }
    }

    /// Removes and returns the queued key whose job is most urgent, skipping ones already dropped.
    private func takeMostUrgent(from queue: inout [String]) -> String? {
        queue.removeAll { jobs[$0] == nil }
        guard let index = queue.indices.max(by: { isLessUrgent(queue[$0], than: queue[$1]) }) else { return nil }
        return queue.remove(at: index)
    }

    private func isLessUrgent(_ lhs: String, than rhs: String) -> Bool {
        guard let a = jobs[lhs], let b = jobs[rhs] else { return false }
        return (a.priority, a.sequence) < (b.priority, b.sequence)
    }

    private func startReading(_ job: Job, key: String) {
        reading += 1
        let photo = job.photo
        let pixels = job.pixels
        let jobID = job.id
        job.task = Task.detached(priority: .userInitiated) { [weak self] in
            let image = Task.isCancelled ? nil : PhotoThumbnailCache.storedCGImage(for: photo, pixels: pixels)
            await self?.finishedReading(key: key, jobID: jobID, image: image)
        }
    }

    private func finishedReading(key: String, jobID: Int, image: CGImage?) {
        reading -= 1
        defer { pump() }
        guard let job = jobs[key], job.id == jobID else { return }
        if let image {
            deliver(image, for: job, key: key)
        } else {
            // Not on this phone yet: queue it for the download lane.
            job.task = nil
            waitingToDownload.append(key)
        }
    }

    private func startDownloading(_ job: Job, key: String) {
        downloading += 1
        let photo = job.photo
        let pixels = job.pixels
        let jobID = job.id
        let client = self.client
        job.task = Task.detached(priority: .userInitiated) { [weak self] in
            let image = Task.isCancelled ? nil : await PhotoThumbnailCache.downloadedCGImage(for: photo, pixels: pixels, client: client)
            await self?.finishedDownloading(key: key, jobID: jobID, image: image)
        }
    }

    private func finishedDownloading(key: String, jobID: Int, image: CGImage?) {
        downloading -= 1
        defer { pump() }
        guard let job = jobs[key], job.id == jobID else { return }
        deliver(image, for: job, key: key)
    }

    private func deliver(_ image: CGImage?, for job: Job, key: String) {
        jobs[key] = nil
        for completion in job.waiters.values { completion(image) }
    }
}
