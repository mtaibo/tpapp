public struct DeviceConnection: Decodable, Equatable, Sendable {
    public var online: Bool
    /// Python's `str(datetime)` (e.g. "2026-01-01 12:34:56.789012"), not ISO-8601 — never parse as `Date`.
    public let lastSeen: String?

    public init(online: Bool, lastSeen: String?) {
        self.online = online
        self.lastSeen = lastSeen
    }
}
