#if os(iOS)
import UIKit

/// Drives the grid's zoom the way the Photos app does. The grid never loses its shape: the grid
/// being left is frozen into a snapshot that scales with the fingers about the middle of the grid
/// (tiles slide off both sides evenly when zooming in), the new grid scales underneath it at exactly the same tile size and lattice,
/// and the two cross-fade, so each photo fades into its new cell instead of travelling there.
/// One pinch can sweep through several column counts; letting go settles on whichever the pinch
/// was heading for; past the densest and the largest levels the grid stretches and springs back.
@MainActor
final class PhotoGridZoomController: NSObject {
    weak var collectionView: PhotoGridCollectionView?
    private(set) var level: Int
    /// After the grid settles on a new level: refresh cells and remember the level.
    var onLevelCommitted: (Int) -> Void = { _ in }
    /// After a zoom ends, either way: apply anything held back while it ran.
    var onZoomEnded: () -> Void = {}

    var isZooming: Bool {
        session != nil || isPinching
    }

    private struct Session {
        let layout: PhotoGridZoomLayout
        let targetLevel: Int
        /// New tile size ÷ old tile size: above 1 zooming in.
        let ratio: CGFloat
        /// The on-screen point both grids scale about.
        let pivot: CGPoint
        /// The frozen grid being left.
        let snapshot: UIView
        /// Fades the snapshot only over the new grid's footprint (see `startSession`).
        let fadeMask: CAGradientLayer
        let offsetFrom: CGPoint
        let offsetTo: CGPoint
        var progress: CGFloat = 0
    }

    private struct Settle {
        let start: CFTimeInterval
        let duration: CFTimeInterval
        let fromProgress: CGFloat
        let toProgress: CGFloat
    }

    private var session: Session?
    private var isPinching = false
    private var baselineScale: CGFloat = 1
    private var focalItem = 0
    /// Where in the focal tile the fingers are, 0...1 from its top.
    private var focalUnitY: CGFloat = 0.5
    /// The fingers' position on screen.
    private var finger: CGPoint = .zero
    /// The screen hasn't drawn the latest layout swap yet, so a snapshot must wait for it.
    private var needsFreshSnapshot = false
    private var settle: Settle?
    private var displayLink: CADisplayLink?
    private var isStretched = false
    private let haptics = UIImpactFeedbackGenerator(style: .light)

    init(level: Int) {
        self.level = level
    }

    private static var levels: [Int] { PhotoGridDensity.columnLevels }

    private func geometry(level: Int) -> PhotoGridGeometry? {
        guard let collectionView else { return nil }
        return PhotoGridLayout.geometry(columns: Self.levels[level], in: collectionView)
    }

    // MARK: Pinch

    @objc func handlePinch(_ pinch: UIPinchGestureRecognizer) {
        guard let collectionView else { return }
        switch pinch.state {
        case .began:
            completeSettleNow()
            isPinching = true
            collectionView.isPinnedToBottom = false
            // Taking over from the scroll view's own pan for the length of the pinch; disabling
            // the recognizer also cancels a drag already underway.
            collectionView.panGestureRecognizer.isEnabled = false
            baselineScale = pinch.scale
            let location = pinch.location(in: collectionView)
            finger = CGPoint(x: location.x - collectionView.contentOffset.x, y: location.y - collectionView.contentOffset.y)
            setFocus(at: location)
            haptics.prepare()
        case .changed:
            pinchChanged(scale: pinch.scale / baselineScale, rawScale: pinch.scale)
        case .ended, .cancelled, .failed:
            isPinching = false
            collectionView.panGestureRecognizer.isEnabled = true
            pinchEnded(velocity: pinch.velocity, cancelled: pinch.state != .ended)
        default:
            break
        }
    }

    private func setFocus(at location: CGPoint) {
        guard let collectionView, let geometry = geometry(level: level), geometry.itemCount > 0 else { return }
        let item = collectionView.indexPathForItem(at: location)?.item ?? nearestItem(to: location, in: geometry)
        focalItem = item
        let frame = geometry.frame(forItem: item)
        focalUnitY = frame.height > 0 ? min(max((location.y - frame.minY) / frame.height, 0), 1) : 0.5
    }

