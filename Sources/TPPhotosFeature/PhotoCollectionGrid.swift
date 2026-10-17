#if os(iOS)
import SwiftUI
import TPCore
import UIKit

/// The iPhone/iPad photo grid: a `UICollectionView`, which is what the Photos app scrolls on.
///
/// Three rounds of tuning a SwiftUI `LazyVStack` still left it hitching: SwiftUI diffs the whole
/// row list whenever anything the grid reads changes, builds and lays out tiles as SwiftUI views,
/// and estimates the heights of rows it hasn't drawn. Here tiles are reused cells, frames are
/// arithmetic (`PhotoGridLayout`), thumbnails are fetched ahead of the scroll by the prefetcher,
/// and SwiftUI is not involved at all while scrolling.
struct PhotoCollectionGrid: UIViewRepresentable {
    /// Newest first, as the server pages them; shown oldest at the top.
    let photos: [Photo]
    let client: PhotosClient
    @Binding var columnLevel: Int
    let scrollToBottomSignal: Int
    let onSelect: (Photo) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(client: client)
    }

    func makeUIView(context: Context) -> PhotoGridCollectionView {
        let coordinator = context.coordinator
        let columns = PhotoGridDensity.columns(forLevel: columnLevel)
        let collectionView = PhotoGridCollectionView(frame: .zero, collectionViewLayout: PhotoGridLayout(columns: columns))
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.contentInsetAdjustmentBehavior = .always
        collectionView.register(PhotoGridCell.self, forCellWithReuseIdentifier: PhotoGridCell.reuseIdentifier)
        collectionView.dataSource = coordinator
        collectionView.delegate = coordinator
        collectionView.prefetchDataSource = coordinator
        collectionView.isPrefetchingEnabled = true

        let pinch = UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = coordinator
        collectionView.addGestureRecognizer(pinch)

        coordinator.collectionView = collectionView
        coordinator.columns = columns
        coordinator.photos = photos
        coordinator.scrollToBottomSignal = scrollToBottomSignal
        return collectionView
    }

    func updateUIView(_ collectionView: PhotoGridCollectionView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onSelect = onSelect
        coordinator.setColumnLevel = { columnLevel = $0 }
        coordinator.columnLevel = columnLevel
        coordinator.updateRefreshControl(context.environment.refresh)
        coordinator.update(photos: photos)

        let columns = PhotoGridDensity.columns(forLevel: columnLevel)
        if columns != coordinator.columns {
            coordinator.apply(columns: columns, anchorItem: nil)
        }
        if scrollToBottomSignal != coordinator.scrollToBottomSignal {
            coordinator.scrollToBottomSignal = scrollToBottomSignal
            coordinator.scrollToNewest()
        }
    }

    @MainActor
    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching, UIGestureRecognizerDelegate {
        /// Newest first; item `i` is `photos[photos.count - 1 - i]`.
        var photos: [Photo] = []
        var columns = PhotoGridDensity.columns(forLevel: 0)
        var columnLevel = 0
        var scrollToBottomSignal = 0
        var onSelect: (Photo) -> Void = { _ in }
        var setColumnLevel: (Int) -> Void = { _ in }
        weak var collectionView: PhotoGridCollectionView?

        private let loader: PhotoThumbnailLoader
        private var prefetches: [IndexPath: PhotoThumbnailLoader.Ticket] = [:]
        private var pinchConsumed = false
        private var refreshAction: RefreshAction?
        private var refreshControl: UIRefreshControl?

        init(client: PhotosClient) {
            loader = PhotoThumbnailLoader(client: client)
        }

        private func photo(at item: Int) -> Photo {
            photos[photos.count - 1 - item]
        }

        private var cornerRadius: CGFloat {
            columns >= 9 ? 0 : 4
        }

        private var pixels: Int {
            guard let collectionView, collectionView.bounds.width > 0 else { return PhotoThumbnailCache.pixelSize }
            let insets = collectionView.adjustedContentInset
            let side = PhotoGridLayout.itemSide(width: collectionView.bounds.width - insets.left - insets.right, columns: columns)
            return PhotoThumbnailCache.pixelSize(forTile: side, scale: collectionView.traitCollection.displayScale)
        }

        // MARK: Data

        /// Reloads for a new photo list (once per sync), keeping the photos on screen where they
        /// are: rows are cut from the newest end, so holding the distance from the bottom fixed
        /// means older photos landing above don't move anything.
        func update(photos newPhotos: [Photo]) {
            guard !Self.sameArray(newPhotos, photos), newPhotos != photos, let collectionView else { return }
            let distanceFromBottom = collectionView.contentSize.height - collectionView.contentOffset.y
            photos = newPhotos
            releasePrefetches()
            collectionView.reloadData()
            guard !collectionView.isPinnedToBottom else { return }
            collectionView.layoutIfNeeded()
            let insets = collectionView.adjustedContentInset
            let maxY = max(collectionView.contentSize.height + insets.bottom - collectionView.bounds.height, -insets.top)
            collectionView.contentOffset.y = min(max(collectionView.contentSize.height - distanceFromBottom, -insets.top), maxY)
        }

        /// `updateUIView` runs on every re-render of the gallery (e.g. each backup progress tick);
        /// when the store hasn't published a new list it's the same buffer, so skip comparing
        /// thousands of photos field by field.
        private static func sameArray(_ lhs: [Photo], _ rhs: [Photo]) -> Bool {
            lhs.count == rhs.count && lhs.withUnsafeBufferPointer { l in
                rhs.withUnsafeBufferPointer { r in l.baseAddress == r.baseAddress }
            }
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            photos.count
        }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PhotoGridCell.reuseIdentifier, for: indexPath)
            if let cell = cell as? PhotoGridCell {
                cell.configure(with: photo(at: indexPath.item), pixels: pixels, cornerRadius: cornerRadius, loader: loader)
            }
            return cell
        }

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            collectionView.deselectItem(at: indexPath, animated: false)
            onSelect(photo(at: indexPath.item))
        }

        // MARK: Prefetching

        func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            let pixels = self.pixels
            for indexPath in indexPaths where indexPath.item < photos.count && prefetches[indexPath] == nil {
                let photo = photo(at: indexPath.item)
                guard PhotoThumbnailCache.cachedCGImage(forChecksum: photo.checksum, pixels: pixels) == nil else { continue }
                prefetches[indexPath] = loader.request(photo, pixels: pixels)
            }
        }

        func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
            for indexPath in indexPaths {
                if let ticket = prefetches.removeValue(forKey: indexPath) { loader.release(ticket) }
            }
        }

        func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            // The cell holds its own claim now.
            if let ticket = prefetches.removeValue(forKey: indexPath) { loader.release(ticket) }
        }

        private func releasePrefetches() {
            for ticket in prefetches.values { loader.release(ticket) }
            prefetches.removeAll()
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            collectionView?.isPinnedToBottom = false
        }

        // MARK: Zoom

        // Two fingers that start moving before the pinch is recognised already belong to the
        // scroll view's pan; without this the pinch would never begin.
        nonisolated func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        @objc func handlePinch(_ pinch: UIPinchGestureRecognizer) {
            switch pinch.state {
            case .changed:
                guard !pinchConsumed else { return }
                let delta = pinch.scale > 1.25 ? -1 : pinch.scale < 0.8 ? 1 : 0
                guard delta != 0 else { return }
                pinchConsumed = true
                let newLevel = min(max(columnLevel + delta, 0), PhotoGridDensity.columnLevels.count - 1)
                guard newLevel != columnLevel, let collectionView else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                // Zoom around the photo under the fingers, like Photos.
                let anchor = collectionView.indexPathForItem(at: pinch.location(in: collectionView))?.item
                columnLevel = newLevel
                apply(columns: PhotoGridDensity.columns(forLevel: newLevel), anchorItem: anchor)
                setColumnLevel(newLevel)
            case .ended, .cancelled, .failed:
                pinchConsumed = false
            default:
                break
            }
        }

        func apply(columns newColumns: Int, anchorItem: Int?) {
            guard let collectionView, newColumns != columns else { return }
            columns = newColumns
            // The zoom's anchor decides where the grid lands now, not the bottom pin.
            collectionView.isPinnedToBottom = false
            let newLayout = PhotoGridLayout(columns: newColumns)
            newLayout.anchorItem = anchorItem ?? centerItem()
            releasePrefetches()
            collectionView.setCollectionViewLayout(newLayout, animated: !UIAccessibility.isReduceMotionEnabled) { _ in
                newLayout.anchorItem = nil
            }
            // Cells already on screen switch to the new corner radius and thumbnail size.
            let pixels = self.pixels
            for case let cell as PhotoGridCell in collectionView.visibleCells {
                guard let indexPath = collectionView.indexPath(for: cell) else { continue }
                cell.configure(with: photo(at: indexPath.item), pixels: pixels, cornerRadius: cornerRadius, loader: loader)
            }
        }

        private func centerItem() -> Int? {
            guard let collectionView else { return nil }
            let insets = collectionView.adjustedContentInset
            let visibleHeight = collectionView.bounds.height - insets.top - insets.bottom
            let center = CGPoint(x: collectionView.bounds.midX, y: collectionView.contentOffset.y + insets.top + visibleHeight / 2)
            if let item = collectionView.indexPathForItem(at: center)?.item { return item }
            let visible = collectionView.indexPathsForVisibleItems.map(\.item).sorted()
            return visible.isEmpty ? nil : visible[visible.count / 2]
        }

        // MARK: Scrolling

        func scrollToNewest() {
            // The system's own "tap the tab again" scroll-to-top fires too; going to the bottom a
            // beat later makes sure ours is the one that wins.
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(80))
                self?.collectionView?.scrollToBottom(animated: true)
            }
        }

        func updateRefreshControl(_ action: RefreshAction?) {
            refreshAction = action
            guard let collectionView else { return }
            if action != nil, refreshControl == nil {
                let control = UIRefreshControl()
                control.addTarget(self, action: #selector(handleRefresh(_:)), for: .valueChanged)
                collectionView.refreshControl = control
                refreshControl = control
            } else if action == nil, refreshControl != nil {
                collectionView.refreshControl = nil
                refreshControl = nil
            }
        }

        @objc private func handleRefresh(_ control: UIRefreshControl) {
            guard let refreshAction else {
                control.endRefreshing()
                return
            }
            Task {
                await refreshAction()
                control.endRefreshing()
            }
        }
    }
}

/// Opens on the newest photos at the bottom, and stays there — through the bars' insets settling
/// and the first sync landing — until the user first scrolls.
final class PhotoGridCollectionView: UICollectionView {
    var isPinnedToBottom = true

    override func layoutSubviews() {
        super.layoutSubviews()
        guard isPinnedToBottom, bounds.height > 0, contentSize.height > 0 else { return }
        let insets = adjustedContentInset
        let bottom = max(contentSize.height + insets.bottom - bounds.height, -insets.top)
        if contentOffset.y != bottom { contentOffset.y = bottom }
    }

    func scrollToBottom(animated: Bool) {
        let insets = adjustedContentInset
        let y = max(contentSize.height + insets.bottom - bounds.height, -insets.top)
        setContentOffset(CGPoint(x: contentOffset.x, y: y), animated: animated)
    }
}
#endif
