import Foundation

@MainActor
public final class AuthSession: ObservableObject {
    public enum State: Equatable, Sendable {
        case signedOut
        case totpRequired(email: String)
        case signedIn(UserProfile)
    }

    @Published public private(set) var state: State = .signedOut

    private let authenticator: PasswordTOTPAuthenticator
    private let cookieStore: SessionCookieStore

    public init(authenticator: PasswordTOTPAuthenticator, cookieStore: SessionCookieStore = HTTPCookieSessionStore()) {
        self.authenticator = authenticator
        self.cookieStore = cookieStore
    }

    public convenience init(baseURL: URL, cookieStore: SessionCookieStore = HTTPCookieSessionStore()) {
        self.init(authenticator: PasswordTOTPAuthenticator(client: HTTPClient(baseURL: baseURL)), cookieStore: cookieStore)
    }

    /// Call on app launch: restores a signed-in state from the persisted session cookie, if any, without prompting for credentials.
    public func restoreIfPossible() async {
        guard cookieStore.hasSessionCookie else {
            state = .signedOut
            return
        }
        do {
            state = .signedIn(try await authenticator.currentProfile())
        } catch {
            state = .signedOut
        }
    }

    public func login(email: String, password: String) async throws {
        let outcome = try await authenticator.login(email: email, password: password)
        if outcome.totpRequired {
            state = .totpRequired(email: email)
        } else {
            state = .signedIn(try await authenticator.currentProfile())
        }
    }

    public func verifyTOTP(_ code: String) async throws {
        try await authenticator.verifyTOTP(code: code)
        state = .signedIn(try await authenticator.currentProfile())
    }

    public func signOut() async {
        try? await authenticator.logout()
        cookieStore.clear()
        state = .signedOut
    }
}
