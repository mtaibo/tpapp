import Foundation

/// Client for tpadmin, the Raspberry Pi control panel API. Every endpoint is admin-only.
public struct AdminClient: Sendable {
    private let client: HTTPClient

    public init(client: HTTPClient) {
        self.client = client
    }

    // MARK: - System

    public func systemStatus() async throws -> SystemStatus {
        try await client.get("/api/system")
    }

    public func fastfetch() async throws -> [FastfetchRow] {
        struct Response: Decodable { let modules: [FastfetchRow] }
        let response: Response = try await client.get("/api/system/fastfetch")
        return response.modules
    }

    // MARK: - Modules & containers

    public func modules() async throws -> [AdminModule] {
        struct Response: Decodable { let modules: [AdminModule] }
        let response: Response = try await client.get("/api/modules")
        return response.modules
    }

    public func logs(container: String, tail: Int = 300) async throws -> [String] {
        let logs: ContainerLogs = try await client.get("/api/containers/\(container)/logs", query: ["tail": String(tail)])
        return logs.lines
    }

    public enum ContainerAction: String, Sendable, CaseIterable {
        case start, stop, restart
    }

    public func perform(_ action: ContainerAction, container: String) async throws {
        struct Response: Decodable { let ok: Bool }
        let _: Response = try await client.post("/api/containers/\(container)/\(action.rawValue)")
    }

    /// Starts `git pull` + rebuild of a module (or one of its services) as a background job.
    public func deploy(module: String, service: String? = nil) async throws -> DeployJob {
        try await client.post("/api/modules/\(module)/deploy", query: service.map { ["service": $0] } ?? [:])
    }

    public func job(id: String) async throws -> DeployJob {
        try await client.get("/api/jobs/\(id)")
    }

    // MARK: - Claude

    public func claudeSessions() async throws -> ClaudeSessionList {
        try await client.get("/api/claude/sessions")
    }

    public func startClaudeSession(directory: String) async throws -> ClaudeSession {
        struct Body: Encodable { let directory: String }
        return try await client.post("/api/claude/sessions", body: Body(directory: directory))
    }

    /// Answers the session's first-run "Trust this folder?" prompt with yes.
    public func trustClaudeSessionFolder(name: String) async throws {
        struct Response: Decodable { let name: String }
        let _: Response = try await client.post("/api/claude/sessions/\(name)/trust")
    }

    public func stopClaudeSession(name: String) async throws {
        struct Response: Decodable { let stopped: Bool }
        let _: Response = try await client.delete("/api/claude/sessions/\(name)")
    }
}
