import CoreGraphics
import Darwin
import Foundation
import ImageIO

/// Every photo's thumbnail as a ready-to-draw bitmap, the way Apple's Photos app keeps its own:
/// 128×128 pixels already decoded into the screen's pixel format (32-bit BGRA, premultiplied),
/// packed into fixed-size slots of a few large files that are memory-mapped once. Showing a
/// thumbnail is just wrapping its slot's bytes in a `CGImage` — no file to open, nothing to
/// decode — so tiles fill in on the frame they appear, however fast the grid moves.
///
/// The JPEGs stay the source of truth (and the sharper 256px picture for the largest tiles); this
/// is filled from them as they're stored or downloaded, plus a one-time pass over the ones
/// already on the device. Being file-backed, the mapped pages don't count against the app's
/// memory: the system drops and re-reads them as needed. About 64 KB per photo on disk.
final class PhotoThumbnailTable: @unchecked Sendable {
    static let shared = PhotoThumbnailTable(directory: PhotoThumbnailCache.directoryURL)

    /// Pixel size of every slot.
    static let side = 128
    private static let bytesPerRow = side * 4
    private static let slotSize = side * side * 4
    /// 64 MB per file: big enough to keep the file count low, small enough to grow in steps.
    private static let slotsPerSegment = 1024
    private static let segmentSize = slotSize * slotsPerSegment
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let bitmapInfo = CGBitmapInfo(
        rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
    )

    private struct Index: Codable {
        var slots: [String: Int] = [:]
        var nextSlot = 0
    }

    private final class Segment {
        let descriptor: Int32
        let base: UnsafeRawPointer

        init(descriptor: Int32, base: UnsafeRawPointer) {
            self.descriptor = descriptor
            self.base = base
        }
    }

    private let directory: URL
    private let indexURL: URL
    private let lock = NSLock()
    private var index: Index
    private var segments: [Int: Segment] = [:]
    /// Checksums being written right now, so two writers never take two slots for one photo.
    private var inFlight: Set<String> = []
    private var saveScheduled = false

    init(directory: URL) {
        self.directory = directory
        indexURL = directory.appendingPathComponent("Table128-v1.index")
        index = (try? Data(contentsOf: indexURL)).flatMap { try? JSONDecoder().decode(Index.self, from: $0) } ?? Index()
        if !segmentsCover(index) {
            // Files missing or cut short (cleared storage, an interrupted first write): start over
            // rather than hand out slots full of garbage.
            removeSegmentFiles()
            index = Index()
        }
    }

    // MARK: Reading

    func contains(_ checksum: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return index.slots[checksum] != nil
    }

