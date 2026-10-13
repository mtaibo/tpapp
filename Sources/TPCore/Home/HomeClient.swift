public struct HomeClient: Sendable {
    private let client: HTTPClient

    public init(client: HTTPClient) {
        self.client = client
    }

    public func blinds() async throws -> [Blind] {
        try await client.get("/api/devices/blinds")
    }

    public func lights() async throws -> [Light] {
        try await client.get("/api/devices/lights")
    }

    public func mapConfig() async throws -> MapConfig {
        try await client.get("/api/config/map")
    }

    public func up(_ id: String) async throws {
        try await client.post("/api/commands/\(id)/up")
    }

    public func down(_ id: String) async throws {
        try await client.post("/api/commands/\(id)/down")
    }

    public func stop(_ id: String) async throws {
        try await client.post("/api/commands/\(id)/stop")
    }

    public func set(_ id: String, position: Int) async throws {
        try await client.post("/api/commands/\(id)/set/\(position)")
    }
}
