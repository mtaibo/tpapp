public struct AdminModule: Decodable, Equatable, Sendable, Identifiable {
    public struct Repo: Decodable, Equatable, Sendable {
        public let branch: String?
        public let commit: String
        public let subject: String
        public let date: String
    }

    public let name: String
    public let path: String
    public let installed: Bool
    public let repo: Repo?
    public let containers: [ContainerInfo]
    /// Only for tpadmin itself, which is a systemd unit rather than containers: "active", "inactive"…
    public let serviceState: String?

    public var id: String { name }
}

public struct ContainerInfo: Decodable, Equatable, Sendable, Identifiable {
    public let name: String
    public let service: String?
    public let project: String?
    public let image: String
    /// docker's state: running, exited, restarting, paused, created, dead.
    public let state: String
    /// docker's human status, e.g. "Up 3 days" or "Exited (0) 2 hours ago".
    public let status: String
    public let health: String?
    public let createdAt: String

    public var id: String { name }
    public var isRunning: Bool { state == "running" }
}

public struct ContainerLogs: Decodable, Equatable, Sendable {
    public let name: String
    public let lines: [String]
}

public struct DeployJob: Decodable, Equatable, Sendable, Identifiable {
    public enum Status: String, Decodable, Sendable {
        case running, succeeded, failed
    }

    public let id: String
    public let title: String
    public let status: Status
    public let output: String
    public let startedAt: Double
    public let finishedAt: Double?
}
