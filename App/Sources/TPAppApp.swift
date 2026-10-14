import SwiftUI
import TPCore
import TPHomeFeature
import TPPhotosFeature

@main
struct TPAppApp: App {
    private static let authBaseURL = URL(string: "https://login.migueltaibo.com")!
    private static let storeBaseURL = URL(string: "https://store.migueltaibo.com")!
    private static let homeBaseURL = URL(string: "https://tphome.migueltaibo.com")!
    private static let homeWSURL = URL(string: "wss://tphome.migueltaibo.com/api/ws")!

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

    var body: some Scene {
        WindowGroup {
            RootView(
                session: session,
                accountClient: accountClient,
                storeClient: storeClient,
                homeStore: homeStore,
                photosClient: photosClient,
                photoGalleryStore: photoGalleryStore,
                photoSyncStore: photoSyncStore
            )
        }
    }
}
