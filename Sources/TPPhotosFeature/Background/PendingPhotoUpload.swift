import Foundation
import TPCore

/// One photo's chunked upload in flight, persisted so a delegate callback firing after the app
/// was relaunched purely to drain background `URLSession` events — with none of the in-memory
/// state from before that relaunch — can still tell which chunks are already done and what to
/// register once the rest land. Keyed by checksum (`uploadId`), which is both globally unique per
/// (owner, content) and the same value the server's canonical filename is built from, so
/// re-planning the same photo across refills always reconnects to the same record instead of
/// starting a parallel one.
public struct PendingPhotoUpload: Codable, Equatable, Sendable {
    public let uploadId: String
    public let assetLocalIdentifier: String
    public let folderPath: String
    public let filename: String
    public let fileSize: Int
    public let chunkSize: Int
    public let totalChunks: Int
    public var completedChunks: Set<Int>
    public let tempFileURL: URL
    public let registration: PhotosClient.Registration

    public var isComplete: Bool { completedChunks.count >= totalChunks }

    public init(
        uploadId: String,
        assetLocalIdentifier: String,
        folderPath: String,
        filename: String,
        fileSize: Int,
        chunkSize: Int,
        totalChunks: Int,
        completedChunks: Set<Int> = [],
        tempFileURL: URL,
        registration: PhotosClient.Registration
    ) {
        self.uploadId = uploadId
        self.assetLocalIdentifier = assetLocalIdentifier
        self.folderPath = folderPath
        self.filename = filename
        self.fileSize = fileSize
        self.chunkSize = chunkSize
        self.totalChunks = totalChunks
        self.completedChunks = completedChunks
        self.tempFileURL = tempFileURL
        self.registration = registration
    }
}

/// Persisted record of chunk-upload progress, one entry per in-flight photo, surviving process
/// relaunch. An `actor` because background-session delegate callbacks for different chunks of
/// different photos can land concurrently on the delegate queue.
public actor PhotoUploadLedger {
    private let fileURL: URL
    private var cache: [String: PendingPhotoUpload]?

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            self.fileURL = base.appendingPathComponent("PhotoUploadLedger.json")
        }
    }

    public func activeUploads() -> [PendingPhotoUpload] {
        Array(load().values)
    }

    public func upload(for uploadId: String) -> PendingPhotoUpload? {
        load()[uploadId]
    }

    /// Inserts a freshly planned upload, unless one with the same id already exists — a photo
    /// already in flight keeps its recorded progress rather than being reset to zero chunks.
    public func beginOrResume(_ upload: PendingPhotoUpload) {
        var all = load()
        if all[upload.uploadId] == nil {
            all[upload.uploadId] = upload
            save(all)
        }
    }

    /// Returns the updated record, or nil if this id isn't tracked (e.g. it was already removed
    /// by a concurrent completion, or the ledger was cleared) — the caller treats that as "nothing
    /// more to do" rather than an error.
    @discardableResult
    public func markChunkComplete(uploadId: String, chunkIndex: Int) -> PendingPhotoUpload? {
        var all = load()
        guard var upload = all[uploadId] else { return nil }
        upload.completedChunks.insert(chunkIndex)
        all[uploadId] = upload
        save(all)
        return upload
    }

    /// Also deletes the local whole-file temp copy this upload was slicing chunks from — it's
    /// only needed while the upload is in flight.
    public func remove(uploadId: String) {
        var all = load()
        guard let upload = all.removeValue(forKey: uploadId) else { return }
        save(all)
        try? FileManager.default.removeItem(at: upload.tempFileURL)
    }

    private func load() -> [String: PendingPhotoUpload] {
        if let cache { return cache }
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: PendingPhotoUpload].self, from: data) else {
            cache = [:]
            return [:]
        }
        cache = decoded
        return decoded
    }

    private func save(_ all: [String: PendingPhotoUpload]) {
        cache = all
        guard let data = try? JSONEncoder().encode(all) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
