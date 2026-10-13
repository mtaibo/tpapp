import SwiftUI
import TPCore

/// A centered Liquid Glass card (not a system sheet) so it floats over the map instead of
/// sliding up from the bottom and covering the whole screen.
struct BlindControlSheet: View {
    let blind: Blind
    @ObservedObject var store: HomeStore
    let onDismiss: () -> Void

    @State private var position: Int

    private static let accent = Color(red: 0 / 255, green: 122 / 255, blue: 255 / 255)

    init(blind: Blind, store: HomeStore, onDismiss: @escaping () -> Void) {
        self.blind = blind
        self.store = store
        self.onDismiss = onDismiss
        _position = State(initialValue: blind.state?.position ?? 0)
    }

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 20) {
                HStack {
                    Text(blind.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                }

                VStack(spacing: 10) {
                    BlindSlider(
                        position: position,
                        onDrag: { position = $0 },
                        onDragEnd: { newPosition in
                            position = newPosition
                            Task { await store.sendSet(blind.id, position: newPosition) }
                        }
                    )
                    .frame(width: 160, height: 240)

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(position)")
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                        Text("%")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Self.accent)
                    }
                }

                HStack(spacing: 16) {
                    controlButton("chevron.up") { Task { await store.sendUp(blind.id) } }
                    controlButton("pause.fill") { Task { await store.sendStop(blind.id) } }
                    controlButton("chevron.down") { Task { await store.sendDown(blind.id) } }
                }
            }
            .padding(24)
            .frame(width: 280)
            .glassEffect(.regular.tint(.white.opacity(0.05)), in: .rect(cornerRadius: 28))
        }
    }

    private func controlButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
    }
}