    /// The thumbnail, ready to draw, or `nil` if it isn't in the table yet. Cheap enough to call
    /// for every tile as it's configured.
    func image(forChecksum checksum: String) -> CGImage? {
        lock.lock()
        let slot = index.slots[checksum]
        let segment = slot.flatMap { try? mappedSegment($0 / Self.slotsPerSegment) }
        lock.unlock()
        guard let slot, let segment else { return nil }
        let bytes = segment.base + (slot % Self.slotsPerSegment) * Self.slotSize
        // No copy: the image reads straight from the mapping, which lives as long as the app.
        guard let provider = CGDataProvider(dataInfo: nil, data: bytes, size: Self.slotSize, releaseData: { _, _, _ in }) else {
            return nil
        }
        return CGImage(
            width: Self.side,
            height: Self.side,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: Self.bytesPerRow,
            space: Self.colorSpace,
            bitmapInfo: Self.bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    // MARK: Writing

    /// Decodes a stored or downloaded thumbnail into the table, unless it's already there.
    /// Synchronous decoding and file I/O: call it off the main thread.
    @discardableResult
    func insert(checksum: String, from source: CGImageSource) -> Bool {
        lock.lock()
        if index.slots[checksum] != nil || inFlight.contains(checksum) {
            lock.unlock()
            return true
        }
        inFlight.insert(checksum)
        lock.unlock()

        var slot: Int?
        defer {
            lock.lock()
            inFlight.remove(checksum)
            if let slot {
                index.slots[checksum] = slot
                scheduleSave()
            }
            lock.unlock()
        }

        guard let pixels = Self.render(source) else { return false }
        lock.lock()
        let candidate = index.nextSlot
        let segment = try? mappedSegment(candidate / Self.slotsPerSegment)
        if segment != nil { index.nextSlot += 1 }
        lock.unlock()
        guard let segment else { return false }

        let offset = off_t((candidate % Self.slotsPerSegment) * Self.slotSize)
        let written = pixels.withUnsafeBytes { pwrite(segment.descriptor, $0.baseAddress, Self.slotSize, offset) }
        guard written == Self.slotSize else { return false }
        // Only indexed once its bytes are in place, so a reader never sees a half-written slot.
        slot = candidate
        return true
    }

    @discardableResult
    func insert(checksum: String, fileURL: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return false }
        return insert(checksum: checksum, from: source)
    }

    @discardableResult
    func insert(checksum: String, data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return insert(checksum: checksum, from: source)
    }

    /// Decodes into a 128×128 BGRA buffer, cropped to fill the square (thumbnails made during
    /// backup keep the photo's own proportions).
    private static func render(_ source: CGImageSource) -> Data? {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? Int) ?? side
        let height = (properties?[kCGImagePropertyPixelHeight] as? Int) ?? side
        // The longest side's size that makes the shortest side reach `side`.
        let aspect = Double(max(width, height)) / Double(max(min(width, height), 1))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int((Double(side) * aspect).rounded(.up)),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        var pixels = Data(count: slotSize)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            let scale = CGFloat(side) / CGFloat(max(min(image.width, image.height), 1))
            let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            let origin = CGPoint(x: (CGFloat(side) - size.width) / 2, y: (CGFloat(side) - size.height) / 2)
            context.draw(image, in: CGRect(origin: origin, size: size))
            return true
        }
        return drawn ? pixels : nil
    }

    // MARK: Files

    private func segmentURL(_ number: Int) -> URL {
        directory.appendingPathComponent("Table128-v1-\(number).bin")
    }

    /// Opens (creating and sizing if needed) and maps a segment file. Mappings are never torn
    /// down: images handed out point into them. Call with `lock` held.
    private func mappedSegment(_ number: Int) throws -> Segment {
        if let segment = segments[number] { return segment }
        let path = segmentURL(number).path
        let descriptor = open(path, O_RDWR | O_CREAT, 0o644)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        var info = stat()
        if fstat(descriptor, &info) != 0 || info.st_size < off_t(Self.segmentSize) {
            // Sparse: disk space is only used as slots are written.
            guard ftruncate(descriptor, off_t(Self.segmentSize)) == 0 else {
                close(descriptor)
                throw POSIXError(.ENOSPC)
            }
        }
        guard let base = mmap(nil, Self.segmentSize, PROT_READ, MAP_SHARED, descriptor, 0), base != MAP_FAILED else {
            close(descriptor)
            throw POSIXError(.ENOMEM)
        }
        let segment = Segment(descriptor: descriptor, base: UnsafeRawPointer(base))
        segments[number] = segment
        return segment
    }

    private func segmentsCover(_ index: Index) -> Bool {
        guard index.nextSlot > 0 else { return true }
        let lastSegment = (index.nextSlot - 1) / Self.slotsPerSegment
        return (0...lastSegment).allSatisfy { number in
            let size = (try? segmentURL(number).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return size >= Self.segmentSize
        }
    }

    private func removeSegmentFiles() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix("Table128-v1-") {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Writes the index a couple of seconds after the last insert rather than after each one.
    /// Call with `lock` held.
    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) { [self] in
            saveIndex()
        }
    }

    /// Writes the index now (the scheduled save does this on its own).
    func saveIndex() {
        lock.lock()
        saveScheduled = false
        let snapshot = index
        lock.unlock()
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }
}
