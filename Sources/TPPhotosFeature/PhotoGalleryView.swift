import SwiftUI
import TPCore

public struct PhotoGalleryView: View {
    @ObservedObject var store: PhotoGalleryStore
    @ObservedObject var syncStore: PhotoSyncStore
    let client: PhotosClient
    let ownerEmail: String

    @State private var selectedPhoto: Photo?
    @State private var topBarHeight: CGFloat = 120

    public init(store: PhotoGalleryStore, syncStore: PhotoSyncStore, client: PhotosClient, ownerEmail: String) {
        self.store = store
        self.syncStore = syncStore
        self.client = client
        self.ownerEmail = ownerEmail
    }

    public var body: some View {
        ZStack(alignment: .top) {
            TPPhotosTheme.background.ignoresSafeArea()
            content
            toolbar
        }
        .task {
            if store.photos.isEmpty { await store.reload() }
        }
        .sheet(item: $selectedPhoto) { photo in
            PhotoDetailView(photo: photo, client: client) {
                Task { await store.delete(photo) }
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 10) {
                HStack {
                    Text("Photos")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                    Spacer()
                    backupButton
                }
                filterChips
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { topBarHeight = $0 }
    }

    private var backupButton: some View {
        Button {
            Task {
                await syncStore.backupNow(ownerEmail: ownerEmail)
                await store.reload()
            }
        } label: {
            Group {
                if syncStore.isRunning {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "icloud.and.arrow.up")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 30, height: 30)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .disabled(syncStore.isRunning)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PhotosClient.Filter.allCases, id: \.self) { filter in
                    chip(for: filter)
                }
            }
        }
    }

    private func chip(for filter: PhotosClient.Filter) -> some View {
        Button {
            store.filter = filter
        } label: {
            Text(label(for: filter))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(store.filter == filter ? .black : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .background(store.filter == filter ? Color.white : Color.white.opacity(0.1))
        .clipShape(Capsule())
    }

    private func label(for filter: PhotosClient.Filter) -> String {
        switch filter {
        case .all: return "All"
        case .screenshots: return "Screenshots"
        case .camera: return "Camera"
        case .shared: return "Shared"
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if store.isLoading && store.photos.isEmpty {
            VStack {
                Spacer()
                ProgressView().tint(.white)
                Spacer()
            }
        } else if let error = store.errorMessage, store.photos.isEmpty {
            VStack {
                Spacer()
                Text(error).foregroundStyle(TPPhotosTheme.danger)
                Spacer()
            }
        } else if store.photos.isEmpty {
            VStack {
                Spacer()
                Text("No photos yet")
                    .font(.system(size: 14))
                    .foregroundStyle(TPPhotosTheme.textMuted)
                Spacer()
            }
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: topBarHeight)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                        ForEach(store.photos) { photo in
                            tile(for: photo)
                                .onAppear { Task { await store.loadMoreIfNeeded(currentItem: photo) } }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 24)

                    if store.isLoadingMore {
                        ProgressView().tint(.white).padding(.bottom, 16)
                    }
                }
            }
        }
    }

    private func tile(for photo: Photo) -> some View {
        Button {
            selectedPhoto = photo
        } label: {
            AsyncImage(url: client.thumbnailURL(for: photo)) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(Color.white.opacity(0.05))
                }
            }
            .frame(width: 110, height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

enum TPPhotosTheme {
    static let background = Color.black
    static let textPrimary = Color(white: 1.0)
    static let textMuted = Color(red: 0.322, green: 0.322, blue: 0.322)
    static let danger = Color(red: 1.0, green: 0.271, blue: 0.227)
}
