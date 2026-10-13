import SwiftUI
import TPCore

/// Lights are read-only this phase: the backend has no working toggle route (see `HomeClient`).
struct LightsLayer: View {
    let lights: [Light]

    var body: some View {
        ForEach(lights) { light in
            ZStack {
                Circle()
                    .fill(fillColor(light))
                    .overlay(Circle().strokeBorder(strokeColor(light), lineWidth: 2))
                    .frame(width: 20, height: 20)
                Circle()
                    .fill(dotColor(light))
                    .frame(width: 6, height: 6)
            }
            .position(x: light.map.x, y: light.map.y)
        }
    }

    private func isOn(_ light: Light) -> Bool { light.state?.on ?? false }

    private static let onColor = Color(red: 1, green: 0.878, blue: 0.541)

    private func strokeColor(_ light: Light) -> Color {
        isOn(light) ? Self.onColor : .white.opacity(0.2)
    }

    private func fillColor(_ light: Light) -> Color {
        isOn(light) ? Self.onColor.opacity(0.07) : .white.opacity(0.05)
    }

    private func dotColor(_ light: Light) -> Color {
        isOn(light) ? Self.onColor : .gray
    }
}
