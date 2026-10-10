public struct PasswordTOTPAuthenticator: Sendable {
    public struct LoginOutcome: Decodable, Sendable {
        public let totpRequired: Bool
    }

    private struct LoginRequest: Encodable {
        let email: String
        let password: String
    }

    private struct TOTPRequest: Encodable {
        let code: String
    }

    private struct StatusResponse: Decodable {
        let status: String
    }

    private let client: HTTPClient

    public init(client: HTTPClient) {
        self.client = client
    }

    public func login(email: String, password: String) async throws -> LoginOutcome {
        try await client.post("/auth/password/login", body: LoginRequest(email: email, password: password))
    }

    public func verifyTOTP(code: String) async throws {
        let _: StatusResponse = try await client.post("/auth/password/totp/verify", body: TOTPRequest(code: code))
    }

    public func currentProfile() async throws -> UserProfile {
        try await client.get("/auth/passkey/me")
    }

    public func logout() async throws {
        try await client.post("/auth/passkey/logout")
    }
}
