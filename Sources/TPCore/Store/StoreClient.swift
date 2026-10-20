import Foundation

public struct StoreClient: Sendable {
    private let client: HTTPClient

    public init(client: HTTPClient) {
        self.client = client
    }

    // MARK: - Browsing

    public func listDirectory(path: String = "", location: StoreLocation = .external) async throws -> DirectoryListing {
        try await client.get("/api/files/list", query: ["path": path, "location": location.rawValue])
    }

    public func diskInfo() async throws -> DiskInfo {
        try await client.get("/api/files/disk")
    }

    // MARK: - File operations

    public func createFolder(path: String, location: StoreLocation = .external) async throws {
        let _: [String: String] = try await client.post("/api/files/mkdir", body: PathBody(path: path, location: location.rawValue))
    }

    public func rename(path: String, newName: String, location: StoreLocation = .external) async throws {
        let _: [String: String] = try await client.post(
            "/api/files/rename",
            body: RenameBody(path: path, newName: newName, location: location.rawValue)
        )
    }

    public func move(path: String, destDir: String, location: StoreLocation = .external) async throws {
        let _: [String: String] = try await client.post(
            "/api/files/move",
            body: MoveBody(path: path, destDir: destDir, location: location.rawValue)
        )
    }

    public func delete(path: String, location: StoreLocation = .external) async throws {
        let _: [String: String] = try await client.delete("/api/files", query: ["path": path, "location": location.rawValue])
    }

    /// A folder's custom icon, by the web frontend's icon name (e.g. "Briefcase"), so both
    /// clients show the same one. `nil` goes back to the default folder.
    public func setFolderIcon(path: String, location: StoreLocation = .external, iconName: String?) async throws {
        if let iconName {
            let _: [String: Bool] = try await client.put(
                "/api/files/icon",
                body: IconBody(path: path, location: location.rawValue, iconName: iconName)
            )
        } else {
            let _: [String: Bool] = try await client.delete("/api/files/icon", query: ["path": path, "location": location.rawValue])
        }
    }

    // MARK: - Download / Upload

    public func download(path: String, location: StoreLocation = .external) async throws -> Data {
        try await client.getData("/api/files/download", query: ["path": path, "location": location.rawValue])
    }

    public func downloadZip(path: String, location: StoreLocation = .external) async throws -> Data {
        try await client.getData("/api/files/download-zip", query: ["path": path, "location": location.rawValue])
    }

    public func thumbnailURL(path: String, location: StoreLocation = .external, size: Int = 160) -> URL {
        var components = URLComponents(url: client.baseURL.appending(path: "/api/files/thumbnail"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "location", value: location.rawValue),
            URLQueryItem(name: "size", value: String(size))
        ]
        return components.url!
    }

    public func upload(path: String, location: StoreLocation = .external, filename: String, data: Data, mimeType: String = "application/octet-stream") async throws {
        let _: [String: [String]] = try await client.upload(
            "/api/files/upload",
            query: ["path": path, "location": location.rawValue],
            files: [HTTPClient.UploadFile(filename: filename, mimeType: mimeType, data: data)]
        )
    }

    // MARK: - Shares

    public func shares(path: String? = nil) async throws -> [ShareLink] {
        var query: [String: String] = [:]
        if let path { query["path"] = path }
        return try await client.get("/api/shares", query: query)
    }

    public func createShare(
        location: StoreLocation,
        path: String,
        hidden: Bool = false,
        slug: String? = nil,
        password: String? = nil,
        editable: Bool = false,
        isPublic: Bool = false
    ) async throws -> ShareLink {
        try await client.post(
            "/api/shares",
            body: CreateShareBody(
                location: location.rawValue,
                path: path,
                hidden: hidden,
                slug: slug,
                password: password,
                editable: editable,
                isPublic: isPublic
            )
        )
    }

    public func updateShare(
        token: String,
        password: String? = nil,
        clearPassword: Bool = false,
        editable: Bool? = nil,
        isPublic: Bool? = nil
    ) async throws -> ShareLink {
        try await client.patch(
            "/api/shares/\(token)",
            body: UpdateShareBody(password: password, clearPassword: clearPassword, editable: editable, isPublic: isPublic)
        )
    }

    public func deleteShare(_ token: String) async throws {
        let _: [String: String] = try await client.delete("/api/shares/\(token)")
    }
}

private struct PathBody: Encodable {
    let path: String
    let location: String
}

private struct IconBody: Encodable {
    let path: String
    let location: String
    let iconName: String
}

private struct RenameBody: Encodable {
    let path: String
    let newName: String
    let location: String
}

private struct MoveBody: Encodable {
    let path: String
    let destDir: String
    let location: String
}

private struct CreateShareBody: Encodable {
    let location: String
    let path: String
    let hidden: Bool
    let slug: String?
    let password: String?
    let editable: Bool
    let isPublic: Bool

    // `.convertToSnakeCase` would otherwise turn `isPublic` into "is_public", but the backend expects "public".
    enum CodingKeys: String, CodingKey {
        case location, path, hidden, slug, password, editable
        case isPublic = "public"
    }
}

private struct UpdateShareBody: Encodable {
    let password: String?
    let clearPassword: Bool
    let editable: Bool?
    let isPublic: Bool?

    enum CodingKeys: String, CodingKey {
        case password, clearPassword, editable
        case isPublic = "public"
    }
}
