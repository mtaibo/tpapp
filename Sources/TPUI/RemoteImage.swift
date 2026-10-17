import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Loads and decodes thumbnails off the main thread, with an in-memory cache in front of
/// `URLCache.shared` (which `TPAppApp` sizes for gallery use) and an optional on-disk file that
/// wins over the network.
///
/// Deliberately not an actor and with no shared in-flight tasks: every load runs inside the
/// *caller's* task, so when a tile scrolls off screen and SwiftUI cancels its `.task`, the
/// network request is cancelled with it. Shared unstructured tasks kept running after their tile
/// was gone, and a fast scroll through a big grid queued hundreds of them ahead of the thumbnails
/// actually on screen — which then looked like they were loading forever.
public final class ImagePipeline: Sendable {
    public static let shared = ImagePipeline()

    // NSCache is internally thread-safe.
    nonisolated(unsafe) private let memory = NSCache<NSURL, ImageBox>()

    private init() {
        memory.countLimit = 800
    }

    /// Synchronous memory-only lookup, so a tile scrolled back into view can draw its image on the
    /// very first frame instead of flashing the placeholder.
    public func cachedImage(for url: URL) -> Image? {
        memory.object(forKey: url as NSURL)?.image
    }

    @concurrent
    public func image(for url: URL, localFile: URL? = nil) async -> Image? {
        if let cached = cachedImage(for: url) { return cached }

        let data: Data?
        if let localFile, let local = try? Data(contentsOf: localFile) {
            data = local
        } else {
            data = await Self.fetch(url)
        }
        guard let data, !Task.isCancelled, let image = await Self.decode(data) else { return nil }
        memory.setObject(ImageBox(image), forKey: url as NSURL)
        return image
    }

    @concurrent
    private static func fetch(_ url: URL) async -> Data? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        return data
    }

    @concurrent
    private static func decode(_ data: Data) async -> Image? {
        #if os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        return Image(nsImage: image)
        #else
        guard let image = UIImage(data: data) else { return nil }
        // Forces the JPEG/HEIC decode here, off the main thread, instead of on first draw.
        let prepared = await image.byPreparingForDisplay() ?? image
        return Image(uiImage: prepared)
        #endif
    }
}

private final class ImageBox: @unchecked Sendable {
    let image: Image
    init(_ image: Image) { self.image = image }
}

/// A thumbnail backed by `ImagePipeline`. The placeholder is a flat fill, so a grid keeps its
/// shape while images stream in.
public struct RemoteImage: View {
    let url: URL
    let localFile: URL?
    let contentMode: ContentMode

    @State private var image: Image?

    public init(url: URL, localFile: URL? = nil, contentMode: ContentMode = .fill) {
        self.url = url
        self.localFile = localFile
        self.contentMode = contentMode
        _image = State(initialValue: ImagePipeline.shared.cachedImage(for: url))
    }

    public var body: some View {
        ZStack {
            if let image {
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle().fill(.fill.tertiary)
            }
        }
        .task(id: url) {
            // On a URL change (e.g. a bigger thumbnail after zooming the grid in) the previous
            // image stays up until the new one is ready, rather than flashing the placeholder.
            if let cached = ImagePipeline.shared.cachedImage(for: url) {
                image = cached
                return
            }
            if let loaded = await ImagePipeline.shared.image(for: url, localFile: localFile) {
                image = loaded
            }
        }
    }
}
