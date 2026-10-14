import Foundation

public struct PhotosClient: Sendable {
    private let client: HTTPClient

    public init(client: HTTPClient) {
        self.client = client
    }

    public enum Filter: String, Sendable, CaseIterable {
        case all, screenshots, camera, shared
    }

    public struct Registration: Encodable, Sendable {
        public let path: String
        public let location: String
        public let checksum: String
        public let originalFilename: String
        public let sourceAssetId: String?
        public let fileSize: Int
        public let mimeType: String?
        public let width: Int?
        public let height: Int?
        public let takenAt: String?
        public let isScreenshot: Bool
        public let isCameraOriginal: Bool
        public let sourceType: String
        public let cameraMake: String?
        public let cameraModel: String?
        public let gpsLat: Double?
        public let gpsLon: Double?

        public init(
            path: String,
            location: StoreLocation = .external,
            checksum: String,
            originalFilename: String,
            sourceAssetId: String? = nil,
            fileSize: Int,
            mimeType: String? = nil,
            width: Int? = nil,
            height: Int? = nil,
            takenAt: String? = nil,
            isScreenshot: Bool = false,
            isCameraOriginal: Bool = false,
            sourceType: String = "unknown",
            cameraMake: String? = nil,
            cameraModel: String? = nil,
            gpsLat: Double? = nil,
            gpsLon: Double? = nil
        ) {
            self.path = path
            self.location = location.rawValue
            self.checksum = checksum
            self.originalFilename = originalFilename
            self.sourceAssetId = sourceAssetId
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
        }
    }

    public func list(
        filter: Filter = .all,
        fromDate: String? = nil,
        toDate: String? = nil,
        cursor: String? = nil,
        limit: Int = 100
    ) async throws -> PhotoPage {
        var query: [String: String] = ["filter": filter.rawValue, "limit": String(limit)]
        if let fromDate { query["from_date"] = fromDate }
        if let toDate { query["to_date"] = toDate }
        if let cursor { query["cursor"] = cursor }
        return try await client.get("/api/photos", query: query)
    }

    public func detail(id: Int) async throws -> Photo {
        try await client.get("/api/photos/\(id)")
    }

    public func checkExisting(assetIds: [String]) async throws -> [String] {
        struct Body: Encodable { let sourceAssetIds: [String] }
        struct Response: Decodable { let knownAssetIds: [String] }
        let response: Response = try await client.post("/api/photos/check-existing", body: Body(sourceAssetIds: assetIds))
        return response.knownAssetIds
    }

    public func register(_ registration: Registration) async throws -> Photo {
        try await client.post("/api/photos", body: registration)
    }

    public func delete(id: Int) async throws {
        let _: [String: Int] = try await client.delete("/api/photos/\(id)")
    }

    public func ensurePhotoFolderExists(path: String, location: StoreLocation = .external) async throws {
        struct Body: Encodable { let path: String; let location: String }
        do {
            let _: [String: String] = try await client.post("/api/files/mkdir", body: Body(path: path, location: location.rawValue))
        } catch APIError.server(let status, _) where status == 400 {
            // Folder already exists — fine, it only needs to exist once.
        }
    }

    public func upload(path: String, location: StoreLocation = .external, filename: String, data: Data, mimeType: String = "application/octet-stream") async throws {
        let _: [String: [String]] = try await client.upload(
            "/api/files/upload",
            query: ["path": path, "location": location.rawValue],
            files: [HTTPClient.UploadFile(filename: filename, mimeType: mimeType, data: data)]
        )
    }

    public func thumbnailURL(for photo: Photo, size: Int = 160) -> URL {
        var components = URLComponents(url: client.baseURL.appending(path: "/api/files/thumbnail"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "path", value: photo.path),
            URLQueryItem(name: "location", value: photo.location.rawValue),
            URLQueryItem(name: "size", value: String(size))
        ]
        return components.url!
    }

    public struct SanitizeReport: Decodable, Sendable {
        public let dryRun: Bool
        public let moved: Int
        public let recoveredOrphans: Int
        public let duplicatesRemoved: Int
        public let errors: [String]
    }

    public func sanitize(dryRun: Bool) async throws -> SanitizeReport {
        try await client.post("/api/photos/sanitize", query: ["dry_run": String(dryRun)])
    }

    public func originalURL(for photo: Photo) -> URL {
        var components = URLComponents(url: client.baseURL.appending(path: "/api/files/download"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "path", value: photo.path),
            URLQueryItem(name: "location", value: photo.location.rawValue)
        ]
        return components.url!
    }
}
