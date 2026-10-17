import Foundation
import os
import Photos
import TPCore
#if os(iOS)
import UIKit
#endif

@MainActor
public final class PhotoSyncStore: ObservableObject {
    @Published public private(set) var isRunning = false
    /// Successfully uploaded assets in the current/last run.
    @Published public private(set) var progressCompleted = 0
    /// Assets that failed in the current/last run — kept separate from `progressCompleted` so
    /// a run full of failures doesn't read as "100% done".
    @Published public private(set) var progressFailed = 0
    @Published public private(set) var progressTotal = 0
    /// Why each of `progressFailed` failed, grouped by human-readable reason — the count alone
    /// gave no way to tell an iCloud download stall from a dropped connection.
    @Published public private(set) var failureReasons: [String: Int] = [:]
    /// v1 backs up stills only; videos found during the scan are counted here so the UI can
    /// say "N videos not included" instead of silently never mentioning them.
    @Published public private(set) var excludedVideoCount = 0
    @Published public private(set) var lastError: String?
    /// Set alongside `lastError` specifically when the failure was the Photos permission being
    /// denied/restricted — the only case where the fix is "go change it in Settings", not retry.
    @Published public private(set) var permissionDenied = false
    @Published public private(set) var lastBackupAt: Date?

    @Published public private(set) var isSanitizing = false
    @Published public private(set) var lastSanitizeMessage: String?

    @Published public private(set) var isChecking = false
    @Published public private(set) var lastCheckMessage: String?

    public var progressDone: Int { progressCompleted + progressFailed }

    public var progressFraction: Double {
        guard progressTotal > 0 else { return 0 }
        return Double(progressDone) / Double(progressTotal)
    }

    public var progressLabel: String {
        var label = "\(progressDone)/\(progressTotal)"
        if progressFailed > 0 { label += " · \(progressFailed) failed" }
        if excludedVideoCount > 0 { label += " · \(excludedVideoCount) video(s) skipped" }
        return label
    }

    private let client: PhotosClient
    /// Bounded in-flight uploads: high enough to overlap network/iCloud-download latency across
    /// assets (the old strictly-serial loop was the main source of "backup is very slow"),
    /// low enough not to flood the server or the device's network queue.
    private let maxConcurrentUploads = 4
    /// Set when iOS stops the background run of `backupNow()`, so it stops starting new uploads.
    /// A property rather than a local: the expiration callback that sets it escapes the run.
    private var stopRequested = false

    /// Total tries for each network step of one photo. Transient failures (a connection the
    /// iPhone dropped mid-upload, a 5xx from the gateway) are common over a long backup and
    /// usually succeed on the next try, so they shouldn't count as a failed photo straight away.
    private static let networkAttempts = 3

    private static let logger = Logger(subsystem: "com.migueltaibo.tpapp", category: "PhotoBackup")

    public init(client: PhotosClient) {
        self.client = client
    }

