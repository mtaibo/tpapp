public struct CloudAccountClient: Sendable {
    public struct TOTPSetup: Decodable, Sendable {
        public let secret: String
        public let otpauthUri: String
    }

    private struct DisplayNameBody: Codable { let displayName: String }
    private struct PasswordChangeBody: Encodable { let currentPassword: String?; let newPassword: String }
    private struct TOTPCodeBody: Encodable { let code: String }
    private struct StatusResponse: Decodable { let status: String }

    private let client: HTTPClient

    public init(client: HTTPClient) {
        self.client = client
    }

    public func profile() async throws -> AccountProfile {
        try await client.get("/auth/account/profile")
    }

    public func updateDisplayName(_ displayName: String) async throws {
        let _: DisplayNameBody = try await client.patch("/auth/account/profile", body: DisplayNameBody(displayName: displayName))
    }

    public func changePassword(currentPassword: String?, newPassword: String) async throws {
        let _: StatusResponse = try await client.patch(
            "/auth/account/password",
            body: PasswordChangeBody(currentPassword: currentPassword, newPassword: newPassword)
        )
    }

    public func beginTOTPSetup() async throws -> TOTPSetup {
        try await client.post("/auth/account/totp/setup/begin")
    }

    public func completeTOTPSetup(code: String) async throws {
        let _: StatusResponse = try await client.post("/auth/account/totp/setup/complete", body: TOTPCodeBody(code: code))
    }

    public func disableTOTP(code: String) async throws {
        let _: StatusResponse = try await client.delete("/auth/account/totp", body: TOTPCodeBody(code: code))
    }

    public func revokeSession(_ sessionId: String) async throws {
        let _: StatusResponse = try await client.delete("/auth/account/session/\(sessionId)")
    }
}
