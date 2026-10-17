import Foundation
import Photos
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Disk-backed cache of small gallery thumbnails, keyed by the same SHA-256 checksum used to
/// identify a `Photo` server-side. Living under Caches (OS-purgeable under storage pressure) is
/// correct here since every thumbnail is cheaply regenerable from the asset or re-downloaded.
/// Keying by checksum rather than asset id gives natural dedup: two `Photo` rows that happen to
/// share a checksum (e.g. a duplicate import) reuse the one cached file.
public enum PhotoThumbnailCache {
    private static let targetSize = CGSize(width: 220, height: 220)

    private static let directory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("PhotoThumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func path(forChecksum checksum: String) -> URL {
        directory.appendingPathComponent("\(checksum).jpg")
    }

    /// Where this checksum's thumbnail lives on disk, whether or not it's been written yet — the
    /// gallery hands it to `ImagePipeline`, which reads it off the main thread and falls back to
    /// the network when it isn't there.
    public static func fileURL(forChecksum checksum: String) -> URL {
        path(forChecksum: checksum)
    }

    public static func exists(forChecksum checksum: String) -> Bool {
        FileManager.default.fileExists(atPath: path(forChecksum: checksum).path)
    }

    /// No-ops if this checksum is already cached. `isNetworkAccessAllowed = false` means an
    /// iCloud-only asset with nothing local yet silently yields no thumbnail rather than forcing
    /// a download — this is a best-effort fill (from backup/Check), not a guarantee for every photo.
    public static func ensureThumbnail(for asset: PHAsset, checksum: String) async {
        guard !exists(forChecksum: checksum) else { return }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isSynchronous = false

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let box = ResumeBox()
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { platformImage, _ in
                guard !box.hasResumed else { return }
                box.hasResumed = true
                if let platformImage, let data = jpegData(from: platformImage) {
                    try? data.write(to: path(forChecksum: checksum))
                }
                continuation.resume()
            }
        }
    }

    #if os(iOS)
    private static func jpegData(from image: UIImage) -> Data? {
        image.jpegData(compressionQuality: 0.7)
    }
    #elseif os(macOS)
    private static func jpegData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
    }
    #endif
}

/// `requestImage` with `.opportunistic` delivery can invoke its handler more than once (low-quality
/// then final); this ensures the continuation only resumes once, serially on PhotoKit's own callback queue.
private final class ResumeBox: @unchecked Sendable {
    var hasResumed = false
}