    #if os(iOS)
    /// Backup/check runs do real network uploads that can easily outlast the few seconds iOS
    /// gives a backgrounded app before suspending it — without this, locking the screen or
    /// switching apps mid-run silently kills the task, which is why backups never seemed to
    /// finish. `beginBackgroundTask` buys extra time to let in-flight work land; disabling the
    /// idle timer additionally stops the screen from auto-locking while the run is in the
    /// foreground. Long unattended runs are kept alive by `PhotoBackupContinuedTask`; this
    /// remains as the fallback when the system declines that request.
    private func beginBackgroundExecution(name: String) -> () -> Void {
        var taskID: UIBackgroundTaskIdentifier = .invalid
        taskID = UIApplication.shared.beginBackgroundTask(withName: name) {
            UIApplication.shared.endBackgroundTask(taskID)
            taskID = .invalid
        }
        UIApplication.shared.isIdleTimerDisabled = true
        return {
            if taskID != .invalid { UIApplication.shared.endBackgroundTask(taskID) }
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
    #endif

    /// v1's whole sync strategy: rescan the full library every run and let `check-existing`
    /// skip known assets. Simple, with no local sync-state that could drift from the server.
    public func backupNow(ownerEmail: String) async {
        guard !isRunning else { return }
        isRunning = true
        lastError = nil
        permissionDenied = false
        progressCompleted = 0
        progressFailed = 0
        progressTotal = 0
        failureReasons = [:]
        excludedVideoCount = 0
        defer { isRunning = false }

        stopRequested = false

        #if os(iOS)
        let endBackgroundExecution = beginBackgroundExecution(name: "PhotoBackup")
        defer { endBackgroundExecution() }

        PhotoBackgroundUploader.shared.setPaused(true)
        defer { PhotoBackgroundUploader.shared.setPaused(false) }

        let continuedTask = PhotoBackupContinuedTask()
        continuedTask.start(onExpire: { [weak self] in self?.stopRequested = true })
        defer { continuedTask.finish(success: lastError == nil) }
        #endif

        let status = await PhotoLibraryAuthorization.requestReadOnlyAccess()
        guard status == .authorized || status == .limited else {
            lastError = "No access to the photo library"
            permissionDenied = true
            return
        }

        let scan = PhotoBackupPlanner.scanImageAssets()
        excludedVideoCount = scan.excludedVideoCount
        guard !scan.images.isEmpty else { return }

        let knownIds: Set<String>
        do {
            knownIds = try await PhotoBackupPlanner.checkKnownAssetIds(scan.images.map(\.localIdentifier), client: client)
        } catch {
            lastError = "Couldn't check which photos are already backed up"
            return
        }

        let pending = scan.images.filter { !knownIds.contains($0.localIdentifier) }
        progressTotal = pending.count
        #if os(iOS)
        continuedTask.update(completed: 0, total: progressTotal)
        #endif

        // Bounded-concurrency pool instead of one-at-a-time: each in-flight upload still goes
        // through `backup(asset:ownerEmail:)` in order pulled from `pending` (already date-sorted),
        // so overall progress stays close to date order while up to `maxConcurrentUploads` network
        // round-trips overlap.
        var sessionExpired = false
        // Local mirror of `stopRequested`: `enqueueNext()` below isn't main-actor isolated, so it
        // can't read the property itself. Synced in the results loop, which is.
        var stopping = false
        await withTaskGroup(of: Result<Void, Error>.self) { group in
            var iterator = pending.makeIterator()

            func enqueueNext() {
                guard !sessionExpired, !stopping, let asset = iterator.next() else { return }
                group.addTask {
                    do {
                        try await self.backup(asset: asset, ownerEmail: ownerEmail)
                        return .success(())
                    } catch {
                        return .failure(error)
                    }
                }
            }

            for _ in 0..<maxConcurrentUploads {
                enqueueNext()
            }

            for await result in group {
                switch result {
                case .success:
                    progressCompleted += 1
                case .failure(APIError.sessionExpired):
                    // The whole batch would fail the same way from here on — stop enqueueing new
                    // uploads (in-flight ones are left to finish) instead of silently burning
                    // through the rest of the library as individual failures.
                    if !sessionExpired {
                        sessionExpired = true
                        lastError = "Your session expired. Sign in again to continue."
                    }
                case .failure(let error):
                    // One bad asset shouldn't abort the whole run — it's retried on the next backupNow().
                    progressFailed += 1
                    failureReasons[Self.failureReason(for: error), default: 0] += 1
                    Self.logger.error("Photo backup failed: \(String(describing: error), privacy: .public)")
                }
                #if os(iOS)
                continuedTask.update(completed: progressDone, total: progressTotal)
                #endif
                stopping = stopRequested
                enqueueNext()
            }
        }

        guard !sessionExpired else { return }

        if stopRequested {
            // iOS (or the user, from the system progress UI) stopped the background run; what's
            // left isn't known to the server yet, so the next backupNow() picks it up.
            lastError = "The backup stopped before finishing. It will resume on the next backup."
            return
        }

        if progressFailed > 0 {
            lastError = "\(progressFailed) photo(s) couldn't be uploaded. They'll be retried on the next backup."
        }
        lastBackupAt = Date()
    }

    /// Polling cadence and ceiling for `sanitizeNow()`. The server job itself has no fixed
    /// duration (it's bounded by how much of the library isn't yet at its canonical path), so
    /// this is a generous upper bound on how long the UI will keep spinning before giving up on
    /// *reporting* the result — the server-side job is unaffected and keeps running regardless.
    private static let sanitizePollInterval: Duration = .seconds(3)
    private static let sanitizePollMaxAttempts = 400

    /// Reorganizes the server's on-disk photo layout to match each photo's DB `taken_at`, and
    /// recovers any uploads that completed without ever being registered. Admin-only server-side.
    /// A full pass over a large library can take minutes of file hashing, so the server runs it as
    /// a background job rather than as part of this HTTP request (which used to time out on a
    /// large library while the job kept mutating the DB in the background regardless) — this just
    /// starts it and polls `/sanitize/status` until it finishes.
    public func sanitizeNow() async {
        guard !isSanitizing else { return }
        isSanitizing = true
        lastError = nil
        lastSanitizeMessage = nil
        defer { isSanitizing = false }

        do {
            let start = try await client.sanitize(dryRun: false)
            if start.alreadyRunning {
                lastSanitizeMessage = "A reorganization was already running. Waiting for it to finish…"
            }

            for _ in 0..<Self.sanitizePollMaxAttempts {
                try await Task.sleep(for: Self.sanitizePollInterval)
                let status = try await client.sanitizeStatus()
                guard !status.running else { continue }
                guard let report = status.lastReport else {
                    lastError = "Couldn't reorganize the photos"
                    return
                }
                var message = "Moved \(report.moved), recovered \(report.recoveredOrphans), removed \(report.duplicatesRemoved) duplicate(s)"
                if report.removedMissing > 0 {
                    message += " · \(report.removedMissing) removed because the file was missing"
                }
                if !report.errors.isEmpty {
                    message += " · \(report.errors.count) error(s)"
                }
                lastSanitizeMessage = message
                return
            }
            lastError = "The reorganization is still running on the server. Check back later."
        } catch {
            lastError = "Couldn't reorganize the photos"
        }
    }

    /// Intensive reconciliation pass: uploads any local asset the server doesn't know about yet
    /// (same safety net as `backupNow()`, just driven by the authoritative server list instead of
    /// a `check-existing` id lookup), and for assets the server already has, compares cheap local
    /// metadata against the server's record to surface drift without ever touching existing rows.
    public func checkNow(ownerEmail: String) async {
        guard !isChecking else { return }
        isChecking = true
        lastError = nil
        permissionDenied = false
        lastCheckMessage = nil
        defer { isChecking = false }

        #if os(iOS)
        let endBackgroundExecution = beginBackgroundExecution(name: "PhotoCheck")
        defer { endBackgroundExecution() }
        #endif

        let status = await PhotoLibraryAuthorization.requestReadOnlyAccess()
        guard status == .authorized || status == .limited else {
            lastError = "No access to the photo library"
            permissionDenied = true
            return
        }

        let scan = PhotoBackupPlanner.scanImageAssets()
        guard !scan.images.isEmpty else {
            lastCheckMessage = "There are no photos in the library"
            return
        }

        let serverMetadata: [String: PhotosClient.AssetMetadata]
        do {
            serverMetadata = try await fetchServerMetadata(scan.images.map(\.localIdentifier))
        } catch {
            lastError = "Couldn't check the server's photos"
            return
        }

        var missing: [PHAsset] = []
        var known: [PHAsset] = []
        for asset in scan.images {
            if serverMetadata[asset.localIdentifier] != nil {
                known.append(asset)
            } else {
                missing.append(asset)
            }
        }

        var uploaded = 0
        var uploadFailed = 0
        var sessionExpired = false
        await withTaskGroup(of: Result<Void, Error>.self) { group in
            var iterator = missing.makeIterator()

            func enqueueNext() {
                guard !sessionExpired, let asset = iterator.next() else { return }
                group.addTask {
                    do {
                        try await self.backup(asset: asset, ownerEmail: ownerEmail)
                        return .success(())
                    } catch {
                        return .failure(error)
                    }
                }
            }

            for _ in 0..<maxConcurrentUploads {
                enqueueNext()
            }

            for await result in group {
                switch result {
                case .success:
                    uploaded += 1
                case .failure(APIError.sessionExpired):
                    if !sessionExpired {
                        sessionExpired = true
                        lastError = "Your session expired. Sign in again to continue."
                    }
                case .failure:
                    uploadFailed += 1
                }
                enqueueNext()
            }
        }

        guard !sessionExpired else { return }

        var mismatches: [String] = []
        for asset in known {
            guard let serverInfo = serverMetadata[asset.localIdentifier] else { continue }
            let local = PhotoMetadataExtractor.extractLightweight(from: asset)
            if let mismatch = describeMismatch(local: local, server: serverInfo) {
                mismatches.append(mismatch)
            }
            await PhotoThumbnailCache.ensureThumbnail(for: asset, checksum: serverInfo.checksum)
        }

        var message = "Checked \(scan.images.count) photos"
        if uploaded > 0 { message += " · \(uploaded) uploaded" }
        if uploadFailed > 0 { message += " · \(uploadFailed) failed" }
        if !mismatches.isEmpty { message += " · \(mismatches.count) with different metadata" }
        lastCheckMessage = message
    }

    /// `takenAt` is compared with a tolerance rather than exact-string equality to absorb
    /// ISO8601 round-trip precision differences between the server's stored value and the
    /// device's `creationDate`, not because real drift is expected to be sub-second.
    private func describeMismatch(local: LightweightPhotoMetadata, server: PhotosClient.AssetMetadata) -> String? {
        var issues: [String] = []
        if let serverWidth = server.width, local.width != serverWidth { issues.append("width") }
        if let serverHeight = server.height, local.height != serverHeight { issues.append("height") }
        if let localName = local.originalFilename, localName != server.originalFilename {
            issues.append("name")
        }
        if let localTakenAt = local.takenAt {
            let serverTakenAt = server.takenAt.flatMap { ISO8601DateFormatter().date(from: $0) }
            if let serverTakenAt, abs(localTakenAt.timeIntervalSince(serverTakenAt)) > 5 {
                issues.append("date")
            }
        }
        guard !issues.isEmpty else { return nil }
        return "\(local.sourceAssetId): \(issues.joined(separator: ", "))"
    }

    private func fetchServerMetadata(_ ids: [String]) async throws -> [String: PhotosClient.AssetMetadata] {
        var result: [String: PhotosClient.AssetMetadata] = [:]
        for batch in ids.chunked(into: 200) {
            let page = try await client.metadataByAsset(assetIds: batch)
            result.merge(page) { _, new in new }
        }
        return result
    }

    private func backup(asset: PHAsset, ownerEmail: String) async throws {
        let metadata = try await PhotoMetadataExtractor.extract(from: asset)
        let folderPath = PhotoBackupPlanner.destinationFolder(for: metadata.takenAt, ownerEmail: ownerEmail)
        let filename = "\(metadata.checksum).\(PhotoBackupPlanner.fileExtension(for: metadata.originalFilename))"
        let filePath = "\(folderPath)/\(filename)"

        // Retrying the upload is safe: the server overwrites the file at the same path.
        try await withNetworkRetry {
            try await client.upload(
                path: folderPath,
                filename: filename,
                data: metadata.data,
                mimeType: metadata.mimeType ?? "application/octet-stream"
            )
        }

        let registration = PhotosClient.Registration(
            path: filePath,
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
        // Also safe to retry: the server dedups registrations by checksum.
        _ = try await withNetworkRetry { try await client.register(registration) }

        await PhotoThumbnailCache.ensureThumbnail(for: asset, checksum: metadata.checksum)
    }

    private func withNetworkRetry<T>(_ operation: () async throws -> T) async throws -> T {
        var attempt = 1
        while true {
            do {
                return try await operation()
            } catch let error as APIError where attempt < Self.networkAttempts && Self.isTransient(error) {
                Self.logger.info("Retrying after transient error: \(String(describing: error), privacy: .public)")
                try await Task.sleep(for: .seconds(2 * attempt))
                attempt += 1
            }
        }
    }

    private static func isTransient(_ error: APIError) -> Bool {
        switch error {
        case .transport: return true
        case .server(let status, _): return status >= 500
        default: return false
        }
    }

    private static func failureReason(for error: Error) -> String {
        switch error {
        case PhotoMetadataExtractor.ExtractionError.timedOut:
            return "iCloud took too long to download the photo"
        case PhotoMetadataExtractor.ExtractionError.noPhotoResource:
            return "The photo has no original file"
        case APIError.transport:
            return "Connection dropped or offline"
        case APIError.server(422, _):
            return "The file reached the server corrupted"
        case APIError.server(let status, _):
            return "Server error (\(status))"
        case APIError.decoding, APIError.invalidResponse:
            return "Unexpected server response"
        case let error as NSError where error.domain == PHPhotosErrorDomain || error.domain == "CloudPhotoLibraryErrorDomain":
            return "Couldn't read the photo from the library or iCloud"
        default:
            return "Other error: \((error as NSError).domain) \((error as NSError).code)"
        }
    }
}

extension Date {
    var tpISO8601: String { ISO8601DateFormatter().string(from: self) }
}
