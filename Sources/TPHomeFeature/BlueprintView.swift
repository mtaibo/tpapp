import SwiftUI
import TPCore

struct BlueprintView: View {
    @ObservedObject var store: HomeStore
    @State private var selectedBlindID: String?

    // The animated "hero" rect: starts matching the tapped icon's screen frame, grows to
    // `cardSize` centered on open, and shrinks back on close. Driven by hand (not
    // matchedGeometryEffect) because the map sits behind a `.scaleEffect(scale)` below, which
    // only transforms rendering -- it never updates the layout geometry matchedGeometryEffect
    // reads, so the icon's reported frame wouldn't match where it actually appears on screen
    // (the same pitfall `hitTargets` below already avoids by computing screen position by hand).
    @State private var cardX: CGFloat = 0
    @State private var cardY: CGFloat = 0
    @State private var cardWidth: CGFloat = 0
    @State private var cardHeight: CGFloat = 0

    /// Mirrors `Blueprint.vue`'s `svg.w-full.h-auto.max-w-3xl` inside a `flex items-center justify-center p-5/10`:
    /// the plan scales to fill the available width (capped, then centered), height following the aspect ratio.
    private static let maxWidth: Double = 768
    private static let padding: Double = 24
    private static let cardSize = CGSize(width: 280, height: 440)
    private static let minHitTargetSize: Double = 44
    private static let openAnimation = Animation.bouncy(duration: 0.35, extraBounce: 0.1)
    // No overshoot on close: a bouncy spring overshoots past its target before settling, which
    // reads fine growing into the big card but, shrinking down to the tiny icon's size, that same
    // overshoot is a much bigger fraction of the target -- it looked like a glitchy little bounce.
    private static let closeAnimation = Animation.smooth(duration: 0.25)

    var body: some View {
        GeometryReader { geometry in
            let canvasSize = Self.parseViewBox(store.mapConfig?.viewBox)
            let availableWidth = max(geometry.size.width - Self.padding * 2, 0)
            let width = min(availableWidth, Self.maxWidth)
            let scale = canvasSize.width > 0 ? width / canvasSize.width : 1
            let onlineBlinds = Array(store.blinds.values).filter { $0.connection?.online == true }
            let originX = (geometry.size.width - canvasSize.width * scale) / 2
            let originY = (geometry.size.height - canvasSize.height * scale) / 2
            let finalFrame = CGRect(
                x: (geometry.size.width - Self.cardSize.width) / 2,
                y: (geometry.size.height - Self.cardSize.height) / 2,
                width: Self.cardSize.width,
                height: Self.cardSize.height
            )

            ZStack {
                ZStack {
                    if let mapConfig = store.mapConfig {
                        WallsLayer(rooms: mapConfig.rooms, labels: mapConfig.labels, doors: mapConfig.doors)
                        LightsLayer(lights: Array(store.lights.values).filter { $0.connection?.online == true })
                        BlindsLayer(blinds: onlineBlinds, selectedBlindID: selectedBlindID)
                    }
                }
                .frame(width: canvasSize.width, height: canvasSize.height)
                .scaleEffect(scale)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .overlay {
                    hitTargets(blinds: onlineBlinds, scale: scale, originX: originX, originY: originY) { blind in
                        open(blind, scale: scale, originX: originX, originY: originY, finalFrame: finalFrame)
                    }
                }
                .allowsHitTesting(selectedBlindID == nil)

                if let blind = selectedBlindID.flatMap({ store.blinds[$0] }) {
                    // Invisible tap catcher so tapping outside the card still dismisses it,
                    // without drawing anything on top of the map.
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture { close(blind, scale: scale, originX: originX, originY: originY) }

                    // Always laid out at its natural full size; only scale + position are
                    // animated, so the content itself never reflows mid-transition (a plain
                    // `.frame` resize would instead clip/squash the slider and buttons).
                    BlindControlSheet(blind: blind, store: store, onDismiss: {
                        close(blind, scale: scale, originX: originX, originY: originY)
                    })
                    .frame(width: Self.cardSize.width, height: Self.cardSize.height)
                    .scaleEffect(x: cardWidth / Self.cardSize.width, y: cardHeight / Self.cardSize.height, anchor: .center)
                    .position(x: cardX + cardWidth / 2, y: cardY + cardHeight / 2)
                }
            }
        }
    }

    private func open(_ blind: Blind, scale: Double, originX: Double, originY: Double, finalFrame: CGRect) {
        let icon = iconFrame(for: blind, scale: scale, originX: originX, originY: originY)
        cardX = icon.minX
        cardY = icon.minY
        cardWidth = icon.width
        cardHeight = icon.height
        selectedBlindID = blind.id
        withAnimation(Self.openAnimation) {
            cardX = finalFrame.minX
            cardY = finalFrame.minY
            cardWidth = finalFrame.width
            cardHeight = finalFrame.height
        }
    }

    private func close(_ blind: Blind, scale: Double, originX: Double, originY: Double) {
        let icon = iconFrame(for: blind, scale: scale, originX: originX, originY: originY)
        withAnimation(Self.closeAnimation) {
            cardX = icon.minX
            cardY = icon.minY
            cardWidth = icon.width
            cardHeight = icon.height
        } completion: {
            selectedBlindID = nil
        }
    }

    private func iconFrame(for blind: Blind, scale: Double, originX: Double, originY: Double) -> CGRect {
        CGRect(
            x: originX + blind.map.x * scale,
            y: originY + blind.map.y * scale,
            width: blind.map.width * scale,
            height: blind.map.height * scale
        )
    }

    private static func parseViewBox(_ viewBox: String?) -> CGSize {
        let parts = (viewBox ?? "0 0 100 100").split(separator: " ").compactMap { Double($0) }
        guard parts.count == 4, parts[2] > 0, parts[3] > 0 else { return CGSize(width: 100, height: 100) }
        return CGSize(width: parts[2], height: parts[3])
    }

    /// Invisible tap targets placed directly in screen space (canvas origin + `scale` applied by hand),
    /// matching `Blinds.vue`'s SVG hit `<rect>`s: one coordinate system shared by rendering and hit-testing,
    /// rather than relying on `.scaleEffect`'s hit-testing to stay in sync with its own rendered output.
    @ViewBuilder
    private func hitTargets(
        blinds: [Blind],
        scale: Double,
        originX: Double,
        originY: Double,
        onTap: @escaping (Blind) -> Void
    ) -> some View {
        ForEach(blinds) { blind in
            // Padded out to at least Apple's 44pt minimum touch target, centered on the icon's
            // actual (often much thinner) drawn rect -- the icon itself stays its true size.
            Color.clear
                .contentShape(Rectangle())
                .frame(
                    width: max(blind.map.width * scale, Self.minHitTargetSize),
                    height: max(blind.map.height * scale, Self.minHitTargetSize)
                )
                .position(
                    x: originX + (blind.map.x + blind.map.width / 2) * scale,
                    y: originY + (blind.map.y + blind.map.height / 2) * scale
                )
                .onTapGesture { onTap(blind) }
                // The map itself (BlindsLayer/LightsLayer/WallsLayer) is drawn with Shapes and
                // Canvas, none of it accessible on its own — without this, VoiceOver has no way
                // to even discover a blind exists here, let alone open its controls.
                .accessibilityElement()
                .accessibilityLabel(blind.name)
                .accessibilityValue("\(blind.state?.position ?? 0) percent open")
                .accessibilityAddTraits(.isButton)
        }
    }
}
