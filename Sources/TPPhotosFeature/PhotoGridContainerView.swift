#if os(iOS)
import UIKit

/// Hosts the grid, with no blur or band behind the navigation bar: photos run straight up under
/// it.
final class PhotoGridContainerView: UIView {
    let collectionView: PhotoGridCollectionView

    init(collectionView: PhotoGridCollectionView) {
        self.collectionView = collectionView
        super.init(frame: .zero)
        collectionView.topEdgeEffect.isHidden = true
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(collectionView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        collectionView.frame = bounds
    }
}
#endif
