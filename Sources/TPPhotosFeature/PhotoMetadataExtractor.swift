import CryptoKit
import ImageIO
import Photos
import UniformTypeIdentifiers

public struct ExtractedPhotoMetadata: Sendable {
    public let sourceAssetId: String
    public let originalFilename: String
    public let fileSize: Int
    public let checksum: String
    public let mimeType: String?
    public let width: Int
    public let height: Int
    public let takenAt: Date?
    public let isScreenshot: Bool
    public let isCameraOriginal: Bool
    public let sourceType: String
    public let cameraMake: String?
    public let cameraModel: String?
    public let gpsLat: Double?
    public let gpsLon: Double?
    public let data: Data
}

public enum PhotoMetadataExtractor {
    public enum ExtractionError: Error {
        case noPhotoResource
    }

    public static func extract(from asset: PHAsset) async throws -> ExtractedPhotoMetadata {
        guard asset.mediaType == .image else { throw ExtractionError.noPhotoResource }

        // Live Photos also carry a `.pairedVideo` resource; v1 backs up stills only, so it's ignored here.
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == .photo }) ?? resources.first(where: { $0.type == .fullSizePhoto }) else {
            throw ExtractionError.noPhotoResource
        }

        let (data, checksum) = try await loadDataAndChecksum(for: resource)

        let isScreenshot = asset.mediaSubtypes.contains(.photoScreenshot)
        let sourceType = classifySourceType(asset.sourceType)
        let exif = await loadEXIF(for: asset)
        let isCameraOriginal = !isScreenshot && sourceType != "cloud_shared" && exif.cameraMake != nil

        return ExtractedPhotoMetadata(
            sourceAssetId: asset.localIdentifier,
            originalFilename: resource.originalFilename,
            fileSize: data.count,
            checksum: checksum,
            mimeType: mimeType(for: resource),
            width: asset.pixelWidth,
            height: asset.pixelHeight,
            takenAt: asset.creationDate,
            isScreenshot: isScreenshot,
            isCameraOriginal: isCameraOriginal,
            sourceType: sourceType,
            cameraMake: exif.cameraMake,
            cameraModel: exif.cameraModel,
            gpsLat: exif.gpsLat,
            gpsLon: exif.gpsLon,
            data: data
        )
    }

    private static func classifySourceType(_ sourceType: PHAssetSourceType) -> String {
        if sourceType.contains(.typeCloudShared) { return "cloud_shared" }
        if sourceType.contains(.typeiTunesSynced) { return "synced" }
        if sourceType.contains(.typeUserLibrary) { return "user_library" }
        return "unknown"
    }

    private static func mimeType(for resource: PHAssetResource) -> String? {
        UTType(resource.uniformTypeIdentifier)?.preferredMIMEType
    }

    /// Streams the asset's bytes once, hashing as it goes — the same read produces the upload
    /// payload, its size, and the checksum the server will later re-verify from disk.
    private static func loadDataAndChecksum(for resource: PHAssetResource) async throws -> (Data, String) {
        var hasher = SHA256()
        var buffer = Data()
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().requestData(
                for: resource,
                options: options,
                dataReceivedHandler: { chunk in
                    hasher.update(data: chunk)
                    buffer.append(chunk)
                },
                completionHandler: { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            )
        }

        let checksum = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return (buffer, checksum)
    }

    private struct EXIFInfo {
        var cameraMake: String?
        var cameraModel: String?
        var gpsLat: Double?
        var gpsLon: Double?
    }

    private static func loadEXIF(for asset: PHAsset) async -> EXIFInfo {
        await withCheckedContinuation { continuation in
            let options = PHContentEditingInputRequestOptions()
            options.isNetworkAccessAllowed = true
            asset.requestContentEditingInput(with: options) { input, _ in
                guard let url = input?.fullSizeImageURL,
                      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
                    continuation.resume(returning: EXIFInfo())
                    return
                }

                let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
                let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any]

                var info = EXIFInfo()
                info.cameraMake = tiff?[kCGImagePropertyTIFFMake] as? String
                info.cameraModel = tiff?[kCGImagePropertyTIFFModel] as? String

                if let gps,
                   let latitude = gps[kCGImagePropertyGPSLatitude] as? Double,
                   let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String,
                   let longitude = gps[kCGImagePropertyGPSLongitude] as? Double,
                   let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String {
                    info.gpsLat = latRef == "S" ? -latitude : latitude
                    info.gpsLon = lonRef == "W" ? -longitude : longitude
                }

                continuation.resume(returning: info)
            }
        }
    }
}
