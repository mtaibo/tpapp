/// `Codable` (not just `Decodable`) so the gallery can keep its list on disk between launches.
public struct Photo: Codable, Equatable, Sendable, Identifiable {
    public enum Status: String, Codable, Sendable {
        case pending, verified, checksumMismatch = "checksum_mismatch", error
    }

    public enum SourceType: String, Codable, Sendable {
        case userLibrary = "user_library", cloudShared = "cloud_shared", synced, unknown, recoveredOrphan = "recovered_orphan"

        // Server and client deploy independently, so a server-introduced value this enum doesn't
        // know about is a real, already-proven risk: "recovered_orphan" (set by Sanitize's
        // orphan-file recovery pass) was missing here and made JSONDecoder throw on the *entire*
        // page array the moment it hit that one row, silently breaking pagination for any filter
        // that could include it. Falling back to `.unknown` instead of throwing keeps one
        // unrecognized value from taking down decoding of every photo on the same page.
        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = SourceType(rawValue: raw) ?? .unknown
        }
    }

    public let id: Int
    public let path: String
    public let location: StoreLocation
    public let checksum: String
    public let sourceAssetId: String?
    public let originalFilename: String
    public let fileSize: Int
    public let mimeType: String?
    public let width: Int?
    public let height: Int?
    public let takenAt: String?
    public let isScreenshot: Bool
    public let isCameraOriginal: Bool
    public let sourceType: SourceType
    public let cameraMake: String?
    public let cameraModel: String?
    public let gpsLat: Double?
    public let gpsLon: Double?
    public let status: Status
    public let uploadedAt: String
    public let verifiedAt: String?

    public init(
        id: Int,
        path: String,
        location: StoreLocation,
        checksum: String,
        sourceAssetId: String?,
        originalFilename: String,
        fileSize: Int,
        mimeType: String?,
        width: Int?,
        height: Int?,
        takenAt: String?,
        isScreenshot: Bool,
        isCameraOriginal: Bool,
        sourceType: SourceType,
        cameraMake: String?,
        cameraModel: String?,
        gpsLat: Double?,
        gpsLon: Double?,
        status: Status,
        uploadedAt: String,
        verifiedAt: String?
    ) {
        self.id = id
        self.path = path
        self.location = location
        self.checksum = checksum
        self.sourceAssetId = sourceAssetId
        self.originalFilename = originalFilename
        self.fileSize = fileSize
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.takenAt = takenAt
        self.isScreenshot = isScreenshot
        self.isCameraOriginal = isCameraOriginal
        self.sourceType = sourceType
        self.cameraMake = cameraMake
        self.cameraModel = cameraModel
        self.gpsLat = gpsLat
        self.gpsLon = gpsLon
        self.status = status
        self.uploadedAt = uploadedAt
        self.verifiedAt = verifiedAt
    }
}

public struct PhotoPage: Decodable, Sendable {
    public let items: [Photo]
    public let nextCursor: String?
}
