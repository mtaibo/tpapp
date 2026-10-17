#if os(iOS)
import UIKit

/// The resting grid for one column count (see `PhotoGridGeometry`). Every frame is arithmetic on
/// the item index, so this only ever builds attributes for the rows in the rect UIKit asks about —
/// a flow layout measures all of a 30,000-photo library up front and again on every invalidation.
final class PhotoGridLayout: UICollectionViewLayout {
    let columns: Int
    private(set) var geometry: PhotoGridGeometry

    init(columns: Int) {
        self.columns = columns
        self.geometry = PhotoGridGeometry(columns: columns, width: 0, itemCount: 0, scale: 2)
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepare() {
        super.prepare()
        guard let collectionView else { return }
        geometry = Self.geometry(columns: columns, in: collectionView)
    }

    /// The geometry `columns` would have in `collectionView` right now.
    static func geometry(columns: Int, in collectionView: UICollectionView) -> PhotoGridGeometry {
        let insets = collectionView.adjustedContentInset
        return PhotoGridGeometry(
            columns: columns,
            width: collectionView.bounds.width - insets.left - insets.right,
            itemCount: collectionView.numberOfSections > 0 ? collectionView.numberOfItems(inSection: 0) : 0,
            scale: collectionView.traitCollection.displayScale
        )
    }

    override var collectionViewContentSize: CGSize {
        CGSize(width: geometry.width, height: geometry.contentHeight)
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        geometry.items(fromY: rect.minY, toY: rect.maxY).map(makeAttributes(item:))
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard indexPath.item >= 0, indexPath.item < geometry.itemCount else { return nil }
        return makeAttributes(item: indexPath.item)
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        newBounds.width != collectionView?.bounds.width
    }

    private func makeAttributes(item: Int) -> UICollectionViewLayoutAttributes {
        let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: item, section: 0))
        attributes.frame = geometry.frame(forItem: item)
        return attributes
    }
}
#endif
