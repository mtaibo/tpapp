#if os(iOS)
import UIKit

/// The destination grid of a zoom, scaled as a whole about one point, like the Photos app: the
/// grid always keeps its shape — at `scale` 1/ratio its tiles are exactly the size of the grid
/// being left (and line up with it, see `PhotoGridZoomController`), and they grow or shrink with
/// the fingers until, at 1, this is the resting `PhotoGridLayout` frame for frame.
///
/// Only tiles whose scaled frame is in the requested rect are built, so this costs what's on
/// screen, not the library size.
final class PhotoGridZoomLayout: UICollectionViewLayout {
    let geometry: PhotoGridGeometry
    /// The content-space point the grid scales about.
    let pivot: CGPoint
    var scale: CGFloat = 1

    init(geometry: PhotoGridGeometry, pivot: CGPoint) {
        self.geometry = geometry
        self.pivot = pivot
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var collectionViewContentSize: CGSize {
        CGSize(width: geometry.width, height: geometry.contentHeight)
    }

    func frame(forItem item: Int) -> CGRect {
        let frame = geometry.frame(forItem: item)
        return CGRect(
            x: pivot.x + (frame.minX - pivot.x) * scale,
            y: pivot.y + (frame.minY - pivot.y) * scale,
            width: frame.width * scale,
            height: frame.height * scale
        )
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard scale > 0 else { return [] }
        // The rect in the unscaled grid's coordinates.
        let minY = pivot.y + (rect.minY - pivot.y) / scale
        let maxY = pivot.y + (rect.maxY - pivot.y) / scale
        return geometry.items(fromY: minY, toY: maxY).compactMap { item in
            let frame = frame(forItem: item)
            // Tiles pushed off the sides while zoomed in aren't built at all.
            return frame.intersects(rect) ? makeAttributes(item: item, frame: frame) : nil
        }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard indexPath.item >= 0, indexPath.item < geometry.itemCount else { return nil }
        return makeAttributes(item: indexPath.item, frame: frame(forItem: indexPath.item))
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        false
    }

    private func makeAttributes(item: Int, frame: CGRect) -> UICollectionViewLayoutAttributes {
        let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: item, section: 0))
        attributes.frame = frame
        return attributes
    }
}
#endif
