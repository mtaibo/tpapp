import Foundation
@preconcurrency import Photos
import SwiftUI
import TPCore
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Where gallery thumbnails come from, fastest first — the same idea as Apple's Photos app, which
/// never downloads anything to draw its grid:
///
/// 1. Memory.
/// 2. **This device's own photo library.** Most server photos were backed up from this iPhone,
///    and `Photo.sourceAssetId` is that asset's local identifier, so PhotoKit can hand back the
///    system's own small thumbnail: no network, no extra storage, effectively instant.
/// 3. A persistent on-disk copy of the server thumbnail (`Caches/PhotoGridThumbnails`).
/// 4. The server, once — the result is written to disk for next time.
///
/// Only two server sizes are ever requested. tpstore builds each thumbnail by decoding the full
/// original with PIL on the Pi and caches it *per size*, so asking for a different size at every
/// zoom level (as the grid used to) made the server regenerate thousands of them from originals.
final class PhotoThumbnailLoader: Sendable {
    static let shared = PhotoThumbnailLoader()

    /// Pixel sizes requested from PhotoKit, so nearby tile sizes share one cached image.
    private static let pixelBuckets = [128, 256, 512, 1024]

    /// tpstore caps thumbnails at 400px.
    private static let smallServerSize = 200
    private static let largeServerSize = 400

    // NSCache is internally thread-safe.
    nonisolated(unsafe) private let memory = NSCache<NSString, ImageBox>()

    private let assetLock = NSLock()
    nonisolated(unsafe) private var assets: [String: PHAsset] = [:]
    nonisolated(unsafe) private var missingAssetIDs: Set<String> = []

    private static let directory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = caches.appendingPathComponent("PhotoGridThumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    private init() {
        memory.countLimit = 1500
    }

    static func bucket(forPixels pixels: Int) -> Int {
        pixelBuckets.first { $0 >= pixels } ?? pixelBuckets[pixelBuckets.count - 1]
    }

    /// Memory-only, synchronous: lets a tile draw on its first frame. Falls back to any other
    /// size already in memory, so zooming the grid shows the old image instead of a blank tile.
    func cachedImage(for photo: Photo, bucket: Int) -> Image? {
        if let exact = memory.object(forKey: Self.key(photo, bucket)) { return exact.image }
        for other in Self.pixelBuckets.reversed() where other != bucket {
            if let image = memory.object(forKey: Self.key(photo, other)) { return image.image }
        }
        return nil
    }

    @concurrent
    func image(for photo: Photo, bucket: Int, client: PhotosClient) async -> Image? {
        let key = Self.key(photo, bucket)
        if let cached = memory.object(forKey: key) { return cached.image }

        var image: Image?
        if let asset = localAsset(for: photo.sourceAssetId) {
            image = await Self.requestLocalImage(asset, pixels: bucket, allowNetwork: false)
        }
        if image == nil, !Task.isCancelled {
            image = await serverImage(for: photo, size: bucket <= 256 ? Self.smallServerSize : Self.largeServerSize, client: client)
        }
        guard let image else { return nil }
        memory.setObject(ImageBox(image), forKey: key)
        return image
    }

    /// The full photo for the viewer, from this device's library when it's there (downsampled
    /// to `pixels`, allowed to fetch from iCloud), so opening a photo doesn't download a
    /// multi-megabyte original from the server. Nil if the photo isn't on this device.
    @concurrent
    func localFullImage(for photo: Photo, pixels: Int) async -> Image? {
        guard let asset = localAsset(for: photo.sourceAssetId) else { return nil }
        return await Self.requestLocalImage(asset, pixels: pixels, allowNetwork: true, contentMode: .aspectFit)
    }

