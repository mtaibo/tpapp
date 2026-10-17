#if os(iOS)
import UIKit

/// A uniform square grid, newest photo at the bottom right. Rows are cut from the newest end, so
/// the partial row is the oldest one at the very top (right-aligned): older photos arriving only
/// ever add rows above, and no tile below them moves.
///
/// Every frame is plain arithmetic on the item index, so this only ever builds attributes for the
/// rows in the rect UIKit asks about — a flow layout measures all of a 30,000-photo library up
/// front and again on every invalidation.
final class PhotoGridLayout: UICollectionViewLayout {
    let columns: Int
    let spacing: CGFloat
    /// The item to keep in the middle of the screen when this layout replaces another (pinch or
    /// Zoom In/Out), instead of wherever the old offset lands in the new layout.
    var anchorItem: Int?

    private var itemCount = 0
    private var leadingBlanks = 0
    private var rowCount = 0
    private var width: CGFloat = 0
    private var pitch: CGFloat = 0
    private var scale: CGFloat = 2

    init(columns: Int) {
        self.columns = columns
        self.spacing = Self.spacing(forColumns: columns)
        super.init()
    }

    static func spacing(forColumns columns: Int) -> CGFloat {
        columns >= 9 ? 1 : 2
    }

    /// A tile's width in points for `columns` across `width`, before this layout has prepared.
    static func itemSide(width: CGFloat, columns: Int) -> CGFloat {
        let spacing = spacing(forColumns: columns)
        return max((width + spacing) / CGFloat(columns) - spacing, 0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepare() {
        super.prepare()
        guard let collectionView else { return }
        itemCount = collectionView.numberOfSections > 0 ? collectionView.numberOfItems(inSection: 0) : 0
        leadingBlanks = (columns - itemCount % columns) % columns
        rowCount = (itemCount + leadingBlanks + columns - 1) / columns
        let insets = collectionView.adjustedContentInset
        width = collectionView.bounds.width - insets.left - insets.right
        pitch = (width + spacing) / CGFloat(columns)
        scale = collectionView.traitCollection.displayScale > 0 ? collectionView.traitCollection.displayScale : 2
    }

    override var collectionViewContentSize: CGSize {
        CGSize(width: width, height: max(CGFloat(rowCount) * pitch - spacing, 0))
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard itemCount > 0, pitch > 0 else { return [] }
        let firstRow = max(Int((rect.minY / pitch).rounded(.down)), 0)
        let lastRow = min(Int((rect.maxY / pitch).rounded(.down)), rowCount - 1)
        guard firstRow <= lastRow else { return [] }
        var attributes: [UICollectionViewLayoutAttributes] = []
        attributes.reserveCapacity((lastRow - firstRow + 1) * columns)
        for slot in (firstRow * columns)...(lastRow * columns + columns - 1) {
            let item = slot - leadingBlanks
            guard item >= 0, item < itemCount else { continue }
            attributes.append(makeAttributes(item: item))
        }
        return attributes
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard indexPath.item >= 0, indexPath.item < itemCount else { return nil }
        return makeAttributes(item: indexPath.item)
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        newBounds.width != collectionView?.bounds.width
    }

    override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint) -> CGPoint {
        guard let anchorItem, anchorItem < itemCount, let collectionView else {
            return super.targetContentOffset(forProposedContentOffset: proposedContentOffset)
        }
        let insets = collectionView.adjustedContentInset
        let visibleHeight = collectionView.bounds.height - insets.top - insets.bottom
        let target = frame(forItem: anchorItem).midY - insets.top - visibleHeight / 2
        let minY = -insets.top
        let maxY = max(collectionViewContentSize.height + insets.bottom - collectionView.bounds.height, minY)
        return CGPoint(x: proposedContentOffset.x, y: min(max(target, minY), maxY))
    }

    func frame(forItem item: Int) -> CGRect {
        let slot = item + leadingBlanks
        let row = CGFloat(slot / columns)
        let column = CGFloat(slot % columns)
        // Snapped to whole pixels so neighbouring tiles never blur or leave uneven seams.
        let minX = pixelRound(column * pitch)
        let maxX = pixelRound(column * pitch + pitch - spacing)
        let minY = pixelRound(row * pitch)
        let maxY = pixelRound(row * pitch + pitch - spacing)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func makeAttributes(item: Int) -> UICollectionViewLayoutAttributes {
        let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: item, section: 0))
        attributes.frame = frame(forItem: item)
        return attributes
    }

    private func pixelRound(_ value: CGFloat) -> CGFloat {
        (value * scale).rounded() / scale
    }
}
#endif
