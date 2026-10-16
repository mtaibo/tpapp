import SwiftUI
import TPAdminFeature
import TPCore
import TPHomeFeature
import TPPhotosFeature

@main
struct TPAppApp: App {
    private static let authBaseURL = URL(string: "https://login.migueltaibo.com")!
    private static let storeBaseURL = URL(string: "https://store.migueltaibo.com")!
    private static let homeBaseURL = URL(string: "https://tphome.migueltaibo.com")!
    private static let homeWSURL = URL(string: "wss://tphome.migueltaibo.com/api/ws")!
    private static let adminBaseURL = URL(string: "https://admin.migueltaibo.com")!

    @StateObject private var session = AuthSession(baseURL: authBaseURL)
    private let accountClient = CloudAccountClient(client: HTTPClient(baseURL: authBaseURL))
    private let storeClient = StoreClient(client: HTTPClient(baseURL: storeBaseURL))
    private let photosClient = PhotosClient(client: HTTPClient(baseURL: storeBaseURL))
    @StateObject private var homeStore = HomeStore(
        client: HomeClient(client: HTTPClient(baseURL: homeBaseURL)),
        wsClient: HomeWebSocketClient(url: homeWSURL)
    )
    @StateObject private var photoGalleryStore = PhotoGalleryStore(client: PhotosClient(client: HTTPClient(baseURL: storeBaseURL)))
    @StateObject private var photoSyncStore = PhotoSyncStore(client: PhotosClient(client: HTTPClient(baseURL: storeBaseURL)))
    @StateObject private var adminStore = AdminStore(client: AdminClient(client: HTTPClient(baseURL: adminBaseURL)))

    #if os(iOS)
    @UIApplicationDelegateAdaptor(PhotoBackupAppDelegate.self) private var appDelegate
    #endif

    init() {
        // `URLSession.shared` (what `HTTPClient` uses) honors `URLCache.shared` under its default
        // cache policy, and `/api/files/thumbnail` already serves cache-friendly
        // `Cache-Control: max-age` responses — but the system's default cache is sized for
        // occasional use, not a gallery grid scrolling back and forth over thousands of already-
        // seen thumbnails. Sizing it explicitly avoids re-fetching those over the network.
        URLCache.shared = URLCache(memoryCapacity: 50 * 1024 * 1024, diskCapacity: 500 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                session: session,
                accountClient: accountClient,
                storeClient: storeClient,
                homeStore: homeStore,
                photosClient: photosClient,
                photoGalleryStore: photoGalleryStore,
                photoSyncStore: photoSyncStore,
                adminStore: adminStore
            )
        }
    }
}
