#if os(iOS)
import UIKit

/// Hosts the grid, with no blur or band behind the navigation bar: photos run straight up under
/// it. Also reports when the grid leaves the screen.
final class PhotoGridContainerView: UIView {
    let collectionView: PhotoGridCollectionView
    /// Called when the grid leaves the screen (another tab is picked).
    var onLeaveWindow: () -> Void = {}

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

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { onLeaveWindow() }
    }
}
#endif
