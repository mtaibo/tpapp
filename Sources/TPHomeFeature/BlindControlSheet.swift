import SwiftUI
import TPCore

/// A centered Liquid Glass card (not a system sheet) so it floats over the map instead of
/// sliding up from the bottom and covering the whole screen.
struct BlindControlSheet: View {
    let blind: Blind
    @ObservedObject var store: HomeStore
    let onDismiss: () -> Void

    // Only holds the finger-tracked value while actively dragging; the rest of the time the
    // slider mirrors `store.blinds[blind.id]` live, so WebSocket position updates (the motor
    // moving) are reflected here too instead of only on the next open/close of the popup.
    @State private var dragPosition: Int?

    private static let accent = Color(red: 0 / 255, green: 122 / 255, blue: 255 / 255)

    init(blind: Blind, store: HomeStore, onDismiss: @escaping () -> Void) {
        self.blind = blind
        self.store = store
        self.onDismiss = onDismiss
    }

    private var livePosition: Int { store.blinds[blind.id]?.state?.position ?? blind.state?.position ?? 0 }
    private var position: Int { dragPosition ?? livePosition }

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 20) {
                HStack {
                    Text(blind.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button(action: onDismiss) {
                        // Same sizing convention as the "..." glass button (FileBrowserView/
                        // SharedView in TPStoreFeature): a dedicated, platform-sized label --
                        // not toolbarIcon() -- since .buttonStyle(.glass) never shrinks its label.
                        Image(systemName: "xmark")
                            .font(.system(size: Self.closeIconFontSize, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: Self.closeIconDimension, height: Self.closeIconDimension)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                }

                VStack(spacing: 10) {
                    BlindSlider(
                        position: position,
                        onDrag: { dragPosition = $0 },
                        onDragEnd: { newPosition in
                            dragPosition = newPosition
                            Task {
                                await store.sendSet(blind.id, position: newPosition)
                                dragPosition = nil
                            }
                        }
                    )
                    .frame(width: 160, height: 240)
                    .animation(dragPosition == nil ? .easeInOut(duration: 0.4) : nil, value: livePosition)

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
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
        }
    }

    private func controlButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: Self.controlIconFontSize, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: Self.controlIconDimension, height: Self.controlIconDimension)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
    }

    // Mirrors TPStoreFeature's ellipsisIconDimension/ellipsisIconFontSize exactly: the close
    // button is the same kind of small corner icon action as the "..." menu button.
    private static var closeIconDimension: CGFloat {
        #if os(macOS)
        23
        #else
        30
        #endif
    }

    private static var closeIconFontSize: CGFloat {
        #if os(macOS)
        12
        #else
        16
        #endif
    }

    // Up/stop/down are primary actions, so they get a larger touch target than the close
    // button, but still scaled down for macOS pointer input like every other glass button here.
    private static var controlIconDimension: CGFloat {
        #if os(macOS)
        34
        #else
        44
        #endif
    }

    private static var controlIconFontSize: CGFloat {
        #if os(macOS)
        14
        #else
        18
        #endif
    }
}
