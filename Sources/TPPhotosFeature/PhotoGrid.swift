import SwiftUI
import TPCore
import TPUI
#if os(iOS)
import UIKit
#endif

/// The photo grid's density levels. One pinch steps one level, like the native Photos app.
enum PhotoGridDensity {
    static let columnLevels = [1, 3, 5, 9, 15]
    static let storageKey = "photos.columnLevel"

    static func columns(forLevel level: Int) -> Int {
        columnLevels[min(max(level, 0), columnLevels.count - 1)]
    }
}

/// One row of the grid. Rows are cut from the *newest* end, so its id (the newest photo in it)
/// and its contents never change when older pages arrive: those only ever add rows above, or
/// fill in the partial row at the very top. The previous grid prepended older photos to a flat
/// `LazyVGrid`, which shifted every photo one or more columns over on each page — the whole grid
/// re-laid itself out (and flickered) every time a page landed.
private struct PhotoRow: Identifiable, Equatable {
    let id: Int
    /// Oldest to newest, left to right.
    let photos: [Photo]
}

/// Newest-at-the-bottom grid with pinch-to-zoom. Its own view (rather than part of
/// `PhotoGalleryView`) so status/menu state changes up there don't recompute thousands of rows.
struct PhotoGrid: View {
    /// Newest first, as the server pages them.
    let photos: [Photo]
    let client: PhotosClient
    let isLoadingMore: Bool
    let onSelect: (Photo) -> Void
    /// Called as rows near the top (the oldest loaded photos) appear, with the store index of
    /// the oldest photo in that row.
    let onReachOlder: (Int) -> Void

    @AppStorage(PhotoGridDensity.storageKey) private var columnLevel = 1
    @State private var scrollPosition = ScrollPosition(idType: Int.self)
    /// Written on every scroll frame, so it must not be `@State`: re-rendering the grid that
    /// often is what froze the whole app when entering Photos.
    @State private var visibleRows = VisibleRows()
    @State private var pinchConsumed = false

    private var columns: Int { PhotoGridDensity.columns(forLevel: columnLevel) }
    private var spacing: CGFloat { columns >= 9 ? 1 : 2 }

    /// Bigger thumbnails as tiles grow, so zooming in doesn't just blow up a blurry one.
    private var thumbnailSize: Int {
        switch columns {
        case 1: return 800
        case 3: return 400
        case 5: return 240
        default: return 120
        }
    }

    var body: some View {
        let rows = Self.rows(from: photos, columns: columns)
        ScrollView {
            LazyVStack(spacing: spacing) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { offset, row in
                    rowView(row)
                        .onAppear {
                            guard offset < 8 else { return }
                            // Store index of this row's oldest photo.
                            onReachOlder(min(photos.count - 1, (rows.count - 1 - offset) * columns + columns - 1))
                        }
                }
            }
            .scrollTargetLayout()

            if isLoadingMore {
                ProgressView().padding()
            }
        }
        .scrollPosition($scrollPosition)
        // Open on the newest photos, and keep the view still while older rows are added above.
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.5) { ids in
            visibleRows.ids = ids
        }
        // Simultaneous, not `.gesture`: a plain gesture on a ScrollView loses two-finger touches
        // to the scroll view's own pan.
        .simultaneousGesture(pinchGesture)
        .onChange(of: columnLevel) { oldLevel, _ in
            keepCenteredPhoto(previousColumns: PhotoGridDensity.columns(forLevel: oldLevel))
        }
    }

    private func rowView(_ row: PhotoRow) -> some View {
        HStack(spacing: spacing) {
            // The oldest row is the partial one; right-align it so every column lines up.
            ForEach(0..<(columns - row.photos.count), id: \.self) { _ in
                Color.clear.aspectRatio(1, contentMode: .fit)
            }
            ForEach(row.photos) { photo in
                tile(for: photo)
            }
        }
    }

    private func tile(for photo: Photo) -> some View {
        Button {
            onSelect(photo)
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    RemoteImage(
                        url: client.thumbnailURL(for: photo, size: thumbnailSize),
                        // The on-device cache holds small thumbnails only; bigger tiles fetch.
                        localFile: thumbnailSize <= 400 ? PhotoThumbnailCache.fileURL(forChecksum: photo.checksum) : nil
                    )
                }
                .clipShape(.rect(cornerRadius: columns >= 9 ? 0 : 4))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.accessibilityLabel(for: photo))
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.05)
            .onChanged { value in
                guard !pinchConsumed else { return }
                if value.magnification > 1.25 {
                    pinchConsumed = true
                    step(by: -1)
                } else if value.magnification < 0.8 {
                    pinchConsumed = true
                    step(by: 1)
                }
            }
            .onEnded { _ in
                pinchConsumed = false
            }
    }

    /// Negative zooms in (fewer, bigger columns).
    private func step(by delta: Int) {
        let newLevel = min(max(columnLevel + delta, 0), PhotoGridDensity.columnLevels.count - 1)
        guard newLevel != columnLevel else { return }
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        withAnimation(.snappy(duration: 0.3)) { columnLevel = newLevel }
    }

    /// After the column count changes, scrolls back to the row holding the photo that was in the
    /// middle of the screen, instead of wherever the old offset lands in the new layout. Row ids
    /// are photo ids (each row's newest photo), so the old middle row's id is that photo.
    private func keepCenteredPhoto(previousColumns: Int) {
        guard !visibleRows.ids.isEmpty else { return }
        let anchorPhotoID = visibleRows.ids[visibleRows.ids.count / 2]
        guard let index = photos.firstIndex(where: { $0.id == anchorPhotoID }) else { return }
        let rowID = photos[(index / columns) * columns].id
        withAnimation(.snappy(duration: 0.3)) {
            scrollPosition.scrollTo(id: rowID, anchor: .center)
        }
    }

    /// Cuts `photos` (newest first) into rows of `columns`, starting from the newest, then orders
    /// the rows oldest-on-top with each row oldest-on-the-left.
    private static func rows(from photos: [Photo], columns: Int) -> [PhotoRow] {
        var rows: [PhotoRow] = []
        rows.reserveCapacity(photos.count / columns + 1)
        var start = 0
        while start < photos.count {
            let chunk = photos[start..<min(start + columns, photos.count)]
            rows.append(PhotoRow(id: chunk[chunk.startIndex].id, photos: chunk.reversed()))
            start += columns
        }
        return rows.reversed()
    }

    private static func accessibilityLabel(for photo: Photo) -> String {
        var parts = [photo.isScreenshot ? "Screenshot" : "Photo"]
        if let takenAt = photo.takenAt.flatMap(PhotoDates.parse) {
            parts.append(takenAt.formatted(date: .long, time: .shortened))
        }
        return parts.joined(separator: ", ")
    }
}

/// A plain reference box: mutating `ids` never invalidates the view that owns it.
private final class VisibleRows {
    var ids: [Int] = []
}
