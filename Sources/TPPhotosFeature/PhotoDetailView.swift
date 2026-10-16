import SwiftUI
import TPCore

public struct PhotoDetailView: View {
    let photo: Photo
    let client: PhotosClient
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false

    public init(photo: Photo, client: PhotosClient, onDelete: @escaping () -> Void) {
        self.photo = photo
        self.client = client
        self.onDelete = onDelete
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            AsyncImage(url: client.originalURL(for: photo)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                case .failure:
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                default:
                    ProgressView().tint(.white)
                }
            }

            VStack {
                HStack {
                    closeButton
                    Spacer()
                    deleteButton
                }
                .padding()
                Spacer()
            }
        }
        .confirmationDialog(
            "Delete this photo?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel("Close")
    }

    private var deleteButton: some View {
        Button {
            showDeleteConfirm = true
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel("Delete")
    }
}
