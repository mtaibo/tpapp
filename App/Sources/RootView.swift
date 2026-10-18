import SwiftUI
import TPCore
import TPAdminFeature
import TPCloudFeature
import TPStoreFeature
import TPHomeFeature
import TPPhotosFeature

private enum AppTab: Hashable {
    case store, photos, home, more
}

struct RootView: View {
    @ObservedObject var session: AuthSession
    let accountClient: CloudAccountClient
    let storeClient: StoreClient
    // Plain references, not @ObservedObject: each feature view observes its own store. Observing
    // them here re-rendered the whole app — every tab — on each photo page that loaded during the
    // background drain and on every Home WebSocket event, which made launch and Photos crawl.
    let homeStore: HomeStore
    let photosClient: PhotosClient
    let photoGalleryStore: PhotoGalleryStore
    let photoSyncStore: PhotoSyncStore
    let adminStore: AdminStore

    @State private var selectedTab: AppTab = .store
    @State private var storeResetSignal = 0
    @State private var moreResetSignal = 0
    @State private var photosScrollSignal = 0

    var body: some View {
        Group {
            switch session.state {
            case .checkingSession:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .signedOut, .totpRequired:
                LoginView(session: session)
            case .signedIn(let profile):
                tabs(for: profile)
            }
        }
        .task {
            await session.restoreIfPossible()
            await homeStore.start()
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
                selectedTab = .store
                #if os(iOS)
                PhotoBackgroundUploader.forgetSignedIn()
                #endif
            case .checkingSession, .totpRequired:
                break
            }
        }
    }

    private func tabs(for profile: UserProfile) -> some View {
        TabView(selection: tabSelection) {
            Tab("Store", systemImage: "folder", value: AppTab.store) {
                StoreRootView(
                    storeClient: storeClient,
                    rootPath: "users/\(profile.email)",
                    isAdmin: profile.isAdmin,
                    resetSignal: storeResetSignal
                )
            }
            Tab("Photos", systemImage: "photo.on.rectangle", value: AppTab.photos) {
                PhotoGalleryView(
                    store: photoGalleryStore,
                    syncStore: photoSyncStore,
                    client: photosClient,
                    ownerEmail: profile.email,
                    isAdmin: profile.isAdmin,
                    scrollToBottomSignal: photosScrollSignal
                )
            }
            Tab("Home", systemImage: "house", value: AppTab.home) {
                HomeRootView(store: homeStore)
            }
            Tab("More", systemImage: "ellipsis", value: AppTab.more) {
                MoreView(
                    session: session,
                    profile: profile,
                    accountClient: accountClient,
                    adminStore: adminStore,
                    resetSignal: moreResetSignal
                )
            }
        }
        // A sidebar on iPad and Mac, the bottom tab bar on iPhone.
        .tabViewStyle(.sidebarAdaptable)
        #if os(iOS)
        // The system's own shrinking tab bar (what the Photos app does while scrolling). It
        // replaces a hand-made one that hid the real bar and floated a copy over the content.
        // Photos keeps its newest photos at the bottom, so there scrolling up (into older photos)
        // tucks the bar away and scrolling back down brings it back.
        .tabBarMinimizeBehavior(selectedTab == .photos ? .onScrollUp : .onScrollDown)
        #endif
    }

    /// Re-selecting the current tab pops it back to its root, like every system app.
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == selectedTab {
                    switch newValue {
                    case .store: storeResetSignal += 1
                    case .more: moreResetSignal += 1
                    // Photos keeps its newest photos at the bottom, so "back to the start" is down.
                    case .photos: photosScrollSignal += 1
                    case .home: break
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
    let photosClient = PhotosClient(client: HTTPClient(baseURL: storeURL))
    RootView(
        session: AuthSession(baseURL: authURL),
        accountClient: CloudAccountClient(client: HTTPClient(baseURL: authURL)),
        storeClient: StoreClient(client: HTTPClient(baseURL: storeURL)),
        homeStore: HomeStore(
            client: HomeClient(client: HTTPClient(baseURL: homeURL)),
            wsClient: HomeWebSocketClient(url: URL(string: "wss://tphome.migueltaibo.com/api/ws")!)
        ),
        photosClient: photosClient,
        photoGalleryStore: PhotoGalleryStore(client: photosClient),
        photoSyncStore: PhotoSyncStore(client: photosClient),
        adminStore: AdminStore(client: AdminClient(client: HTTPClient(baseURL: URL(string: "https://admin.migueltaibo.com")!)))
    )
}
