import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum QRCodeGenerator {
    static func image(for string: String, scale: CGFloat = 8) -> Image? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }

        #if os(macOS)
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
        return Image(nsImage: nsImage)
        #else
        return Image(uiImage: UIImage(cgImage: cgImage))
        #endif
    }
}
