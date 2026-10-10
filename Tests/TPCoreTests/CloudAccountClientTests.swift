import Foundation
import Testing
@testable import TPCore

extension TPCoreTestsRoot {

@Suite struct CloudAccountClientTests {
    private func makeClient() -> CloudAccountClient {
        CloudAccountClient(client: HTTPClient(baseURL: URL(string: "https://example.invalid")!, session: makeStubSession()))
    }

    @Test func fetchesProfile() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/auth/account/profile")
            #expect(request.httpMethod == "GET")
            return jsonResponse(request.url!, status: 200, json: #"""
            {
                "id": 1,
                "email": "a@b.com",
                "display_name": "A",
                "is_admin": false,
                "has_password": true,
                "totp_enabled": false,
                "sessions": [
                    {
                        "session_id": "s1",
                        "created_at": "2026-01-01T00:00:00Z",
                        "expires_at": "2026-02-01T00:00:00Z",
                        "ip_address": "1.2.3.4",
                        "device_info": "Safari on macOS",
                        "location": "Madrid, ES",
                        "auth_method": "password",
                        "current": true
                    }
                ]
            }
            """#)
        }

        let profile = try await makeClient().profile()

        #expect(profile == AccountProfile(
            id: 1,
            email: "a@b.com",
            displayName: "A",
            isAdmin: false,
            hasPassword: true,
            totpEnabled: false,
            sessions: [
                AccountSession(
                    sessionId: "s1",
                    createdAt: "2026-01-01T00:00:00Z",
                    expiresAt: "2026-02-01T00:00:00Z",
                    ipAddress: "1.2.3.4",
                    deviceInfo: "Safari on macOS",
                    location: "Madrid, ES",
                    authMethod: "password",
                    current: true
                )
            ]
        ))
    }

    @Test func updatesDisplayName() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/auth/account/profile")
            #expect(request.httpMethod == "PATCH")
            let body = try #require(requestBody(request))
            let decoded = try JSONDecoder().decode([String: String].self, from: body)
            #expect(decoded["display_name"] == "New Name")
            return jsonResponse(request.url!, status: 200, json: #"{"display_name":"New Name"}"#)
        }

        try await makeClient().updateDisplayName("New Name")
    }

    @Test func changesPassword() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/auth/account/password")
            #expect(request.httpMethod == "PATCH")
            let body = try #require(requestBody(request))
            let decoded = try JSONDecoder().decode([String: String].self, from: body)
            #expect(decoded["current_password"] == "old")
            #expect(decoded["new_password"] == "newpass123")
            return jsonResponse(request.url!, status: 200, json: #"{"status":"ok"}"#)
        }

        try await makeClient().changePassword(currentPassword: "old", newPassword: "newpass123")
    }

    @Test func omitsCurrentPasswordWhenSettingForTheFirstTime() async throws {
        StubURLProtocol.handler = { request in
            let body = try #require(requestBody(request))
            let decoded = try JSONDecoder().decode([String: String].self, from: body)
            #expect(decoded["current_password"] == nil)
            #expect(decoded["new_password"] == "newpass123")
            return jsonResponse(request.url!, status: 200, json: #"{"status":"ok"}"#)
        }

        try await makeClient().changePassword(currentPassword: nil, newPassword: "newpass123")
    }

    @Test func beginsTOTPSetup() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/auth/account/totp/setup/begin")
            #expect(request.httpMethod == "POST")
            return jsonResponse(request.url!, status: 200, json: #"""
            {"secret":"BASE32SECRET","otpauth_uri":"otpauth://totp/TPCloud:a@b.com?secret=BASE32SECRET&issuer=TPCloud"}
            """#)
        }

        let setup = try await makeClient().beginTOTPSetup()

        #expect(setup.secret == "BASE32SECRET")
        #expect(setup.otpauthUri == "otpauth://totp/TPCloud:a@b.com?secret=BASE32SECRET&issuer=TPCloud")
    }

    @Test func completesTOTPSetup() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/auth/account/totp/setup/complete")
            #expect(request.httpMethod == "POST")
            let body = try #require(requestBody(request))
            let decoded = try JSONDecoder().decode([String: String].self, from: body)
            #expect(decoded["code"] == "123456")
            return jsonResponse(request.url!, status: 200, json: #"{"status":"TOTP configurado"}"#)
        }

        try await makeClient().completeTOTPSetup(code: "123456")
    }

    @Test func disablesTOTP() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/auth/account/totp")
            #expect(request.httpMethod == "DELETE")
            let body = try #require(requestBody(request))
            let decoded = try JSONDecoder().decode([String: String].self, from: body)
            #expect(decoded["code"] == "654321")
            return jsonResponse(request.url!, status: 200, json: #"{"status":"TOTP desactivado"}"#)
        }

        try await makeClient().disableTOTP(code: "654321")
    }

    @Test func revokesSession() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/auth/account/session/s1")
            #expect(request.httpMethod == "DELETE")
            return jsonResponse(request.url!, status: 200, json: #"{"status":"revocada"}"#)
        }

        try await makeClient().revokeSession("s1")
    }
}

}