    /// The tile closest to a point that fell in a gap (or beyond the content).
    private func nearestItem(to point: CGPoint, in geometry: PhotoGridGeometry) -> Int {
        let y = min(max(point.y, 0), max(geometry.contentHeight - 1, 0))
        let row = geometry.items(fromY: y, toY: y)
        guard !row.isEmpty else { return geometry.itemCount - 1 }
        return row.min { abs(geometry.frame(forItem: $0).midX - point.x) < abs(geometry.frame(forItem: $1).midX - point.x) } ?? row.lowerBound
    }

    private func pinchChanged(scale: CGFloat, rawScale: CGFloat) {
        // Spreading the fingers zooms in: fewer, bigger columns.
        let target = level + (scale >= 1 ? -1 : 1)
        guard Self.levels.indices.contains(target) else {
            revertSession()
            stretch(scale)
            return
        }
        if isStretched { stretch(1) }
        if session?.targetLevel != target {
            revertSession()
            startSession(to: target)
        }
        guard let session else { return }
        let progress = log(scale) / log(session.ratio)
        if progress >= 1 {
            // Reached the next level with the fingers still going: land on it and carry on from
            // there in the same pinch.
            setProgress(1)
            commit()
            baselineScale = rawScale
        } else {
            setProgress(max(progress, 0))
        }
    }

    private func pinchEnded(velocity: CGFloat, cancelled: Bool) {
        if isStretched { springBackStretch() }
        guard let session else {
            onZoomEnded()
            return
        }
        let zoomingIn = session.ratio > 1
        let flicked = abs(velocity) > 0.6
        let towardTarget = zoomingIn ? velocity > 0 : velocity < 0
        let finish: Bool
        if cancelled {
            finish = false
        } else if flicked {
            finish = towardTarget ? session.progress > 0.05 : session.progress > 0.9
        } else {
            finish = session.progress > 0.5
        }
        settle(to: finish ? 1 : 0)
    }

    // MARK: Zoom In / Zoom Out (menu)

    /// Animates to `newLevel` around the middle of the screen, as if pinched there.
    func zoom(toLevel newLevel: Int) {
        guard let collectionView, newLevel != level, Self.levels.indices.contains(newLevel), !isPinching else { return }
        completeSettleNow()
        collectionView.isPinnedToBottom = false
        let insets = collectionView.adjustedContentInset
        finger = CGPoint(x: collectionView.bounds.width / 2, y: insets.top + (collectionView.bounds.height - insets.top - insets.bottom) / 2)
        setFocus(at: CGPoint(x: collectionView.contentOffset.x + finger.x, y: collectionView.contentOffset.y + finger.y))
        guard abs(newLevel - level) == 1, !UIAccessibility.isReduceMotionEnabled else {
            jump(to: newLevel)
            return
        }
        startSession(to: newLevel)
        settle(to: 1)
    }

    // MARK: Sessions

