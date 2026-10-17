import SwiftUI
import TPCore

/// The Albums section: the server's filters as a "Media Types" list, like the Photos app's own.
/// Picking one jumps back to Library, filtered to it.
struct AlbumsListView: View {
    private struct Album: Identifiable {
        let title: String
        let systemImage: String
        let filter: PhotosClient.Filter

        var id: PhotosClient.Filter { filter }
    }

    let selected: PhotosClient.Filter
    let onSelect: (PhotosClient.Filter) -> Void

    private let albums: [Album] = [
        Album(title: "All Photos", systemImage: "photo.on.rectangle", filter: .all),
        Album(title: "Camera", systemImage: "camera", filter: .camera),
        Album(title: "Screenshots", systemImage: "camera.viewfinder", filter: .screenshots),
    ]

    var body: some View {
        List {
            Section("Media Types") {
                ForEach(albums) { album in
                    Button {
                        onSelect(album.filter)
                    } label: {
                        HStack {
                            Label(album.title, systemImage: album.systemImage)
                                .foregroundStyle(.primary)
                            Spacer()
                            if album.filter == selected {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .accessibilityAddTraits(album.filter == selected ? .isSelected : [])
                }
            }
        }
    }
}
