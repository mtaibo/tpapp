import Foundation
import Photos
import TPCore

@MainActor
public final class PhotoSyncStore: ObservableObject {
    @Published public private(set) var isRunning = false
    @Published public private(set) var progressCompleted = 0
    @Published public private(set) var progressTotal = 0
    @Published public private(set) var lastError: String?
    @Published public private(set) var lastBackupAt: Date?

    private let client: PhotosClient

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
        progressTotal = 0
        defer { isRunning = false }

        let status = await PhotoLibraryAuthorization.requestReadOnlyAccess()
        guard status == .authorized || status == .limited else {
            lastError = "Sin acceso a la librería de fotos"
            return
        }

        let assets = fetchAllImageAssets()
        guard !assets.isEmpty else { return }

        let knownIds: Set<String>
        do {
            knownIds = try await checkKnownAssetIds(assets.map(\.localIdentifier))
        } catch {
            lastError = "No se pudo comprobar qué fotos ya existen"
            return
        }

        let pending = assets.filter { !knownIds.contains($0.localIdentifier) }
        progressTotal = pending.count

        for asset in pending {
            do {
                try await backup(asset: asset, ownerEmail: ownerEmail)
            } catch {
                // One bad asset shouldn't abort the whole run — it's retried on the next backupNow().
            }
            progressCompleted += 1
        }

        lastBackupAt = Date()
    }

    private func fetchAllImageAssets() -> [PHAsset] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        let result = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
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
        return "users/\(ownerEmail)/Photos/\(year)/\(String(format: "%02d", month))"
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
