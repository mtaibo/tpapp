import SwiftUI
import TPCore

/// Purely visual: the invisible tap targets live in `BlueprintView`'s hit-test overlay instead,
/// computed directly in screen space so they can't drift out of sync with `.scaleEffect`'s
/// rendering (see `BlueprintView.hitTargets`).
struct BlindsLayer: View {
    let blinds: [Blind]
    let selectedBlindID: String?

    var body: some View {
        ForEach(blinds) { blind in
            blindView(blind)
                // Hidden (not animated) the instant it's selected: `BlueprintView`'s hero card
                // appears already matching this icon's exact screen rect, so the swap is seamless.
                .opacity(blind.id == selectedBlindID ? 0 : (blind.connection?.online == true ? 1 : 0.3))
                .position(x: blind.map.x + blind.map.width / 2, y: blind.map.y + blind.map.height / 2)
        }
    }

    private func isHorizontal(_ blind: Blind) -> Bool { blind.map.width > blind.map.height }

    private func coverSize(_ blind: Blind) -> CGSize {
        guard let position = blind.state?.position else {
            return CGSize(width: blind.map.width, height: blind.map.height)
        }
        let uncovered = Double(100 - position) / 100
        return isHorizontal(blind)
            ? CGSize(width: blind.map.width * uncovered, height: blind.map.height)
            : CGSize(width: blind.map.width, height: blind.map.height * uncovered)
    }

    @ViewBuilder
    private func blindView(_ blind: Blind) -> some View {
        let cover = coverSize(blind)
        ZStack(alignment: isHorizontal(blind) ? .leading : .top) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(.black)
                .overlay(RoundedRectangle(cornerRadius: 1.5).strokeBorder(.white.opacity(0.55), lineWidth: 0.5))

            slatFill(isHorizontal: isHorizontal(blind))
                .frame(width: cover.width, height: cover.height)
                .animation(.easeInOut(duration: 0.4), value: blind.state?.position)
        }
        .frame(width: blind.map.width, height: blind.map.height)
        .clipShape(RoundedRectangle(cornerRadius: 1.5))
    }

    /// Repeating-stripe stand-in for the web's SVG slat pattern — not pixel-identical, just close enough.
    private func slatFill(isHorizontal: Bool) -> some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(0.84)))
            let stripe = 6.0
            if isHorizontal {
                var x = 0.0
                while x < size.width {
                    context.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(.black.opacity(0.14)))
                    x += stripe
                }
            } else {
                var y = 0.0
                while y < size.height {
                    context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.14)))
                    y += stripe
                }
            }
        }
    }
}
