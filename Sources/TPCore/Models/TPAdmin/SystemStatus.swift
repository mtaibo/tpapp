public struct SystemStatus: Decodable, Equatable, Sendable {
    public struct Throttled: Decodable, Equatable, Sendable {
        public let raw: String
        /// `vcgencmd get_throttled` flags active right now, e.g. "under_voltage", "throttled".
        public let now: [String]
        /// Flags that have been raised at some point since boot.
        public let sinceBoot: [String]
    }

    public struct Memory: Decodable, Equatable, Sendable {
        public let total: Int
        public let used: Int
        public let available: Int
        public let swapTotal: Int
        public let swapUsed: Int
    }

    public struct Disk: Decodable, Equatable, Sendable, Identifiable {
        public let name: String
        public let mount: String
        public let total: Int
        public let used: Int
        public let free: Int

        public var id: String { mount }
    }

    public let hostname: String
    public let uptimeSeconds: Double
    public let temperatureC: Double?
    public let throttled: Throttled?
    /// Nil on the first sample after the API starts (usage is measured between two requests).
    public let cpuPercent: Double?
    public let cpuCount: Int?
    public let load: [Double]
    public let memory: Memory
    public let disks: [Disk]
}

/// One fastfetch module as a ready-to-show title/value row.
public struct FastfetchRow: Decodable, Equatable, Sendable, Identifiable {
    public let type: String
    public let value: String

    public var id: String { type }
}
