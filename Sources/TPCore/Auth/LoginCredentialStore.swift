import Foundation
import Security

/// Remembers the last email/password that the server accepted, in this app's own Keychain, so the
/// login form can prefill them. System password AutoFill can't suggest the right login on its own:
/// that needs an Associated Domains entitlement, which free Apple developer accounts can't sign.
public struct LoginCredentialStore: Sendable {
    public struct Credentials: Equatable, Sendable {
        public let email: String
        public let password: String
    }

    private let service: String

    public init(service: String = "com.migueltaibo.tpapp.login") {
        self.service = service
    }

    public func load() -> Credentials? {
        var query = baseQuery
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let item = result as? [String: Any],
              let email = item[kSecAttrAccount as String] as? String,
              let data = item[kSecValueData as String] as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return nil
        }
        return Credentials(email: email, password: password)
    }

    /// Replaces whatever was stored: only one account is ever remembered.
    public func save(email: String, password: String) {
        clear()
        var item = baseQuery
        item[kSecAttrAccount as String] = email
        item[kSecValueData as String] = Data(password.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    public func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
    }
}