    /// Freezes the current grid and lays the `target` grid out underneath it, scaled so its tiles
    /// match the current ones in size and sit on the same lattice, with the focal photo's row
    /// in the same place in both.
    private func startSession(to target: Int) {
        guard let collectionView, let from = geometry(level: level), let to = geometry(level: target),
              from.itemCount > 0, from.pitch > 0, to.pitch != from.pitch else { return }
        let offsetFrom = collectionView.contentOffset
        // Where the new grid comes to rest: the focal photo as close under the fingers as the
        // scrollable range allows, so the zoom ends without any correcting jump.
        let focalTo = to.frame(forItem: focalItem)
        let restingY = focalTo.minY + focalTo.height * focalUnitY - finger.y
        let offsetTo = CGPoint(x: offsetFrom.x, y: clampedOffset(restingY, contentHeight: to.contentHeight))

        // The point both grids scale about. Across: the middle of the grid, so columns leave and
        // arrive evenly on both sides — and since every level has an odd column count, the middle
        // column and with it every column of the two grids line up. Down: the height that maps
        // the focal photo's row in the old grid onto its row in the new one, so rows line up too.
        let ratio = to.pitch / from.pitch
        let a = from.frame(forItem: focalItem).offsetBy(dx: -offsetFrom.x, dy: -offsetFrom.y)
        let b = focalTo.offsetBy(dx: -offsetTo.x, dy: -offsetTo.y)
        let pivot = CGPoint(x: to.width / 2 - offsetTo.x, y: (ratio * a.minY - b.minY) / (ratio - 1))

        let snapshot = collectionView.snapshotView(afterScreenUpdates: needsFreshSnapshot) ?? UIView()
        needsFreshSnapshot = false
        snapshot.isUserInteractionEnabled = false
        snapshot.layer.zPosition = 1000

        let layout = PhotoGridZoomLayout(geometry: to, pivot: CGPoint(x: pivot.x + offsetTo.x, y: pivot.y + offsetTo.y))
        layout.scale = 1 / ratio
        install(layout, offset: offsetTo)
        snapshot.frame = CGRect(origin: offsetTo, size: collectionView.bounds.size)
        collectionView.addSubview(snapshot)

        // Zooming in, the new grid starts out narrower than the screen (its tiles are shrunk to
        // the old size), so there's nothing under the snapshot's outer columns: fading those too
        // just showed the background, darkening the sides. Only the part over the new grid fades;
        // the rest stays solid and slides off the edges as it grows. In the snapshot's own
        // (untransformed) coordinates that part is a fixed band: the new grid's width ÷ ratio,
        // centred on the pivot. Zooming out the band is wider than the screen, so all of it fades.
        let width = collectionView.bounds.width
        let halfBand = to.width / (2 * ratio)
        let left = width > 0 ? min(max((pivot.x - halfBand) / width, 0), 1) : 0
        let right = width > 0 ? min(max((pivot.x + halfBand) / width, 0), 1) : 1
        let fadeMask = CAGradientLayer()
        fadeMask.startPoint = CGPoint(x: 0, y: 0.5)
        fadeMask.endPoint = CGPoint(x: 1, y: 0.5)
        // Repeated stops make hard steps rather than gradients.
        fadeMask.locations = [0, left, left, right, right, 1].map { NSNumber(value: Double($0)) }
        fadeMask.frame = snapshot.bounds
        snapshot.layer.mask = fadeMask

        session = Session(
            layout: layout,
            targetLevel: target,
            ratio: ratio,
            pivot: pivot,
            snapshot: snapshot,
            fadeMask: fadeMask,
            offsetFrom: offsetFrom,
            offsetTo: offsetTo
        )
    }

    private func setProgress(_ progress: CGFloat) {
        guard let collectionView, var session else { return }
        session.progress = progress
        self.session = session
        let scale = pow(session.ratio, progress)
        session.layout.scale = scale / session.ratio
        session.layout.invalidateLayout()

        // The old grid grows (or shrinks) by `scale` about the pivot; a view transforms about its
        // own centre, so shift by however far the pivot is from it.
        let center = CGPoint(x: collectionView.bounds.width / 2, y: collectionView.bounds.height / 2)
        session.snapshot.transform = CGAffineTransform(
            a: scale, b: 0, c: 0, d: scale,
            tx: (session.pivot.x - center.x) * (1 - scale),
            ty: (session.pivot.y - center.y) * (1 - scale)
        )
        let solid = UIColor.black.cgColor
        let faded = UIColor(white: 0, alpha: 1 - progress).cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        session.fadeMask.colors = [solid, solid, faded, faded, solid, solid]
        CATransaction.commit()
    }

    /// Lands on the session's target: the new grid is already at rest underneath.
    private func commit() {
        guard let session else { return }
        session.snapshot.removeFromSuperview()
        self.session = nil
        level = session.targetLevel
        install(PhotoGridLayout(columns: Self.levels[level]), offset: session.offsetTo)
        finishLevelChange()
    }

