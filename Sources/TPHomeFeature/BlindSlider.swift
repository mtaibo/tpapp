import SwiftUI

/// Vertical fill-from-top slider, mirroring `BlindSlider.vue`'s `posFromY` drag math and glass styling:
/// a translucent track, a stack of "slat" bars filling down from the top, and a gradient handle pill.
struct BlindSlider: View {
    let position: Int
    let onDrag: (Int) -> Void
    let onDragEnd: (Int) -> Void

    private static let accent = Color(red: 0 / 255, green: 122 / 255, blue: 255 / 255)
    private static let slatCount = 32

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let fillHeight = height * Double(100 - position) / 100

            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 26)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.07), .white.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(0.13), lineWidth: 0.5))

                slats
                    .frame(height: max(fillHeight, 0), alignment: .top)
                    .clipped()
                    .overlay(alignment: .bottom) {
                        if position < 100 {
                            Rectangle().fill(Self.accent.opacity(0.35)).frame(height: 0.5)
                        }
                    }

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.96), .white.opacity(0.82)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 14)
                    .padding(.horizontal, 10)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    .position(x: geometry.size.width / 2, y: handleY(height: height))
            }
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in onDrag(Self.position(fromY: value.location.y, height: height)) }
                    .onEnded { value in onDragEnd(Self.position(fromY: value.location.y, height: height)) }
            )
            // The drag gesture above has no VoiceOver equivalent on its own — this exposes the
            // same control as an adjustable element, nudged 5% per swipe up/down.
            .accessibilityElement()
            .accessibilityLabel("Blind position")
            .accessibilityValue("\(position) percent")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: onDragEnd(min(100, position + 5))
                case .decrement: onDragEnd(max(0, position - 5))
                default: break
                }
            }
        }
    }

    private var slats: some View {
        VStack(spacing: 3) {
            ForEach(0..<Self.slatCount, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white.opacity(0.14))
                    .frame(height: 4)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    private func handleY(height: Double) -> Double {
        let y = height * Double(100 - position) / 100
        return min(max(y, 7), max(height - 7, 7))
    }

    private static func position(fromY y: Double, height: Double) -> Int {
        guard height > 0 else { return 0 }
        let raw = (1 - y / height) * 100
        return max(0, min(100, Int(raw.rounded())))
    }
}
