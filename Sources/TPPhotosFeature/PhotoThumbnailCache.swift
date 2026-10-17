import Foundation
@preconcurrency import Photos
import SwiftUI
import TPCore
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// The gallery's own on-device thumbnails, the way Apple's Photos app works: every photo has one
/// small (256px, ~10–15 KB) thumbnail stored on the phone, and the grid only ever draws from
/// those — it never waits on the server or the photo library while scrolling.
///
/// A thumbnail lands here either when the photo is backed up from this device (made from the
/// asset being uploaded anyway), or by being downloaded from the server exactly once: in the
/// background after the photo list syncs, or on demand if a tile scrolls into view first. Stored
/// in Application Support, not Caches, so iOS doesn't purge them and force a re-download.
public enum PhotoThumbnailCache {
    /// Pixel size of every stored thumbnail (and the size requested from the server).
    static let pixelSize = 256

    private static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var directory = base.appendingPathComponent("PhotoThumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Re-creatable from the server, so not worth a place in the user's iCloud backup.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
        migrateOldCaches(into: directory)
        return directory
    }()

    /// Earlier versions kept thumbnails in Caches: backup-made ones (same `<checksum>.jpg`
    /// naming) are moved over so they don't need downloading; per-size server copies are dropped.
    private static func migrateOldCaches(into directory: URL) {
        let fileManager = FileManager.default
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let backupMade = caches.appendingPathComponent("PhotoThumbnails", isDirectory: true)
        if let files = try? fileManager.contentsOfDirectory(at: backupMade, includingPropertiesForKeys: nil) {
            for file in files {
                try? fileManager.moveItem(at: file, to: directory.appendingPathComponent(file.lastPathComponent))
            }
        }
        try? fileManager.removeItem(at: backupMade)
        try? fileManager.removeItem(at: caches.appendingPathComponent("PhotoGridThumbnails", isDirectory: true))
    }

    /// Decoded images for tiles on and near the screen.
    nonisolated(unsafe) private static let memory: NSCache<NSString, ImageBox> = {
        let cache = NSCache<NSString, ImageBox>()
        cache.countLimit = 2000
        return cache
    }()

    static func fileURL(forChecksum checksum: String) -> URL {
        directory.appendingPathComponent("\(checksum).jpg")
    }

    public static func exists(forChecksum checksum: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(forChecksum: checksum).path)
    }

    /// Memory only and synchronous, so a tile scrolled back into view draws on its first frame.
    static func cachedImage(for photo: Photo) -> Image? {
        memory.object(forKey: photo.checksum as NSString)?.image
    }

    /// From disk, or — only if this photo has never been seen on this device — downloaded once
    /// and kept. Runs in the caller's task, so a tile that scrolls away cancels its download.
    @concurrent
    static func image(for photo: Photo, client: PhotosClient) async -> Image? {
        if let cached = cachedImage(for: photo) { return cached }
        var data = try? Data(contentsOf: fileURL(forChecksum: photo.checksum))
        if data == nil {
            data = await download(photo, client: client)
        }
        guard let data, !Task.isCancelled, let image = await decode(data) else { return nil }
        memory.setObject(ImageBox(image), forKey: photo.checksum as NSString)
        return image
    }

    /// Downloads the thumbnail of every photo that doesn't have one on this device yet, newest
    /// first, a few at a time in the background. After this, the grid never touches the network.
    @concurrent
    static func downloadMissing(_ photos: [Photo], client: PhotosClient) async {
        let missing = photos.filter { !exists(forChecksum: $0.checksum) }
        guard !missing.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            var iterator = missing.makeIterator()
            func addNext() {
                guard let photo = iterator.next() else { return }
                group.addTask(priority: .background) {
                    _ = await download(photo, client: client)
                }
            }
            for _ in 0..<6 { addNext() }
            for await _ in group {
                if Task.isCancelled {
                    group.cancelAll()
                    return
                }
                addNext()
            }
        }
    }

    @concurrent
    private static func download(_ photo: Photo, client: PhotosClient) async -> Data? {
        let url = client.thumbnailURL(for: photo, size: pixelSize)
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              !data.isEmpty else { return nil }
        try? data.write(to: fileURL(forChecksum: photo.checksum), options: .atomic)
        return data
    }

    /// Made during backup from the asset that's being uploaded anyway, so photos backed up from
    /// this device never need their thumbnail downloaded. No-ops if one already exists.
    /// `isNetworkAccessAllowed = false`: an iCloud-only asset just gets its thumbnail from the
    /// server later instead of forcing an iCloud download here.
    public static func ensureThumbnail(for asset: PHAsset, checksum: String) async {
        guard !exists(forChecksum: checksum) else { return }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isSynchronous = false

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let once = ResumeOnce()
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: pixelSize, height: pixelSize),
                contentMode: .aspectFill,
                options: options
            ) { platformImage, _ in
                guard once.claim() else { return }
                if let platformImage, let data = jpegData(from: platformImage) {
                    try? data.write(to: fileURL(forChecksum: checksum), options: .atomic)
                }
                continuation.resume()
            }
        }
    }

    #if os(iOS)
    private static func jpegData(from image: UIImage) -> Data? {
        image.jpegData(compressionQuality: 0.75)
    }

    @concurrent
    private static func decode(_ data: Data) async -> Image? {
        guard let image = UIImage(data: data) else { return nil }
        // Decode now, off the main thread, rather than on first draw.
        return Image(uiImage: await image.byPreparingForDisplay() ?? image)
    }
    #elseif os(macOS)
    private static func jpegData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.75])
    }

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

/// A grid tile's image, from `PhotoThumbnailCache`.
struct PhotoThumbnail: View {
    let photo: Photo
    let client: PhotosClient

    @State private var image: Image?

    init(photo: Photo, client: PhotosClient) {
        self.photo = photo
        self.client = client
        _image = State(initialValue: PhotoThumbnailCache.cachedImage(for: photo))
    }

    var body: some View {
        ZStack {
            if let image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.fill.tertiary)
            }
        }
        .task(id: photo.checksum) {
            guard image == nil else { return }
            image = await PhotoThumbnailCache.image(for: photo, client: client)
        }
    }
}