    /// Back to the grid the session started from, exactly as it was.
    private func revertSession() {
        guard let session else { return }
        session.snapshot.removeFromSuperview()
        self.session = nil
        install(PhotoGridLayout(columns: Self.levels[level]), offset: session.offsetFrom)
        collectionView?.layoutIfNeeded()
        needsFreshSnapshot = true
    }

    /// Straight to a level with no animation (Reduce Motion, or a jump of several levels).
    private func jump(to newLevel: Int) {
        guard let collectionView, let to = geometry(level: newLevel), to.itemCount > 0 else { return }
        let frame = to.frame(forItem: min(focalItem, to.itemCount - 1))
        let y = clampedOffset(frame.minY + frame.height * focalUnitY - finger.y, contentHeight: to.contentHeight)
        level = newLevel
        install(PhotoGridLayout(columns: Self.levels[newLevel]), offset: CGPoint(x: collectionView.contentOffset.x, y: y))
        finishLevelChange()
        onZoomEnded()
    }

    private func finishLevelChange() {
        needsFreshSnapshot = true
        onLevelCommitted(level)
        haptics.impactOccurred()
        haptics.prepare()
    }

    private func install(_ layout: UICollectionViewLayout, offset: CGPoint) {
        guard let collectionView else { return }
        collectionView.setCollectionViewLayout(layout, animated: false)
        collectionView.contentOffset = offset
    }

    private func clampedOffset(_ y: CGFloat, contentHeight: CGFloat) -> CGFloat {
        guard let collectionView else { return y }
        let insets = collectionView.adjustedContentInset
        let minY = -insets.top
        let maxY = max(contentHeight + insets.bottom - collectionView.bounds.height, minY)
        return min(max(y, minY), maxY)
    }

    // MARK: Settling after the fingers lift

    private func settle(to toProgress: CGFloat) {
        guard let session else { return }
        settle = Settle(
            start: CACurrentMediaTime(),
            duration: 0.2 + 0.15 * Double(abs(toProgress - session.progress)),
            fromProgress: session.progress,
            toProgress: toProgress
        )
        if displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(step(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    @objc private func step(_ link: CADisplayLink) {
        advanceSettle(to: CACurrentMediaTime())
    }

    private func advanceSettle(to time: CFTimeInterval) {
        guard let settle, session != nil else {
            stopDisplayLink()
            return
        }
        let t = min(max((time - settle.start) / settle.duration, 0), 1)
        // Ease out: quick to respond, soft to land.
        let eased = CGFloat(1 - pow(1 - t, 3))
        setProgress(settle.fromProgress + (settle.toProgress - settle.fromProgress) * eased)
        guard t >= 1 else { return }
        self.settle = nil
        stopDisplayLink()
        if settle.toProgress == 1 {
            commit()
        } else {
            revertSession()
        }
        onZoomEnded()
    }

    private func completeSettleNow() {
        guard let settle else { return }
        advanceSettle(to: settle.start + settle.duration)
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    // MARK: Stretch past the ends

    /// Scales the grid slightly around the fingers, resisting more the further the pinch goes.
    private func stretch(_ scale: CGFloat) {
        guard let collectionView else { return }
        let amount = pow(scale, 0.2)
        isStretched = amount != 1
        let dx = finger.x - collectionView.bounds.width / 2
        let dy = finger.y - collectionView.bounds.height / 2
        var transform = CATransform3DMakeTranslation(dx, dy, 0)
        transform = CATransform3DScale(transform, amount, amount, 1)
        transform = CATransform3DTranslate(transform, -dx, -dy, 0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        collectionView.layer.sublayerTransform = transform
        CATransaction.commit()
    }

    private func springBackStretch() {
        guard let layer = collectionView?.layer else { return }
        isStretched = false
        let animation = CASpringAnimation(keyPath: "sublayerTransform")
        animation.fromValue = layer.presentation()?.sublayerTransform ?? layer.sublayerTransform
        animation.toValue = CATransform3DIdentity
        animation.damping = 26
        animation.stiffness = 300
        animation.duration = animation.settlingDuration
        layer.sublayerTransform = CATransform3DIdentity
        layer.add(animation, forKey: "stretch")
    }
}
#endif
