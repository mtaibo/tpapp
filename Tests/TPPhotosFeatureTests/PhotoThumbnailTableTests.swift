import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import TPPhotosFeature

@Suite struct PhotoThumbnailTableTests {
    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("table-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A JPEG filled with `center`, with a `border`-coloured band `band` pixels wide at the left
    /// and right edges.
    private func jpeg(width: Int, height: Int, center: (CGFloat, CGFloat, CGFloat), border: (CGFloat, CGFloat, CGFloat), band: Int = 0) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(red: border.0, green: border.1, blue: border.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(red: center.0, green: center.1, blue: center.2, alpha: 1)
        context.fill(CGRect(x: band, y: 0, width: width - 2 * band, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    /// The RGB of one pixel of `image`, read back through a plain RGBA context.
    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> (Int, Int, Int) {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(
            data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
    }

    private func close(_ a: (Int, Int, Int), _ b: (Int, Int, Int)) -> Bool {
        abs(a.0 - b.0) < 24 && abs(a.1 - b.1) < 24 && abs(a.2 - b.2) < 24
    }

    @Test func insertedThumbnailReadsBackAsA128PixelBitmap() throws {
        let table = PhotoThumbnailTable(directory: try makeDirectory())
        #expect(table.image(forChecksum: "a") == nil)
        #expect(table.insert(checksum: "a", data: try jpeg(width: 256, height: 256, center: (1, 0, 0), border: (1, 0, 0))))
        #expect(table.contains("a"))
        let image = try #require(table.image(forChecksum: "a"))
        #expect(image.width == 128 && image.height == 128)
        #expect(close(try pixel(image, x: 64, y: 64), (255, 0, 0)))
    }

    @Test func eachPhotoGetsItsOwnSlot() throws {
        let table = PhotoThumbnailTable(directory: try makeDirectory())
        table.insert(checksum: "red", data: try jpeg(width: 256, height: 256, center: (1, 0, 0), border: (1, 0, 0)))
        table.insert(checksum: "blue", data: try jpeg(width: 256, height: 256, center: (0, 0, 1), border: (0, 0, 1)))
        #expect(close(try pixel(try #require(table.image(forChecksum: "red")), x: 10, y: 10), (255, 0, 0)))
        #expect(close(try pixel(try #require(table.image(forChecksum: "blue")), x: 10, y: 10), (0, 0, 255)))
    }

    @Test func nonSquareThumbnailIsCroppedToFillTheSquare() throws {
        let table = PhotoThumbnailTable(directory: try makeDirectory())
        // 400×200 with 100px green bands either side: cropping to the middle square drops them.
        table.insert(checksum: "wide", data: try jpeg(width: 400, height: 200, center: (1, 0, 0), border: (0, 1, 0), band: 100))
        let image = try #require(table.image(forChecksum: "wide"))
        #expect(close(try pixel(image, x: 2, y: 64), (255, 0, 0)))
        #expect(close(try pixel(image, x: 125, y: 64), (255, 0, 0)))
    }

    @Test func indexSurvivesReopening() throws {
        let directory = try makeDirectory()
        let table = PhotoThumbnailTable(directory: directory)
        table.insert(checksum: "kept", data: try jpeg(width: 256, height: 256, center: (0, 0, 1), border: (0, 0, 1)))
        table.saveIndex()

        let reopened = PhotoThumbnailTable(directory: directory)
        #expect(reopened.contains("kept"))
        #expect(close(try pixel(try #require(reopened.image(forChecksum: "kept")), x: 64, y: 64), (0, 0, 255)))
    }

    @Test func missingDataFilesResetTheIndex() throws {
        let directory = try makeDirectory()
        let table = PhotoThumbnailTable(directory: directory)
        table.insert(checksum: "gone", data: try jpeg(width: 256, height: 256, center: (1, 0, 0), border: (1, 0, 0)))
        table.saveIndex()
        for file in try FileManager.default.contentsOfDirectory(atPath: directory.path) where file.hasSuffix(".bin") {
            try FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }

        let reopened = PhotoThumbnailTable(directory: directory)
        #expect(!reopened.contains("gone"))
        #expect(reopened.image(forChecksum: "gone") == nil)
    }
}
