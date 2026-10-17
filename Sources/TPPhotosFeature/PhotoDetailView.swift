import SwiftUI
import TPCore
import TPUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Full-screen viewer: swipe between photos, pinch or double-tap to zoom, and an info sheet with
/// the photo's metadata. Shows the grid's thumbnail instantly and swaps in the original when it
/// arrives.
public struct PhotoDetailView: View {
    let photos: [Photo]
    let client: PhotosClient
    let onDelete: (Photo) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var currentID: Int?
    @State private var isZoomed = false
    @State private var showsChrome = true
    @State private var showsInfo = false
    @State private var photoPendingDelete: Photo?
    /// Photos deleted while the viewer is open; hidden locally so paging stays consistent while
    /// the gallery store catches up.
    @State private var deletedIDs: Set<Int> = []

    public init(photos: [Photo], initialPhotoID: Int, client: PhotosClient, onDelete: @escaping (Photo) -> Void) {
        self.photos = photos
        self.client = client
        self.onDelete = onDelete
        _currentID = State(initialValue: initialPhotoID)
    }

    private var visiblePhotos: [Photo] {
        photos.filter { !deletedIDs.contains($0.id) }
    }

    private var currentPhoto: Photo? {
        visiblePhotos.first { $0.id == currentID }
    }

    public var body: some View {
        NavigationStack {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(visiblePhotos) { photo in
                        ZoomablePhoto(photo: photo, client: client, isZoomed: $isZoomed) {
                            withAnimation(.easeInOut(duration: 0.2)) { showsChrome.toggle() }
                        }
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(photo.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentID)
            .scrollDisabled(isZoomed)
            .scrollIndicators(.hidden)
            .ignoresSafeArea()
            .background(.black)
            .navigationTitle(currentPhoto.flatMap(Self.title) ?? "")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(showsChrome ? .visible : .hidden, for: .navigationBar, .bottomBar)
            .statusBarHidden(!showsChrome)
            #endif
            .toolbar { toolbarContent }
            .sheet(isPresented: $showsInfo) {
                if let currentPhoto {
                    PhotoInfoView(photo: currentPhoto)
                }
            }
            .confirmationDialog(
                "Delete this photo?",
                isPresented: Binding(get: { photoPendingDelete != nil }, set: { if !$0 { photoPendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: photoPendingDelete
            ) { photo in
                Button("Delete Photo", role: .destructive) { delete(photo) }
            } message: { _ in
                Text("It will be removed from your server. The copy on this device isn't affected.")
            }
        }
        .preferredColorScheme(.dark)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close", systemImage: "xmark") { dismiss() }
        }
        #if os(iOS)
        ToolbarItemGroup(placement: .bottomBar) {
            bottomButtons
        }
        #else
        ToolbarItemGroup(placement: .primaryAction) {
            bottomButtons
        }
        #endif
    }

    @ViewBuilder
    private var bottomButtons: some View {
        if let currentPhoto {
            Button("Info", systemImage: "info.circle") { showsInfo = true }
            Spacer()
            Button("Delete", systemImage: "trash") { photoPendingDelete = currentPhoto }
        }
    }

    private func delete(_ photo: Photo) {
        let remaining = visiblePhotos
        guard let index = remaining.firstIndex(of: photo) else { return }
        onDelete(photo)
        if remaining.count == 1 {
            dismiss()
            return
        }
        // Land on the neighbor (the next one, or the previous one at the end), like Photos.
        let next = index + 1 < remaining.count ? remaining[index + 1] : remaining[index - 1]
        withAnimation {
            deletedIDs.insert(photo.id)
            currentID = next.id
        }
    }

    private static func title(for photo: Photo) -> String? {
        photo.takenAt.flatMap(PhotoDates.parse)?.formatted(date: .abbreviated, time: .shortened)
    }
}

/// One page of the viewer. Zoom is handled here; while zoomed the pager's scrolling is turned off
/// (through `isZoomed`) so a drag pans the photo instead of flipping to the next one.
private struct ZoomablePhoto: View {
    let photo: Photo
    let client: PhotosClient
    @Binding var isZoomed: Bool
    let onSingleTap: () -> Void

    @State private var original: Image?
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var drag: CGSize = .zero

    private static let maxScale: CGFloat = 5

    var body: some View {
        ZStack {
            if let original {
                original
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .scaleEffect(scale * pinch)
        .offset(x: offset.width + drag.width, y: offset.height + drag.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
        .gesture(magnify)
        .gesture(pan, including: scale > 1 ? .all : .subviews)
        .onTapGesture(count: 2) {
            withAnimation(.snappy) {
                if scale > 1 {
                    scale = 1
                    offset = .zero
                } else {
                    scale = 2.5
                }
            }
            isZoomed = scale > 1
        }
        .onTapGesture(perform: onSingleTap)
        .onDisappear {
            // Paging away resets zoom, so coming back shows the whole photo again.
            scale = 1
            offset = .zero
        }
        .task(id: photo.id) {
            // From this device's library when the photo is on it (instant, and no multi-megabyte
            // download); from the server otherwise.
            if let local = await PhotoThumbnailLoader.shared.localFullImage(for: photo, pixels: 3000) {
                original = local
            } else {
                original = await Self.loadOriginal(client.originalURL(for: photo))
            }
        }
        .accessibilityElement()
        .accessibilityLabel(photo.isScreenshot ? "Screenshot" : "Photo")
        .accessibilityAddTraits(.isImage)
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                withAnimation(.snappy) {
                    scale = min(max(scale * value.magnification, 1), Self.maxScale)
                    if scale == 1 { offset = .zero }
                }
                isZoomed = scale > 1
            }
    }

    private var pan: some Gesture {
        DragGesture()
            .updating($drag) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                offset.width += value.translation.width
                offset.height += value.translation.height
            }
    }

    /// Originals can be 12–48 MP; decoding them at full size for a phone screen wastes hundreds of
    /// megabytes, so they're downsampled off the main thread to roughly what can be displayed
    /// at max zoom. Not kept in `ImagePipeline`'s memory cache for the same reason.
    @concurrent
    private static func loadOriginal(_ url: URL) async -> Image? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        #if os(iOS)
        guard let image = UIImage(data: data) else { return nil }
        let maxPixels: CGFloat = 4096
        let longest = max(image.size.width, image.size.height) * image.scale
        if longest > maxPixels {
            let factor = maxPixels / longest
            let size = CGSize(width: image.size.width * image.scale * factor, height: image.size.height * image.scale * factor)
            if let thumbnail = await image.byPreparingThumbnail(ofSize: size) {
                return Image(uiImage: thumbnail)
            }
        }
        return Image(uiImage: await image.byPreparingForDisplay() ?? image)
        #else
        guard let image = NSImage(data: data) else { return nil }
        return Image(nsImage: image)
        #endif
    }
}

/// The ⓘ sheet: when, what, with which camera and where.
private struct PhotoInfoView: View {
    let photo: Photo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let takenAt = photo.takenAt.flatMap(PhotoDates.parse) {
                        LabeledContent("Taken", value: takenAt.formatted(date: .long, time: .shortened))
                    }
                    LabeledContent("File Name", value: photo.originalFilename)
                    if let width = photo.width, let height = photo.height {
                        LabeledContent("Dimensions", value: "\(width) × \(height)")
                    }
                    LabeledContent("Size", value: formatBytes(photo.fileSize))
                    if let mimeType = photo.mimeType {
                        LabeledContent("Format", value: mimeType)
                    }
                }
                if photo.cameraMake != nil || photo.cameraModel != nil {
                    Section("Camera") {
                        if let make = photo.cameraMake { LabeledContent("Make", value: make) }
                        if let model = photo.cameraModel { LabeledContent("Model", value: model) }
                    }
                }
                if let lat = photo.gpsLat, let lon = photo.gpsLon {
                    Section("Location") {
                        LabeledContent("Coordinates", value: String(format: "%.5f, %.5f", lat, lon))
                        if let url = URL(string: "https://maps.apple.com/?ll=\(lat),\(lon)") {
                            Link("Open in Maps", destination: url)
                        }
                    }
                }
                Section("Backup") {
                    LabeledContent("Status", value: statusText)
                    if let uploadedAt = PhotoDates.parse(photo.uploadedAt) {
                        LabeledContent("Uploaded", value: uploadedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Info")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var statusText: String {
        switch photo.status {
        case .verified: return "Verified"
        case .pending: return "Pending verification"
        case .checksumMismatch: return "Checksum mismatch"
        case .error: return "Error"
        }
    }
}
