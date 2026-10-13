import SwiftUI
import TPCore

struct BlueprintView: View {
    @ObservedObject var store: HomeStore
    @State private var selectedBlindID: String?

    /// Mirrors `Blueprint.vue`'s `svg.w-full.h-auto.max-w-3xl` inside a `flex items-center justify-center p-5/10`:
    /// the plan scales to fill the available width (capped, then centered), height following the aspect ratio.
    private static let maxWidth: Double = 768
    private static let padding: Double = 24

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                let canvasSize = Self.parseViewBox(store.mapConfig?.viewBox)
                let availableWidth = max(geometry.size.width - Self.padding * 2, 0)
                let width = min(availableWidth, Self.maxWidth)
                let scale = canvasSize.width > 0 ? width / canvasSize.width : 1
                let onlineBlinds = Array(store.blinds.values).filter { $0.connection?.online == true }

                ZStack {
                    if let mapConfig = store.mapConfig {
                        WallsLayer(rooms: mapConfig.rooms, labels: mapConfig.labels, doors: mapConfig.doors)
                        LightsLayer(lights: Array(store.lights.values).filter { $0.connection?.online == true })
                        BlindsLayer(blinds: onlineBlinds)
                    }
                }
                .frame(width: canvasSize.width, height: canvasSize.height)
                .scaleEffect(scale)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .overlay {
                    hitTargets(blinds: onlineBlinds, canvasSize: canvasSize, scale: scale, containerSize: geometry.size)
                }
            }

            if let blind = selectedBlindID.flatMap({ store.blinds[$0] }) {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { selectedBlindID = nil }
                    .transition(.opacity)

                BlindControlSheet(blind: blind, store: store, onDismiss: { selectedBlindID = nil })
                    .id(blind.id)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: selectedBlindID)
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
    private func hitTargets(blinds: [Blind], canvasSize: CGSize, scale: Double, containerSize: CGSize) -> some View {
        let originX = (containerSize.width - canvasSize.width * scale) / 2
        let originY = (containerSize.height - canvasSize.height * scale) / 2

        ForEach(blinds) { blind in
            Color.clear
                .contentShape(Rectangle())
                .frame(width: blind.map.width * scale, height: blind.map.height * scale)
                .position(
                    x: originX + (blind.map.x + blind.map.width / 2) * scale,
                    y: originY + (blind.map.y + blind.map.height / 2) * scale
                )
                .onTapGesture { selectedBlindID = blind.id }
        }
    }
}
