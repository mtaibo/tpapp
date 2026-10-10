import SwiftUI
import TPCore
import TPCloudFeature
import TPStoreFeature

struct RootView: View {
    @ObservedObject var session: AuthSession
    let accountClient: CloudAccountClient
    let storeClient: StoreClient

    var body: some View {
        Group {
            switch session.state {
            case .signedOut, .totpRequired:
                LoginView(session: session)
            case .signedIn(let profile):
                TabView {
                    FileBrowserView(storeClient: storeClient, rootPath: "users/\(profile.email)")
                        .tabItem { Label("Store", systemImage: "folder.fill") }
                    SharedView(storeClient: storeClient)
                        .tabItem { Label("Shared", systemImage: "link") }
                    AccountView(session: session, accountClient: accountClient)
                        .tabItem { Label("Account", systemImage: "person.crop.circle") }
                }
            }
        }
        .task { await session.restoreIfPossible() }
    }
}

#Preview {
    let authURL = URL(string: "https://login.migueltaibo.com")!
    let storeURL = URL(string: "https://store.migueltaibo.com")!
    RootView(
        session: AuthSession(baseURL: authURL),
        accountClient: CloudAccountClient(client: HTTPClient(baseURL: authURL)),
        storeClient: StoreClient(client: HTTPClient(baseURL: storeURL))
    )
}
