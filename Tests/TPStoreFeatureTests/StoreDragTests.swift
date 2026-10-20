import CoreTransferable
import Foundation
import UniformTypeIdentifiers
import Testing
import TPCore
@testable import TPStoreFeature

@MainActor
struct StoreDragTests {
    private let storeClient = StoreClient(client: HTTPClient(baseURL: URL(string: "https://store.example.com")!))

    private func entry(_ name: String, type: FileEntry.Kind) throws -> FileEntry {
        let json = #"{"name":"\#(name)","type":"\#(type.rawValue)","size":1,"modified":0}"#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(FileEntry.self, from: Data(json.utf8))
    }

    @Test func dragCarriesTheStoreItemAndARealFile() async throws {
        let folder = StoreFolder(location: .external, path: "users/me", title: "Home")
        let provider = StoreDragging.itemProvider(for: try entry("clip.mov", type: .file), in: folder, storeClient: storeClient)

        #expect(provider.registeredTypeIdentifiers.contains("com.apple.quicktime-movie"))
        #expect(provider.hasItemConformingToTypeIdentifier(UTType.storeItem.identifier))

        let item: StoreDragItem = try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadTransferable(type: StoreDragItem.self) { continuation.resume(with: $0) }
        }
        #expect(item.path == "users/me/clip.mov")
        #expect(item.parentPath == "users/me")
        #expect(!item.isDirectory)
    }

    @Test func moveRules() {
        let cache = StoreDirectoryCache(storeClient: storeClient)
        let file = StoreDragItem(location: .external, path: "users/me/a/clip.mov", isDirectory: false)
        let dir = StoreDragItem(location: .external, path: "users/me/a", isDirectory: true)
        let home = StoreFolder(location: .external, path: "users/me", title: "Home")

        #expect(cache.canMove(file, into: home.child("b")))
        #expect(!cache.canMove(file, into: home.child("a")))           // already there
        #expect(!cache.canMove(dir, into: home.child("a")))            // into itself
        #expect(!cache.canMove(dir, into: home.child("a").child("x"))) // into its own subfolder
        #expect(!cache.canMove(dir, into: home))                       // already there
        #expect(!cache.canMove(file, into: StoreFolder.system))        // other location
    }
}
