import SwiftUI
import TPCore

@main
struct TPAppApp: App {
    @StateObject private var session = AuthSession(baseURL: URL(string: "https://login.migueltaibo.com")!)

    var body: some Scene {
        WindowGroup {
            RootView(session: session)
        }
    }
}
