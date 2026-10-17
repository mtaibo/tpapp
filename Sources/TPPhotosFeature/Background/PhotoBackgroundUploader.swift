#if os(iOS)
import Foundation
@preconcurrency import Photos
import TPCore

/// Drives photo backup uploads that keep making progress while the app is suspended or not
/// running at all. Unlike `PhotoSyncStore` (whole-file multipart uploads over the app's normal
/// ephemeral `URLSession`, alive only while the app has foreground or `beginBackgroundTask` grace
/// time), this hands each chunk to a `URLSessionConfiguration.background` session: the system's
/// own transfer daemon drives it to completion independently of this process and relaunches the
/// app briefly (`sessionSendsLaunchEvents`) to report completions. As long as the user doesn't
/// force-quit the app from the multitasking switcher, a multi-thousand-photo backup keeps
/// advancing without the app ever needing to be open.
///
/// Uploads are chunked to match the server's `/api/files/upload-chunk`, not whole-file: a
/// background upload task can only send a body `fromFile:`, and small, independently-retriable
/// chunks mean a network hiccup costs one chunk's bytes, not the whole photo.
///
/// The chain keeps itself going without waiting on opportunistic `BGProcessingTask` scheduling:
/// finishing the last chunk of a batch fires `urlSessionDidFinishEvents`, which immediately
/// enqueues the next batch before telling the system it can suspend the app again.
/// `PhotoBackupScheduler`'s `BGProcessingTask` only exists to jumpstart this loop if it ever goes
/// fully idle (first run after sign-in, or if the system ever drops every outstanding task).
public final class PhotoBackgroundUploader: NSObject, @unchecked Sendable {
    public static let shared = PhotoBackgroundUploader()

    /// Matches the server's offset-based chunk write granularity.
    static let chunkSize = 2 * 1024 * 1024

    /// How many not-yet-backed-up assets one refill pass extracts and enqueues. Kept small so a
    /// single wake (especially an events-only one, with a much tighter time budget than a
    /// `BGProcessingTask`) reliably finishes planning before being killed; a half-planned batch
    /// isn't corrupt, just incomplete, and the next wake continues where this one stopped.
    static let refillBatchSize = 12

    static let storeBaseURL = URL(string: "https://store.migueltaibo.com")!
    private static let backgroundSessionIdentifier = "com.migueltaibo.tpapp.photos.upload"
    private static let ownerEmailDefaultsKey = "PhotoBackgroundUploader.ownerEmail"

    private let ledger = PhotoUploadLedger()
    private var client: PhotosClient { PhotosClient(client: HTTPClient(baseURL: Self.storeBaseURL)) }

    private let stateLock = NSLock()
    private var responseBuffers: [Int: Data] = [:]
    private var isRefilling = false
    private var isPaused = false
    private var backgroundEventsCompletion: (() -> Void)?

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private override init() { super.init() }

    /// Idempotent; call early (app delegate launch) so a background launch that exists purely to
    /// deliver session events reconnects to the same session/delegate instead of silently
    /// dropping them because the lazy `session` was never touched.
    public func activate() { _ = session }

    public func handleEventsForBackgroundURLSession(completion: @escaping () -> Void) {
        stateLock.lock()
        backgroundEventsCompletion = completion
        stateLock.unlock()
        activate()
    }

    /// While a foreground "Backup now" run is uploading the same pending assets, planning new ones
    /// here would upload every photo twice. Chunks already enqueued keep going either way.
    public func setPaused(_ paused: Bool) {
        stateLock.lock()
        isPaused = paused
        stateLock.unlock()
    }

    public static func rememberSignedIn(ownerEmail: String) {
        UserDefaults.standard.set(ownerEmail, forKey: ownerEmailDefaultsKey)
    }

    public static func forgetSignedIn() {
        UserDefaults.standard.removeObject(forKey: ownerEmailDefaultsKey)
    }

    private static var rememberedOwnerEmail: String? {
        UserDefaults.standard.string(forKey: ownerEmailDefaultsKey)
    }

