import Foundation
import Photos
import TPCore

@MainActor
public final class PhotoSyncStore: ObservableObject {
    @Published public private(set) var isRunning = false
    /// Successfully uploaded assets in the current/last run.
    @Published public private(set) var progressCompleted = 0
    /// Assets that failed in the current/last run — kept separate from `progressCompleted` so
    /// a run full of failures doesn't read as "100% done".
    @Published public private(set) var progressFailed = 0
    @Published public private(set) var progressTotal = 0
    /// v1 backs up stills only; videos found during the scan are counted here so the UI can
    /// say "N videos not included" instead of silently never mentioning them.
    @Published public private(set) var excludedVideoCount = 0
    @Published public private(set) var lastError: String?
    @Published public private(set) var lastBackupAt: Date?

    public var progressDone: Int { progressCompleted + progressFailed }

    public var progressFraction: Double {
        guard progressTotal > 0 else { return 0 }
        return Double(progressDone) / Double(progressTotal)
    }

    public var progressLabel: String {
        var label = "\(progressDone)/\(progressTotal)"
        if progressFailed > 0 { label += " · \(progressFailed) con error" }
        if excludedVideoCount > 0 { label += " · \(excludedVideoCount) vídeo(s) no incluidos" }
        return label
    }

    private let client: PhotosClient
    /// Bounded in-flight uploads: high enough to overlap network/iCloud-download latency across
    /// assets (the old strictly-serial loop was the main source of "backup is very slow"),
    /// low enough not to flood the server or the device's network queue.
    private let maxConcurrentUploads = 4

    public init(client: PhotosClient) {
        self.client = client
    }

    /// v1's whole sync strategy: rescan the full library every run and let `check-existing`
    /// skip known assets. Simple, with no local sync-state that could drift from the server.
    public func backupNow(ownerEmail: String) async {
        guard !isRunning else { return }
        isRunning = true
        lastError = nil
        progressCompleted = 0
        progressFailed = 0
        progressTotal = 0
        excludedVideoCount = 0
        defer { isRunning = false }

        let status = await PhotoLibraryAuthorization.requestReadOnlyAccess()
        guard status == .authorized || status == .limited else {
            lastError = "Sin acceso a la librería de fotos"
            return
        }

        let scan = scanImageAssets()
        excludedVideoCount = scan.excludedVideoCount
        guard !scan.images.isEmpty else { return }

        let knownIds: Set<String>
        do {
            knownIds = try await checkKnownAssetIds(scan.images.map(\.localIdentifier))
        } catch {
            lastError = "No se pudo comprobar qué fotos ya existen"
            return
        }

        let pending = scan.images.filter { !knownIds.contains($0.localIdentifier) }
        progressTotal = pending.count

        // Bounded-concurrency pool instead of one-at-a-time: each in-flight upload still goes
        // through `backup(asset:ownerEmail:)` in order pulled from `pending` (already date-sorted),
        // so overall progress stays close to date order while up to `maxConcurrentUploads` network
        // round-trips overlap.
        var sessionExpired = false
        await withTaskGroup(of: Result<Void, Error>.self) { group in
            var iterator = pending.makeIterator()

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
                    progressCompleted += 1
                case .failure(APIError.sessionExpired):
                    // The whole batch would fail the same way from here on — stop enqueueing new
                    // uploads (in-flight ones are left to finish) instead of silently burning
                    // through the rest of the library as individual failures.
                    if !sessionExpired {
                        sessionExpired = true
                        lastError = "Tu sesión ha caducado, vuelve a iniciar sesión para continuar"
                    }
                case .failure:
                    // One bad asset shouldn't abort the whole run — it's retried on the next backupNow().
                    progressFailed += 1
                }
                enqueueNext()
            }
        }

        guard !sessionExpired else { return }

        if progressFailed > 0 {
            lastError = "\(progressFailed) foto(s) no se pudieron subir, se reintentarán en el próximo backup"
        }
        lastBackupAt = Date()
    }

    private struct AssetScan {
        let images: [PHAsset]
        let excludedVideoCount: Int
    }

    /// v1 backs up stills only. Sorted newest-first so a long backup makes the newest photos
    /// (the ones visible first in the newest-at-the-bottom gallery) show up almost immediately,
    /// instead of only after the entire backlog finishes.
    private func scanImageAssets() -> AssetScan {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: options)

        var images: [PHAsset] = []
        var videoCount = 0
        result.enumerateObjects { asset, _, _ in
            switch asset.mediaType {
            case .image: images.append(asset)
            case .video: videoCount += 1
            default: break
            }
        }
        return AssetScan(images: images, excludedVideoCount: videoCount)
    }

    private func checkKnownAssetIds(_ ids: [String]) async throws -> Set<String> {
        var known = Set<String>()
        for batch in ids.chunked(into: 200) {
            let result = try await client.checkExisting(assetIds: batch)
            known.formUnion(result)
        }
        return known
    }

    private func backup(asset: PHAsset, ownerEmail: String) async throws {
        let metadata = try await PhotoMetadataExtractor.extract(from: asset)
        let folderPath = destinationFolder(for: metadata.takenAt, ownerEmail: ownerEmail)
        try await client.ensurePhotoFolderExists(path: folderPath)

        let filename = "\(metadata.checksum).\(fileExtension(for: metadata))"
        let filePath = "\(folderPath)/\(filename)"

        try await client.upload(
            path: folderPath,
            filename: filename,
            data: metadata.data,
            mimeType: metadata.mimeType ?? "application/octet-stream"
        )

        _ = try await client.register(PhotosClient.Registration(
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
        ))
    }

    private func destinationFolder(for takenAt: Date?, ownerEmail: String) -> String {
        let date = takenAt ?? Date()
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        return "photos/\(ownerEmail)/\(year)/\(String(format: "%02d", month))"
    }

    private func fileExtension(for metadata: ExtractedPhotoMetadata) -> String {
        let ext = (metadata.originalFilename as NSString).pathExtension
        return ext.isEmpty ? "jpg" : ext.lowercased()
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

private extension Date {
    var tpISO8601: String { ISO8601DateFormatter().string(from: self) }
}
