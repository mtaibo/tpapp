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
        GeometryReader { geometry in
            let canvasSize = Self.parseViewBox(store.mapConfig?.viewBox)
            let availableWidth = max(geometry.size.width - Self.padding * 2, 0)
            let width = min(availableWidth, Self.maxWidth)
            let scale = canvasSize.width > 0 ? width / canvasSize.width : 1

            ZStack {
                if let mapConfig = store.mapConfig {
                    WallsLayer(rooms: mapConfig.rooms, labels: mapConfig.labels, doors: mapConfig.doors)
                    LightsLayer(lights: Array(store.lights.values).filter { $0.connection?.online == true })
                    BlindsLayer(blinds: Array(store.blinds.values).filter { $0.connection?.online == true }) { selectedBlindID = $0 }
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .scaleEffect(scale)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .sheet(item: Binding(
            get: { selectedBlindID.flatMap { store.blinds[$0] } },
            set: { selectedBlindID = $0?.id }
        )) { blind in
            BlindControlSheet(blind: blind, store: store)
        }
    }

    private static func parseViewBox(_ viewBox: String?) -> CGSize {
        let parts = (viewBox ?? "0 0 100 100").split(separator: " ").compactMap { Double($0) }
        guard parts.count == 4, parts[2] > 0, parts[3] > 0 else { return CGSize(width: 100, height: 100) }
        return CGSize(width: parts[2], height: parts[3])
    }
}
