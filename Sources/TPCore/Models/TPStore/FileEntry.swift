public struct FileEntry: Decodable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Decodable, Equatable, Sendable {
        case file
        case directory
        case uploadPending = "upload-pending"
        case shareLink = "share-link"
    }

    public let name: String
    public let type: Kind
    public let size: Int?
    public let modified: Double
    public let iconName: String?
    public let uploadId: String?
    public let bytesReceived: Int?

    public var id: String { name }
    public var isDirectory: Bool { type == .directory }
}

public struct DirectoryListing: Decodable, Equatable, Sendable {
    public let path: String
    public let entries: [FileEntry]
}
