import SwiftUI
import TPCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A small tinted capsule for states like "Enabled", "Public" or "Running". Uses a text style
/// rather than a fixed point size so it grows with Dynamic Type like the rest of the app.
public struct StatusBadge: View {
    let text: String
    let tint: Color

    public init(_ text: String, tint: Color = .secondary) {
        self.text = text
        self.tint = tint
    }

    public var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(tint)
            .background(tint.opacity(0.15), in: .capsule)
    }
}

/// A colored dot paired with an accessibility label, so state isn't conveyed by color alone.
public struct StatusDot: View {
    let color: Color
    let label: String

    public init(_ color: Color, label: String) {
        self.color = color
        self.label = label
    }

    public var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .accessibilityLabel(label)
    }
}

public extension View {
    /// Shows a failed action's message as an alert, leaving whatever was on screen untouched —
    /// instead of replacing the whole content with the error, which used to blank a folder
    /// listing just because one rename failed.
    func errorAlert(_ message: Binding<String?>, title: String = "Something went wrong") -> some View {
        alert(
            title,
            isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } }),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(message.wrappedValue ?? "") }
        )
    }
}

public func formatBytes(_ count: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
}

public func copyToClipboard(_ string: String) {
    #if os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
    #else
    UIPasteboard.general.string = string
    #endif
}
