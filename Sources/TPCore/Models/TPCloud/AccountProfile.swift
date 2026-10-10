public struct AccountProfile: Decodable, Equatable, Sendable {
    public let id: Int
    public let email: String
    public let displayName: String
    public let isAdmin: Bool
    public let hasPassword: Bool
    public let totpEnabled: Bool
    public let sessions: [AccountSession]
}

public struct AccountSession: Decodable, Equatable, Sendable, Identifiable {
    public let sessionId: String
    public let createdAt: String
    public let expiresAt: String
    public let ipAddress: String?
    public let deviceInfo: String?
    public let location: String?
    public let authMethod: String
    public let current: Bool

    public var id: String { sessionId }
}
