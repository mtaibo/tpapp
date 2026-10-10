import SwiftUI
import TPCore
import TPCloudFeature
import TPStoreFeature

private enum AppTab: Hashable {
    case store, shared, account
}

struct RootView: View {
    @ObservedObject var session: AuthSession
    let accountClient: CloudAccountClient
    let storeClient: StoreClient

    @State private var selectedTab: AppTab = .store
    @State private var storeResetSignal = 0
    @State private var sharedResetSignal = 0

    var body: some View {
        Group {
            switch session.state {
            case .signedOut, .totpRequired:
                LoginView(session: session)
            case .signedIn(let profile):
                TabView(selection: tabSelection) {
                    FileBrowserView(storeClient: storeClient, rootPath: "users/\(profile.email)", resetSignal: storeResetSignal)
                        .tabItem { Label("Store", systemImage: "folder.fill") }
                        .tag(AppTab.store)
                    SharedView(storeClient: storeClient, resetSignal: sharedResetSignal)
                        .tabItem { Label("Shared", systemImage: "link") }
                        .tag(AppTab.shared)
                    AccountView(session: session, accountClient: accountClient)
                        .tabItem { Label("Account", systemImage: "person.crop.circle") }
                        .tag(AppTab.account)
                }
            }
        }
        .task { await session.restoreIfPossible() }
    }

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == selectedTab {
                    switch newValue {
                    case .store: storeResetSignal += 1
                    case .shared: sharedResetSignal += 1
                    case .account: break
                    }
                }
                selectedTab = newValue
            }
        )
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
