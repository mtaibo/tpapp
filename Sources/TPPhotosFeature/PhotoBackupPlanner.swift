import Foundation
@preconcurrency import Photos
import TPCore

/// Shared "what still needs backing up" logic, used by both the foreground `PhotoSyncStore`
/// (user taps "Backup now") and `PhotoBackgroundUploader` (the unattended background-session
/// engine) so the two paths can never drift into different ideas of what "pending" means.
public enum PhotoBackupPlanner {
    public struct AssetScan: Sendable {
        public let images: [PHAsset]
        public let excludedVideoCount: Int
    }

    /// v1 backs up stills only. Sorted newest-first so a long backup makes the newest photos
    /// show up almost immediately instead of only after the entire backlog finishes.
    /// Enumerates the whole library, which takes a noticeable while on a large one — `@concurrent`
    /// so it never runs on the main thread, whoever calls it.
    @concurrent
    public static func scanImageAssets() async -> AssetScan {
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

    public static func checkKnownAssetIds(_ ids: [String], client: PhotosClient) async throws -> Set<String> {
        var known = Set<String>()
        for batch in ids.chunked(into: 200) {
            let result = try await client.checkExisting(assetIds: batch)
            known.formUnion(result)
        }
        return known
    }

    /// Matches the server's `photos/<email>/<year>/<month>` canonical layout.
    public static func destinationFolder(for takenAt: Date?, ownerEmail: String) -> String {
        let date = takenAt ?? Date()
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        return "photos/\(ownerEmail)/\(year)/\(String(format: "%02d", month))"
    }

    public static func fileExtension(for originalFilename: String) -> String {
        let ext = (originalFilename as NSString).pathExtension
        return ext.isEmpty ? "jpg" : ext.lowercased()
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
