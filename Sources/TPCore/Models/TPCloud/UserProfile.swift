public struct UserProfile: Decodable, Equatable, Sendable {
    public let email: String
    public let displayName: String
    public let isAdmin: Bool
}