    /// Re-drives anything already planned (uploading its still-missing chunks, or registering it
    /// server-side if every chunk already landed but registration hasn't happened yet), then
    /// tops the active set back up to `refillBatchSize` with brand-new assets. Returns whether
    /// this call enqueued or finished anything, so callers (BGProcessingTask) can report real
    /// progress.
    ///
    /// Topping up always happens, regardless of how many uploads are still active — one asset
    /// that's stuck (a chunk that never completes, extraction that keeps failing) delays itself
    /// but must never be able to block the rest of a thousands-of-photos library from advancing,
    /// which an "only plan new assets once nothing is active" rule would do.
    ///
    /// Safe to call even while another `refill()` is still running — `isRefilling` makes the
    /// redundant call a no-op rather than double-planning the same batch (double-*uploading* a
    /// chunk would just be wasteful, not incorrect, since the server writes each chunk at a fixed
    /// offset — but there's no reason to pay that cost).
    @discardableResult
    public func refill() async -> Bool {
        guard beginRefill() else { return false }
        defer { endRefill() }

        guard let ownerEmail = Self.rememberedOwnerEmail else { return false }
        let authStatus = PhotoLibraryAuthorization.currentStatus
        guard authStatus == .authorized || authStatus == .limited else { return false }

        var madeProgress = false

        for upload in await ledger.activeUploads() {
            if upload.isComplete {
                if await finalize(upload) { madeProgress = true }
            } else {
                enqueueMissingChunks(for: upload)
                madeProgress = true
            }
        }

        // Re-read: `finalize()` above may have removed entries, freeing up room in the batch.
        let active = await ledger.activeUploads()
        let room = Self.refillBatchSize - active.count
        guard room > 0 else { return madeProgress }

        let scan = PhotoBackupPlanner.scanImageAssets()
        guard !scan.images.isEmpty else { return madeProgress }

        let knownIds: Set<String>
        do {
            knownIds = try await PhotoBackupPlanner.checkKnownAssetIds(scan.images.map(\.localIdentifier), client: client)
        } catch {
            return madeProgress
        }

        // Exclude assets already being planned/uploaded too — they're not yet "known" to the
        // server (not registered), so `knownIds` alone wouldn't filter them out, and re-extracting
        // an asset that's already in flight would just waste work.
        let activeAssetIds = Set(active.map(\.assetLocalIdentifier))
        let candidates = scan.images
            .filter { !knownIds.contains($0.localIdentifier) && !activeAssetIds.contains($0.localIdentifier) }
            .prefix(room)

        for asset in candidates {
            do {
                try await plan(asset: asset, ownerEmail: ownerEmail)
                madeProgress = true
            } catch {
                continue // one bad asset shouldn't block the rest of the batch
            }
        }
        return madeProgress
    }

