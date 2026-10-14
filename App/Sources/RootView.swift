import SwiftUI
import TPCore
import TPCloudFeature
import TPStoreFeature
import TPHomeFeature
import TPPhotosFeature

private enum AppTab: Hashable {
    case store, shared, photos, home, account
}

struct RootView: View {
    @ObservedObject var session: AuthSession
    let accountClient: CloudAccountClient
    let storeClient: StoreClient
    @ObservedObject var homeStore: HomeStore
    let photosClient: PhotosClient
    @ObservedObject var photoGalleryStore: PhotoGalleryStore
    @ObservedObject var photoSyncStore: PhotoSyncStore

    @State private var selectedTab: AppTab = .store
    @State private var storeResetSignal = 0
    @State private var sharedResetSignal = 0

    var body: some View {
        Group {
            switch session.state {
            case .checkingSession:
                Color.black.ignoresSafeArea()
            case .signedOut, .totpRequired:
                LoginView(session: session)
            case .signedIn(let profile):
                TabView(selection: tabSelection) {
                    FileBrowserView(storeClient: storeClient, rootPath: "users/\(profile.email)", resetSignal: storeResetSignal, isAdmin: profile.isAdmin)
                        .tabItem { Label("Store", systemImage: "folder.fill") }
                        .tag(AppTab.store)
                    SharedView(storeClient: storeClient, resetSignal: sharedResetSignal)
                        .tabItem { Label("Shared", systemImage: "link") }
                        .tag(AppTab.shared)
                    PhotoGalleryView(
                        store: photoGalleryStore,
                        syncStore: photoSyncStore,
                        client: photosClient,
                        ownerEmail: profile.email
                    )
                        .tabItem { Label("Photos", systemImage: "photo.on.rectangle") }
                        .tag(AppTab.photos)
                    HomeRootView(store: homeStore)
                        .tabItem { Label("Home", systemImage: "house.fill") }
                        .tag(AppTab.home)
                    AccountView(session: session, accountClient: accountClient)
                        .tabItem { Label("Account", systemImage: "person.crop.circle") }
                        .tag(AppTab.account)
                }
            }
        }
        .task {
            await session.restoreIfPossible()
            await homeStore.start()
        }
    }

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == selectedTab {
                    switch newValue {
                    case .store: storeResetSignal += 1
                    case .shared: sharedResetSignal += 1
                    case .photos, .home, .account: break
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
    let homeURL = URL(string: "https://tphome.migueltaibo.com")!
    RootView(
        session: AuthSession(baseURL: authURL),
        accountClient: CloudAccountClient(client: HTTPClient(baseURL: authURL)),
        storeClient: StoreClient(client: HTTPClient(baseURL: storeURL)),
        homeStore: HomeStore(
            client: HomeClient(client: HTTPClient(baseURL: homeURL)),
            wsClient: HomeWebSocketClient(url: URL(string: "wss://tphome.migueltaibo.com/api/ws")!)
        ),
        photosClient: PhotosClient(client: HTTPClient(baseURL: storeURL)),
        photoGalleryStore: PhotoGalleryStore(client: PhotosClient(client: HTTPClient(baseURL: storeURL))),
        photoSyncStore: PhotoSyncStore(client: PhotosClient(client: HTTPClient(baseURL: storeURL)))
    )
}
