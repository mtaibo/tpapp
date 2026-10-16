import SwiftUI
import TPCore

struct BlindsSectionView: View {
    @ObservedObject var store: HomeStore
    @State private var inputText: [String: String] = [:]

    private let columns = [GridItem(.adaptive(minimum: 180), spacing: 16)]

    var body: some View {
        ScrollView {
            if store.blinds.isEmpty {
                ContentUnavailableView("No blinds available", systemImage: "blinds.horizontal.closed")
                    .padding(.top, 60)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Array(store.blinds.values).sorted(by: { $0.name < $1.name })) { blind in
                        BlindCardView(
                            blind: blind,
                            inputText: Binding(
                                get: { inputText[blind.id] ?? "" },
                                set: { inputText[blind.id] = $0 }
                            ),
                            onUp: { Task { await store.sendUp(blind.id) } },
                            onStop: { Task { await store.sendStop(blind.id) } },
                            onDown: { Task { await store.sendDown(blind.id) } },
                            onSet: { position in Task { await store.sendSet(blind.id, position: position) } }
                        )
                    }
                }
                .padding()
            }
        }
    }
}

private struct BlindCardView: View {
    let blind: Blind
    @Binding var inputText: String
    let onUp: () -> Void
    let onStop: () -> Void
    let onDown: () -> Void
    let onSet: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill((blind.connection?.online ?? false) ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel((blind.connection?.online ?? false) ? "Online" : "Offline")
                Text(blind.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text("\(blind.state?.position ?? 0)%")
                    .font(.system(.footnote, design: .monospaced).weight(.bold))
            }

            HStack(spacing: 8) {
                BlindSlider(
                    position: blind.state?.position ?? 0,
                    onDrag: { _ in },
                    onDragEnd: { onSet($0) }
                )
                .frame(height: 180)

                VStack(spacing: 8) {
                    Button(action: onUp) { Image(systemName: "chevron.up").frame(width: 36, height: 36) }
                        .accessibilityLabel("Raise")
                    Button(action: onStop) { Image(systemName: "pause.fill").frame(width: 36, height: 36) }
                        .accessibilityLabel("Stop")
                    Button(action: onDown) { Image(systemName: "chevron.down").frame(width: 36, height: 36) }
                        .accessibilityLabel("Lower")
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                TextField("0 – 100", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commit() }
                    .accessibilityLabel("Blind position")
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                Button(action: commit) {
                    Image(systemName: "chevron.right")
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Set position")
            }
        }
        .padding(16)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22))
    }

    private func commit() {
        guard let value = Int(inputText) else { return }
        onSet(min(100, max(0, value)))
        inputText = ""
    }
}