    private func beginRefill() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !isRefilling, !isPaused else { return false }
        isRefilling = true
        return true
    }

    private func endRefill() {
        stateLock.lock()
        isRefilling = false
        stateLock.unlock()
    }

    /// Registers a photo whose chunks are all on disk server-side, and cleans up its ledger entry
    /// once that succeeds. `register` is safe to retry blindly: the server dedups by checksum.
    private func finalize(_ upload: PendingPhotoUpload) async -> Bool {
        do {
            _ = try await client.register(upload.registration)
        } catch {
            return false // retried on the next refill(); every chunk already landed, nothing to re-upload
        }
        if let asset = PHAsset.fetchAssets(withLocalIdentifiers: [upload.assetLocalIdentifier], options: nil).firstObject {
            await PhotoThumbnailCache.ensureThumbnail(for: asset, checksum: upload.uploadId)
        }
        await ledger.remove(uploadId: upload.uploadId)
        return true
    }

    private func plan(asset: PHAsset, ownerEmail: String) async throws {
        let metadata = try await PhotoMetadataExtractor.extract(from: asset)
        let folderPath = PhotoBackupPlanner.destinationFolder(for: metadata.takenAt, ownerEmail: ownerEmail)
        let filename = "\(metadata.checksum).\(PhotoBackupPlanner.fileExtension(for: metadata.originalFilename))"

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tpphotoupload-\(metadata.checksum)", isDirectory: false)
        try metadata.data.write(to: tempURL, options: .atomic)

        let totalChunks = max(1, (metadata.data.count + Self.chunkSize - 1) / Self.chunkSize)
        let registration = PhotosClient.Registration(
            path: "\(folderPath)/\(filename)",
            checksum: metadata.checksum,
            originalFilename: metadata.originalFilename,
            sourceAssetId: metadata.sourceAssetId,
            fileSize: metadata.fileSize,
            mimeType: metadata.mimeType,
            width: metadata.width,
            height: metadata.height,
            takenAt: metadata.takenAt?.tpISO8601,
            isScreenshot: metadata.isScreenshot,
            isCameraOriginal: metadata.isCameraOriginal,
            sourceType: metadata.sourceType,
            cameraMake: metadata.cameraMake,
            cameraModel: metadata.cameraModel,
            gpsLat: metadata.gpsLat,
            gpsLon: metadata.gpsLon
        )

        let upload = PendingPhotoUpload(
            uploadId: metadata.checksum,
            assetLocalIdentifier: metadata.sourceAssetId,
            folderPath: folderPath,
            filename: filename,
            fileSize: metadata.data.count,
            chunkSize: Self.chunkSize,
            totalChunks: totalChunks,
            tempFileURL: tempURL,
            registration: registration
        )
        await ledger.beginOrResume(upload)
        // beginOrResume() no-ops if this checksum was already tracked (e.g. a previous plan() got
        // this far but the app died before any chunk task was created) — fetch the possibly-older
        // record back so chunk enqueuing is driven by its actual completedChunks, not an empty set.
        if let current = await ledger.upload(for: upload.uploadId) {
            enqueueMissingChunks(for: current)
        }
    }

    private func enqueueMissingChunks(for upload: PendingPhotoUpload) {
        guard FileManager.default.fileExists(atPath: upload.tempFileURL.path) else { return }
        for index in 0..<upload.totalChunks where !upload.completedChunks.contains(index) {
            enqueueChunk(index, of: upload)
        }
    }

    private func enqueueChunk(_ index: Int, of upload: PendingPhotoUpload) {
        guard let handle = try? FileHandle(forReadingFrom: upload.tempFileURL) else { return }
        let offset = index * upload.chunkSize
        try? handle.seek(toOffset: UInt64(offset))
        let chunkData = (try? handle.read(upToCount: upload.chunkSize)) ?? Data()
        try? handle.close()
        guard !chunkData.isEmpty else { return }

        let chunkFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tpphotochunk-\(upload.uploadId)-\(index)", isDirectory: false)
        guard (try? chunkData.write(to: chunkFileURL, options: .atomic)) != nil else { return }

        var components = URLComponents(url: Self.storeBaseURL.appendingPathComponent("/api/files/upload-chunk"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "upload_id", value: upload.uploadId),
            URLQueryItem(name: "chunk_index", value: String(index)),
            URLQueryItem(name: "total_chunks", value: String(upload.totalChunks)),
            URLQueryItem(name: "chunk_size", value: String(upload.chunkSize)),
            URLQueryItem(name: "filename", value: upload.filename),
            URLQueryItem(name: "file_size", value: String(upload.fileSize)),
            URLQueryItem(name: "path", value: upload.folderPath),
            URLQueryItem(name: "location", value: "external"),
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("ios", forHTTPHeaderField: "X-TP-Client")

        let info = ChunkTaskInfo(uploadId: upload.uploadId, chunkIndex: index, chunkFileURL: chunkFileURL.path)
        let task = session.uploadTask(with: request, fromFile: chunkFileURL)
        task.taskDescription = Self.encode(info)
        task.resume()
    }

    private struct ChunkTaskInfo: Codable {
        let uploadId: String
        let chunkIndex: Int
        let chunkFileURL: String
    }

    private static func encode(_ info: ChunkTaskInfo) -> String? {
        guard let data = try? JSONEncoder().encode(info) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func decode(_ string: String?) -> ChunkTaskInfo? {
        guard let string, let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ChunkTaskInfo.self, from: data)
    }

    fileprivate func bufferResponse(_ data: Data, for taskIdentifier: Int) {
        stateLock.lock()
        responseBuffers[taskIdentifier, default: Data()].append(data)
        stateLock.unlock()
    }

    fileprivate func takeResponse(for taskIdentifier: Int) -> Data? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return responseBuffers.removeValue(forKey: taskIdentifier)
    }

    fileprivate func handleChunkTaskCompletion(_ task: URLSessionTask, error: Error?) {
        _ = takeResponse(for: task.taskIdentifier)
        guard let info = Self.decode(task.taskDescription) else { return }
        try? FileManager.default.removeItem(atPath: info.chunkFileURL)

        let statusCode = (task.response as? HTTPURLResponse)?.statusCode
        guard error == nil, let statusCode, (200..<300).contains(statusCode) else {
            return // left incomplete in the ledger; the next refill() re-enqueues this exact chunk
        }

        Task { [weak self] in
            guard let self else { return }
            guard let updated = await self.ledger.markChunkComplete(uploadId: info.uploadId, chunkIndex: info.chunkIndex) else { return }
            guard updated.isComplete else { return }
            _ = await self.finalize(updated)
        }
    }

    fileprivate func takeBackgroundEventsCompletion() -> (() -> Void)? {
        stateLock.lock()
        defer { stateLock.unlock() }
        let completion = backgroundEventsCompletion
        backgroundEventsCompletion = nil
        return completion
    }
}

extension PhotoBackgroundUploader: URLSessionDataDelegate {
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        bufferResponse(data, for: dataTask.taskIdentifier)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        handleChunkTaskCompletion(task, error: error)
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { [weak self] in
            guard let self else { return }
            _ = await self.refill() // try to keep the chain going before telling the system we're done
            self.takeBackgroundEventsCompletion()?()
        }
    }
}
#endif
