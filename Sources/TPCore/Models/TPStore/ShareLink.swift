public struct ShareLink: Decodable, Equatable, Sendable, Identifiable {
    public let token: String
    public let url: String
    public let location: StoreLocation
    public let path: String
    public let hidden: Bool
    public let hasPassword: Bool
    public let editable: Bool
    public let isPublic: Bool
    public let createdAt: String
    public let isFile: Bool

    public var id: String { token }

    // Only `isPublic` needs remapping: `.convertFromSnakeCase` already turns
    // "has_password"/"created_at"/"is_file" into the matching camelCase names,
    // but "public" has no underscore to convert.
    enum CodingKeys: String, CodingKey {
        case token, url, location, path, hidden, hasPassword, editable, createdAt, isFile
        case isPublic = "public"
    }
}
