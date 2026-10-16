import SwiftUI
import TPCore
import TPAdminFeature
import TPCloudFeature
import TPStoreFeature
import TPHomeFeature
import TPPhotosFeature

private enum AppTab: Hashable {
    case store, shared, photos, home, admin, account
}

struct RootView: View {
    @ObservedObject var session: AuthSession
    let accountClient: CloudAccountClient
    let storeClient: StoreClient
    @ObservedObject var homeStore: HomeStore
    let photosClient: PhotosClient
    @ObservedObject var photoGalleryStore: PhotoGalleryStore
    @ObservedObject var photoSyncStore: PhotoSyncStore
    @ObservedObject var photosTabBarState: PhotosTabBarState
    @ObservedObject var adminStore: AdminStore

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
                        tabBarState: photosTabBarState,
                        client: photosClient,
                        ownerEmail: profile.email,
                        isAdmin: profile.isAdmin
                    )
                        .tabItem { Label("Photos", systemImage: "photo.on.rectangle") }
                        .tag(AppTab.photos)
                        // Swapped for PhotosCollapsedBar below once scrolled — same trick the
                        // native Photos app uses to shrink its own tab bar while browsing.
                        .toolbar(photosTabBarState.isCollapsed ? .hidden : .visible, for: .tabBar)
                    HomeRootView(store: homeStore)
                        .tabItem { Label("Home", systemImage: "house.fill") }
                        .tag(AppTab.home)
                    // tpadmin controls the Pi itself; its API rejects non-admins anyway.
                    if profile.isAdmin {
                        AdminRootView(store: adminStore)
                            .tabItem { Label("Admin", systemImage: "gauge.with.dots.needle.67percent") }
                            .tag(AppTab.admin)
                    }
                    AccountView(session: session, accountClient: accountClient)
                        .tabItem { Label("Account", systemImage: "person.crop.circle") }
                        .tag(AppTab.account)
                }
                .overlay(alignment: .bottom) {
                    if selectedTab == .photos && photosTabBarState.isCollapsed {
                        PhotosCollapsedBar(state: photosTabBarState)
                            // Hiding the tab bar frees up the space it used to reserve, so this
                            // floating replacement has to re-add the home indicator clearance
                            // itself — otherwise it sits flush against (or under) the indicator.
                            .safeAreaPadding(.bottom)
                            .padding(.bottom, 8)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
            }
        }
        .task {
            await session.restoreIfPossible()
            await homeStore.start()
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            // Leaving Photos always hands the real tab bar back, so switching to it again (or
            // returning here) starts from its normal, uncollapsed state.
            if oldValue == .photos && newValue != .photos {
                photosTabBarState.isCollapsed = false
            }
        }
        .onChange(of: session.state) { _, newState in
            // The background upload engine has no SwiftUI view hierarchy to read `profile.email`
            // from when iOS wakes it directly (BGProcessingTask, or a background URLSession
            // completion) — this is the one place that keeps its persisted copy in sync with the
            // signed-in user, as the only two events that matter (signing in, signing out) happen.
            switch newState {
            case .signedIn(let profile):
                #if os(iOS)
                PhotoBackgroundUploader.rememberSignedIn(ownerEmail: profile.email)
                PhotoBackupScheduler.scheduleNext()
                Task { await PhotoBackgroundUploader.shared.refill() }
                #endif
            case .signedOut:
                #if os(iOS)
                PhotoBackgroundUploader.forgetSignedIn()
                #endif
            case .checkingSession, .totpRequired:
                break
            }
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
                    case .photos, .home, .admin, .account: break
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
        photoSyncStore: PhotoSyncStore(client: PhotosClient(client: HTTPClient(baseURL: storeURL))),
        photosTabBarState: PhotosTabBarState(),
        adminStore: AdminStore(client: AdminClient(client: HTTPClient(baseURL: URL(string: "https://admin.migueltaibo.com")!)))
    )
}
