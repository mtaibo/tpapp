import SwiftUI
import TPCore

@main
struct TPAppApp: App {
    private static let authBaseURL = URL(string: "https://login.migueltaibo.com")!
    private static let storeBaseURL = URL(string: "https://store.migueltaibo.com")!

    @StateObject private var session = AuthSession(baseURL: authBaseURL)
    private let accountClient = CloudAccountClient(client: HTTPClient(baseURL: authBaseURL))
    private let storeClient = StoreClient(client: HTTPClient(baseURL: storeBaseURL))

    var body: some Scene {
        WindowGroup {
            RootView(session: session, accountClient: accountClient, storeClient: storeClient)
        }
    }
}
