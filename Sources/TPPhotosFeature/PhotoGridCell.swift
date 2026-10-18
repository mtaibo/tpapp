#if os(iOS)
import TPCore
import UIKit

/// One tile: a plain image view, reused as tiles scroll by. Draws from the memory cache on the
/// same frame it's configured when it can; otherwise shows a fill until its load lands.
final class PhotoGridCell: UICollectionViewCell {
    static let reuseIdentifier = "PhotoGridCell"

    private let imageView = UIImageView()
    private(set) var photo: Photo?
    private var pixels = 0
    private var ticket: PhotoThumbnailLoader.Ticket?
    private weak var loader: PhotoThumbnailLoader?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .tertiarySystemFill
        contentView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.frame = contentView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(imageView)
        isAccessibilityElement = true
        accessibilityTraits = [.image, .button]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Built only when VoiceOver asks, not for every tile that scrolls past.
    override var accessibilityLabel: String? {
        get { photo.map(PhotoGrid.accessibilityLabel(for:)) }
        set {}
    }

    override var isHighlighted: Bool {
        didSet { imageView.alpha = isHighlighted ? 0.7 : 1 }
    }

    func configure(with photo: Photo, pixels: Int, cornerRadius: CGFloat, loader: PhotoThumbnailLoader) {
        contentView.layer.cornerRadius = cornerRadius
        let samePhoto = photo.checksum == self.photo?.checksum
        guard !samePhoto || pixels != self.pixels else { return }
        cancelLoad()
        self.photo = photo
        self.pixels = pixels
        self.loader = loader

        if let cached = PhotoThumbnailCache.cachedCGImage(forChecksum: photo.checksum, pixels: pixels)
            ?? PhotoThumbnailCache.tableCGImage(forChecksum: photo.checksum, pixels: pixels) {
            imageView.image = UIImage(cgImage: cached)
            return
        }
        // Show what's at hand straight away — the table's 128px copy, or another decoded size —
        // while the sharp one decodes, so neither a big tile nor a zoom step is ever blank.
        if !samePhoto {
            imageView.image = PhotoThumbnailCache.anyCachedCGImage(forChecksum: photo.checksum).map(UIImage.init(cgImage:))
        }
        ticket = loader.request(photo, pixels: pixels, priority: .visible) { [weak self] image in
            guard let self, self.photo?.checksum == photo.checksum else { return }
            self.ticket = nil
            if let image { self.imageView.image = UIImage(cgImage: image) }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancelLoad()
        photo = nil
        pixels = 0
        imageView.image = nil
        imageView.alpha = 1
    }

    private func cancelLoad() {
        if let ticket { loader?.release(ticket) }
        ticket = nil
    }
}
#endif
