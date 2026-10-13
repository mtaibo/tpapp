import SwiftUI
import TPCore

struct BlindControlSheet: View {
    let blind: Blind
    @ObservedObject var store: HomeStore
    @Environment(\.dismiss) private var dismiss

    @State private var position: Int

    init(blind: Blind, store: HomeStore) {
        self.blind = blind
        self.store = store
        _position = State(initialValue: blind.state?.position ?? 0)
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text(blind.name)
                    .font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
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
                    Text("%")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.tint)
                }
            }

            HStack(spacing: 16) {
                Button { Task { await store.sendUp(blind.id) } } label: {
                    Image(systemName: "chevron.up").frame(width: 32, height: 32)
                }
                Button { Task { await store.sendStop(blind.id) } } label: {
                    Image(systemName: "pause.fill").frame(width: 32, height: 32)
                }
                Button { Task { await store.sendDown(blind.id) } } label: {
                    Image(systemName: "chevron.down").frame(width: 32, height: 32)
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(width: 320)
    }
}
