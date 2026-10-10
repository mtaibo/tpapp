import Foundation
import Testing
@testable import TPCore

extension TPCoreTestsRoot {

@MainActor
@Suite struct AuthSessionTests {
    private func makeAuthenticator() -> PasswordTOTPAuthenticator {
        PasswordTOTPAuthenticator(client: HTTPClient(baseURL: URL(string: "https://example.invalid")!, session: makeStubSession()))
    }

    @Test func loginWithoutTOTPSignsInDirectly() async throws {
        StubURLProtocol.handler = { request in
            if request.url?.path == "/auth/password/login" {
                return jsonResponse(request.url!, status: 200, json: #"{"totp_required": false}"#)
            }
            return jsonResponse(request.url!, status: 200, json: #"{"email":"a@b.com","display_name":"A","is_admin":false}"#)
        }
        let session = AuthSession(authenticator: makeAuthenticator(), cookieStore: FakeSessionCookieStore())

        try await session.login(email: "a@b.com", password: "secret")

        #expect(session.state == .signedIn(UserProfile(email: "a@b.com", displayName: "A", isAdmin: false)))
    }

    @Test func loginRequiringTOTPWaitsForCode() async throws {
        StubURLProtocol.handler = { request in
            jsonResponse(request.url!, status: 200, json: #"{"totp_required": true}"#)
        }
        let session = AuthSession(authenticator: makeAuthenticator(), cookieStore: FakeSessionCookieStore())

        try await session.login(email: "a@b.com", password: "secret")

        #expect(session.state == .totpRequired(email: "a@b.com"))
    }

    @Test func verifyTOTPCompletesSignIn() async throws {
        StubURLProtocol.handler = { request in
            if request.url?.path == "/auth/password/totp/verify" {
                return jsonResponse(request.url!, status: 200, json: #"{"status":"ok"}"#)
            }
            return jsonResponse(request.url!, status: 200, json: #"{"email":"a@b.com","display_name":"A","is_admin":false}"#)
        }
        let session = AuthSession(authenticator: makeAuthenticator(), cookieStore: FakeSessionCookieStore())

        try await session.verifyTOTP("123456")

        #expect(session.state == .signedIn(UserProfile(email: "a@b.com", displayName: "A", isAdmin: false)))
    }

    @Test func restoreWithoutCookieStaysSignedOutWithoutNetworkCall() async throws {
        StubURLProtocol.handler = { _ in
            Issue.record("should not make a network call when there is no session cookie")
            throw URLError(.unknown)
        }
        let session = AuthSession(authenticator: makeAuthenticator(), cookieStore: FakeSessionCookieStore(hasSessionCookie: false))

        await session.restoreIfPossible()

        #expect(session.state == .signedOut)
    }

    @Test func restoreWithValidCookieSignsIn() async throws {
        StubURLProtocol.handler = { request in
            jsonResponse(request.url!, status: 200, json: #"{"email":"a@b.com","display_name":"A","is_admin":false}"#)
        }
        let session = AuthSession(authenticator: makeAuthenticator(), cookieStore: FakeSessionCookieStore(hasSessionCookie: true))

        await session.restoreIfPossible()

        #expect(session.state == .signedIn(UserProfile(email: "a@b.com", displayName: "A", isAdmin: false)))
    }

    @Test func signOutClearsCookiesAndResetsState() async throws {
        StubURLProtocol.handler = { request in
            jsonResponse(request.url!, status: 200, json: "")
        }
        let fakeStore = FakeSessionCookieStore(hasSessionCookie: true)
        let session = AuthSession(authenticator: makeAuthenticator(), cookieStore: fakeStore)

        await session.signOut()

        #expect(session.state == .signedOut)
        #expect(fakeStore.clearCallCount == 1)
    }
}

}
