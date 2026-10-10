public struct DiskInfo: Decodable, Equatable, Sendable {
    public let total: Int
    public let used: Int
    public let free: Int
}
