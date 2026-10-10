import Foundation

public protocol SessionCookieStore: Sendable {
    var hasSessionCookie: Bool { get }
    func clear()
}

public struct HTTPCookieSessionStore: SessionCookieStore {
    private let storage: HTTPCookieStorage
    private let domain: String

    public init(storage: HTTPCookieStorage = .shared, domain: String = "migueltaibo.com") {
        self.storage = storage
        self.domain = domain
    }

    public var hasSessionCookie: Bool {
        sessionCookies.contains { $0.name == "session_id" }
    }

    public func clear() {
        for cookie in sessionCookies {
            storage.deleteCookie(cookie)
        }
    }

    private var sessionCookies: [HTTPCookie] {
        (storage.cookies ?? []).filter { $0.domain.hasSuffix(domain) }
    }
}
