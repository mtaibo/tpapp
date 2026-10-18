#if os(iOS)
import SwiftUI
import TPCore
import UIKit

/// The iPhone/iPad photo grid: a `UICollectionView`, which is what the Photos app scrolls on.
///
/// Three rounds of tuning a SwiftUI `LazyVStack` still left it hitching: SwiftUI diffs the whole
/// row list whenever anything the grid reads changes, builds and lays out tiles as SwiftUI views,
/// and estimates the heights of rows it hasn't drawn. Here tiles are reused cells, frames are
/// arithmetic (`PhotoGridLayout`), thumbnails are loaded ahead of the scroll (see `updateLookahead`),
/// and SwiftUI is not involved at all while scrolling.
struct PhotoCollectionGrid: UIViewRepresentable {
    /// Newest first, as the server pages them; shown oldest at the top.
    let photos: [Photo]
    let client: PhotosClient
    @Binding var columnLevel: Int
    let scrollToBottomSignal: Int
    let onSelect: (Photo) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(client: client, level: columnLevel)
    }

    func makeUIView(context: Context) -> PhotoGridContainerView {
        let coordinator = context.coordinator
        let columns = PhotoGridDensity.columns(forLevel: columnLevel)
        let collectionView = PhotoGridCollectionView(frame: .zero, collectionViewLayout: PhotoGridLayout(columns: columns))
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.contentInsetAdjustmentBehavior = .always
        // Breathing room between the newest photos and the tab bar, like Photos.
        collectionView.contentInset.bottom = 20
        collectionView.register(PhotoGridCell.self, forCellWithReuseIdentifier: PhotoGridCell.reuseIdentifier)
        collectionView.dataSource = coordinator
        collectionView.delegate = coordinator
        collectionView.isPrefetchingEnabled = true

        let pinch = UIPinchGestureRecognizer(target: coordinator.zoom, action: #selector(PhotoGridZoomController.handlePinch(_:)))
        pinch.delegate = coordinator
        collectionView.addGestureRecognizer(pinch)

        coordinator.collectionView = collectionView
        coordinator.zoom.collectionView = collectionView
        collectionView.isGridZooming = { [weak zoom = coordinator.zoom] in zoom?.isZooming ?? false }
        coordinator.columns = columns
        coordinator.photos = photos
        coordinator.scrollToBottomSignal = scrollToBottomSignal

        return PhotoGridContainerView(collectionView: collectionView)
    }

    func updateUIView(_ container: PhotoGridContainerView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onSelect = onSelect
        coordinator.setColumnLevel = { columnLevel = $0 }
        coordinator.updateRefreshControl(context.environment.refresh)
        coordinator.update(photos: photos)

        // Zoom In/Out from the menu (a pinch has already settled on its level by the time it
        // writes `columnLevel`, so this is a no-op for those).
        if columnLevel != coordinator.zoom.level {
            coordinator.zoom.zoom(toLevel: columnLevel)
        }
        if scrollToBottomSignal != coordinator.scrollToBottomSignal {
            coordinator.scrollToBottomSignal = scrollToBottomSignal
            coordinator.scrollToNewest()
        }
    }

    @MainActor
    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate, UIGestureRecognizerDelegate {
        /// Newest first; item `i` is `photos[photos.count - 1 - i]`.
        var photos: [Photo] = []
        var columns: Int
        var scrollToBottomSignal = 0
        var onSelect: (Photo) -> Void = { _ in }
        var setColumnLevel: (Int) -> Void = { _ in }
        weak var collectionView: PhotoGridCollectionView?

        private let loader: PhotoThumbnailLoader
        /// Loads for tiles just ahead of the scroll, by item.
        private var lookahead: [Int: PhotoThumbnailLoader.Ticket] = [:]
        private var lookaheadKey: (bucket: Int, direction: Int)?
        private var lastLookaheadY: CGFloat = 0
        let zoom: PhotoGridZoomController
        /// A sync that landed mid-zoom; reloading would pull the items out from under it.
        private var pendingPhotos: [Photo]?
        private var refreshAction: RefreshAction?
        private var refreshControl: UIRefreshControl?

        init(client: PhotosClient, level: Int) {
            loader = PhotoThumbnailLoader(client: client)
            columns = PhotoGridDensity.columns(forLevel: level)
            zoom = PhotoGridZoomController(level: level)
            super.init()
            zoom.onLevelCommitted = { [weak self] level in self?.levelCommitted(level) }
            zoom.onZoomEnded = { [weak self] in
                guard let self, let pending = self.pendingPhotos else { return }
                self.pendingPhotos = nil
                self.update(photos: pending)
            }
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
            let side = PhotoGridGeometry.itemSide(width: collectionView.bounds.width - insets.left - insets.right, columns: columns)
            return PhotoThumbnailCache.pixelSize(forTile: side, scale: collectionView.traitCollection.displayScale)
        }

        // MARK: Data

        /// Reloads for a new photo list (once per sync), keeping the photos on screen where they
        /// are: rows are cut from the newest end, so holding the distance from the bottom fixed
        /// means older photos landing above don't move anything.
        func update(photos newPhotos: [Photo]) {
            guard !Self.sameArray(newPhotos, photos), newPhotos != photos, let collectionView else { return }
            guard !zoom.isZooming else {
                pendingPhotos = newPhotos
                return
            }
            let distanceFromBottom = collectionView.contentSize.height - collectionView.contentOffset.y
            photos = newPhotos
            releaseLookahead()
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
            guard !zoom.isZooming else { return }
            // In the dense grids a tap closes in on the photo (31 → 15 → 5 columns) instead of
            // opening it; photos open from 5 columns or fewer.
            if let target = PhotoGridDensity.tapZoomLevel(fromLevel: zoom.level),
               let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame {
                zoom.zoom(toLevel: target, around: CGPoint(x: frame.midX, y: frame.midY), duration: 0.45)
            } else {
                onSelect(photo(at: indexPath.item))
            }
        }

        // MARK: Look-ahead

        /// Loads the thumbnails about a screen and a half ahead in the direction of the scroll, at
        /// lower priority than the tiles on screen, so a fling lands on tiles that are already
        /// decoded. UIKit's own prefetching looks only a row or two ahead, which a fast fling
        /// outruns. Recomputed every quarter screen, not every frame.
        private func updateLookahead(in collectionView: UICollectionView) {
            let y = collectionView.contentOffset.y
            let delta = y - lastLookaheadY
            lastLookaheadY = y
            guard delta != 0, !zoom.isZooming, collectionView.bounds.height > 0 else { return }
            let height = collectionView.bounds.height
            let direction = delta > 0 ? 1 : -1
            let key = (bucket: Int((y / (height / 4)).rounded(.down)), direction: direction)
            guard lookaheadKey?.bucket != key.bucket || lookaheadKey?.direction != key.direction else { return }
            lookaheadKey = key

            let bounds = collectionView.bounds
            let window = direction > 0
                ? CGRect(x: bounds.minX, y: bounds.maxY, width: bounds.width, height: height * 1.5)
                : CGRect(x: bounds.minX, y: bounds.minY - height * 1.5, width: bounds.width, height: height * 1.5)
            let items = Set((collectionView.collectionViewLayout.layoutAttributesForElements(in: window) ?? []).map(\.indexPath.item))

            for (item, ticket) in lookahead where !items.contains(item) {
                loader.release(ticket)
                lookahead[item] = nil
            }
            let pixels = self.pixels
            for item in items where lookahead[item] == nil && item < photos.count {
                let photo = photo(at: item)
                guard PhotoThumbnailCache.cachedCGImage(forChecksum: photo.checksum, pixels: pixels) == nil,
                      pixels > PhotoThumbnailTable.side || !PhotoThumbnailTable.shared.contains(photo.checksum) else { continue }
                lookahead[item] = loader.request(photo, pixels: pixels, priority: .lookahead) { _ in }
            }
        }

        func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            // The cell holds its own claim now.
            if let ticket = lookahead.removeValue(forKey: indexPath.item) { loader.release(ticket) }
        }

        private func releaseLookahead() {
            for ticket in lookahead.values { loader.release(ticket) }
            lookahead.removeAll()
            lookaheadKey = nil
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            if let collectionView = scrollView as? UICollectionView { updateLookahead(in: collectionView) }
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            collectionView?.isPinnedToBottom = false
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { collectionView?.scrollCameToRest() }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            collectionView?.scrollCameToRest()
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

        private func levelCommitted(_ level: Int) {
            guard let collectionView else { return }
            columns = PhotoGridDensity.columns(forLevel: level)
            releaseLookahead()
            // Cells already on screen switch to the new corner radius and thumbnail size.
            let pixels = self.pixels
            for case let cell as PhotoGridCell in collectionView.visibleCells {
                guard let indexPath = collectionView.indexPath(for: cell) else { continue }
                cell.configure(with: photo(at: indexPath.item), pixels: pixels, cornerRadius: cornerRadius, loader: loader)
            }
            setColumnLevel(level)
        }

        // MARK: Scrolling

        func scrollToNewest() {
            guard let collectionView, !zoom.isZooming else { return }
            collectionView.scrollToBottom(animated: true)
        }

        /// Re-tapping the Photos tab (and tapping the status bar) asks the scroll view to go to
        /// the top — the oldest photos here. Racing that with a delayed scroll back down used to
        /// lose now and then, sending the grid all the way up and then back down. The system
        /// scroll is refused instead, and the grid goes straight to where it starts: the newest
        /// photos at the bottom.
        func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
            scrollToNewest()
            return false
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
    /// A zoom owns the offset while it runs.
    var isGridZooming: () -> Bool = { false }

    private var lastInsets: UIEdgeInsets?
    /// An inset change that landed mid-scroll, to settle once the scroll comes to rest.
    private var pendingBottomFix: CGFloat?

    private func maxOffsetY(for insets: UIEdgeInsets) -> CGFloat {
        max(contentSize.height + insets.bottom - bounds.height, -insets.top)
    }

    /// The tab bar can change the bottom inset as it minimizes and restores. UIKit keeps the
    /// offset where it was, so a grid sitting on its newest photos either slid behind the bar or
    /// left a gap under the last row — until switching tabs re-laid it out. Keep it on its
    /// bottom edge instead, and never leave blank space below the last row.
    override func adjustedContentInsetDidChange() {
        super.adjustedContentInsetDidChange()
        let insets = adjustedContentInset
        defer { lastInsets = insets }
        guard let old = lastInsets, old != insets, contentSize.height > 0, bounds.height > 0 else { return }
        let wasAtBottom = contentOffset.y >= maxOffsetY(for: old) - 1
        if isTracking || isDecelerating || isGridZooming() {
            if wasAtBottom { pendingBottomFix = abs(insets.bottom - old.bottom) + 1 }
            return
        }
        let maxY = maxOffsetY(for: insets)
        if wasAtBottom || contentOffset.y > maxY { contentOffset.y = maxY }
    }

    /// After a drag or fling ends: applies an inset change that happened during it.
    func scrollCameToRest() {
        defer { pendingBottomFix = nil }
        guard !isGridZooming(), contentSize.height > 0 else { return }
        let maxY = maxOffsetY(for: adjustedContentInset)
        let tolerance = pendingBottomFix ?? 0.5
        if contentOffset.y > maxY || (pendingBottomFix != nil && abs(contentOffset.y - maxY) <= tolerance) {
            setContentOffset(CGPoint(x: contentOffset.x, y: maxY), animated: true)
        }
    }

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