    /// Downloads, in the background, the small server thumbnail of every photo that isn't on
    /// this device and isn't on disk yet, newest first, so later scrolling is instant even for
    /// photos taken elsewhere. Roughly 10 KB per photo, in Caches (the system may purge it).
    @concurrent
    func prefetch(_ photos: [Photo], client: PhotosClient) async {
        primeAssets(photos.compactMap(\.sourceAssetId))
        let missing = photos.filter { photo in
            localAsset(for: photo.sourceAssetId) == nil && !hasDiskThumbnail(for: photo)
        }
        guard !missing.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            var iterator = missing.makeIterator()
            func addNext() {
                guard let photo = iterator.next() else { return }
                group.addTask(priority: .background) {
                    _ = await self.downloadServerThumbnail(for: photo, size: Self.smallServerSize, client: client)
                }
            }
            for _ in 0..<4 { addNext() }
            for await _ in group {
                if Task.isCancelled { group.cancelAll(); return }
                addNext()
            }
        }
    }

    // MARK: - Local library

    private static var hasLibraryAccess: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    /// Looks every id up in one PhotoKit fetch, instead of one fetch per tile.
    private func primeAssets(_ ids: [String]) {
        guard Self.hasLibraryAccess else { return }
        assetLock.lock()
        let unknown = ids.filter { assets[$0] == nil && !missingAssetIDs.contains($0) }
        assetLock.unlock()
        guard !unknown.isEmpty else { return }

        var found: [String: PHAsset] = [:]
        for start in stride(from: 0, to: unknown.count, by: 500) {
            let batch = Array(unknown[start..<min(start + 500, unknown.count)])
            PHAsset.fetchAssets(withLocalIdentifiers: batch, options: nil).enumerateObjects { asset, _, _ in
                found[asset.localIdentifier] = asset
            }
        }
        assetLock.lock()
        assets.merge(found) { _, new in new }
        missingAssetIDs.formUnion(unknown.filter { found[$0] == nil })
        assetLock.unlock()
    }

    private func localAsset(for id: String?) -> PHAsset? {
        guard let id, Self.hasLibraryAccess else { return nil }
        assetLock.lock()
        if let asset = assets[id] {
            assetLock.unlock()
            return asset
        }
        let knownMissing = missingAssetIDs.contains(id)
        assetLock.unlock()
        guard !knownMissing else { return nil }

        let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
        assetLock.lock()
        if let asset { assets[id] = asset } else { missingAssetIDs.insert(id) }
        assetLock.unlock()
        return asset
    }

    @concurrent
    private static func requestLocalImage(
        _ asset: PHAsset,
        pixels: Int,
        allowNetwork: Bool,
        contentMode: PHImageContentMode = .aspectFill
    ) async -> Image? {
        let options = PHImageRequestOptions()
        // One callback with the final image (`.opportunistic` calls back twice). At grid sizes
        // this is served from the library's own thumbnails, so it's still fast.
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = allowNetwork
        options.isSynchronous = false

        return await withCheckedContinuation { continuation in
            let once = ResumeOnce()
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: pixels, height: pixels),
                contentMode: contentMode,
                options: options
            ) { platformImage, _ in
                guard once.claim() else { return }
                continuation.resume(returning: platformImage.map(Self.swiftUIImage))
            }
        }
    }

    // MARK: - Server thumbnails

    private func diskURL(for photo: Photo, size: Int) -> URL {
        Self.directory.appendingPathComponent("\(photo.checksum)-\(size).jpg")
    }

    private func hasDiskThumbnail(for photo: Photo) -> Bool {
        FileManager.default.fileExists(atPath: diskURL(for: photo, size: Self.smallServerSize).path)
            || PhotoThumbnailCache.exists(forChecksum: photo.checksum)
    }

    @concurrent
    private func serverImage(for photo: Photo, size: Int, client: PhotosClient) async -> Image? {
        if let data = try? Data(contentsOf: diskURL(for: photo, size: size)) {
            return await Self.decode(data)
        }
        // The 220px copy made on this device during backup is good enough for small tiles.
        if size == Self.smallServerSize, let data = try? Data(contentsOf: PhotoThumbnailCache.fileURL(forChecksum: photo.checksum)) {
            return await Self.decode(data)
        }
        guard let data = await downloadServerThumbnail(for: photo, size: size, client: client) else { return nil }
        return await Self.decode(data)
    }

    @concurrent
    private func downloadServerThumbnail(for photo: Photo, size: Int, client: PhotosClient) async -> Data? {
        let url = client.thumbnailURL(for: photo, size: size)
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        try? data.write(to: diskURL(for: photo, size: size), options: .atomic)
        return data
    }

    // MARK: - Helpers

    private static func key(_ photo: Photo, _ bucket: Int) -> NSString {
        "\(photo.id)-\(bucket)" as NSString
    }

    #if os(iOS)
    private static func swiftUIImage(_ image: UIImage) -> Image { Image(uiImage: image) }

    @concurrent
    private static func decode(_ data: Data) async -> Image? {
        guard let image = UIImage(data: data) else { return nil }
        return Image(uiImage: await image.byPreparingForDisplay() ?? image)
    }
    #elseif os(macOS)
    private static func swiftUIImage(_ image: NSImage) -> Image { Image(nsImage: image) }

    @concurrent
    private static func decode(_ data: Data) async -> Image? {
        NSImage(data: data).map(Image.init(nsImage:))
    }
    #endif
}

private final class ImageBox: @unchecked Sendable {
    let image: Image
    init(_ image: Image) { self.image = image }
}

/// PhotoKit result handlers can fire more than once; a continuation must resume exactly once.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}

/// A grid tile's image, loaded through `PhotoThumbnailLoader`.
struct PhotoThumbnail: View {
    let photo: Photo
    let pixelSize: Int
    let client: PhotosClient

    @State private var image: Image?

    init(photo: Photo, pixelSize: Int, client: PhotosClient) {
        self.photo = photo
        self.pixelSize = pixelSize
        self.client = client
        _image = State(initialValue: PhotoThumbnailLoader.shared.cachedImage(
            for: photo,
            bucket: PhotoThumbnailLoader.bucket(forPixels: pixelSize)
        ))
    }

    var body: some View {
        let bucket = PhotoThumbnailLoader.bucket(forPixels: pixelSize)
        ZStack {
            if let image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.fill.tertiary)
            }
        }
        .task(id: bucket) {
            // Keeps whatever is showing (e.g. the previous zoom level's image) until the new one
            // is ready, rather than flashing the placeholder.
            if let loaded = await PhotoThumbnailLoader.shared.image(for: photo, bucket: bucket, client: client) {
                image = loaded
            }
        }
    }
}
