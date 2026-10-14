public struct Photo: Decodable, Equatable, Sendable, Identifiable {
    public enum Status: String, Decodable, Sendable {
        case pending, verified, checksumMismatch = "checksum_mismatch", error
    }

    public enum SourceType: String, Decodable, Sendable {
        case userLibrary = "user_library", cloudShared = "cloud_shared", synced, unknown
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
