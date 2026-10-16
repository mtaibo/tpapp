import SwiftUI
import TPCore

/// The "Albums" section: the same filters the old chips row offered, now presented as tappable
/// tiles — tapping one jumps into the Gallery grid pre-filtered to it.
struct AlbumsGridView: View {
    struct Album: Identifiable {
        let id: String
        let title: String
        let systemImage: String
        let filter: PhotosClient.Filter
    }

    let onSelect: (PhotosClient.Filter) -> Void

    let albums: [Album] = [
        Album(id: "all", title: "All Photos", systemImage: "photo.on.rectangle", filter: .all),
        Album(id: "camera", title: "Camera", systemImage: "camera.fill", filter: .camera),
        Album(id: "screenshots", title: "Screenshots", systemImage: "iphone", filter: .screenshots),
    ]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            ForEach(albums) { album in
                Button {
                    onSelect(album.filter)
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: album.systemImage)
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(.white)
                        Text(album.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .frame(height: 120)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 18))
            }
        }
        .padding(.horizontal, 16)
    }
}
