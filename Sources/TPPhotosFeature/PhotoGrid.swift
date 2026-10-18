import SwiftUI
import TPCore
import TPUI
#if os(iOS)
import UIKit
#endif

/// The photo grid's density levels. One pinch steps one level, like the native Photos app.
/// No single-column level: tiles only ever show the small on-device thumbnail, which would look
/// blurry stretched to the full width — opening a photo is how to see it large.
/// Every count is odd, so zooming about the middle column keeps the columns of any two levels
/// lined up (see `PhotoGridZoomController`).
enum PhotoGridDensity {
    static let columnLevels = [3, 5, 9, 15, 31]
    static let storageKey = "photos.columnLevel.v2"

    static func columns(forLevel level: Int) -> Int {
        columnLevels[min(max(level, 0), columnLevels.count - 1)]
    }

    /// Where tapping a photo zooms to instead of opening it: dense grids are for finding a spot,
    /// so a tap closes in on it — the densest level to 15 columns, anything denser than 5 to 5 —
    /// and photos open from 5 columns or fewer. `nil` means open the photo.
    static func tapZoomLevel(fromLevel level: Int) -> Int? {
        let columns = columns(forLevel: level)
        let target = columns > 15 ? 15 : columns > 5 ? 5 : nil
        return target.flatMap { columnLevels.firstIndex(of: $0) }
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
/// On iOS it's a `UICollectionView` (`PhotoCollectionGrid`); the SwiftUI grid below is the Mac's.
struct PhotoGrid: View {
    /// Newest first, as the server pages them.
    let photos: [Photo]
    let client: PhotosClient
    /// Bumped when the Photos tab is tapped again, to jump to the newest photos at the bottom.
    let scrollToBottomSignal: Int
    let onSelect: (Photo) -> Void

    @AppStorage(PhotoGridDensity.storageKey) private var columnLevel = 0
    @State private var scrollPosition = ScrollPosition(idType: Int.self)
    /// Written on every scroll frame, so it must not be `@State`: re-rendering the grid that
    /// often is what froze the whole app when entering Photos.
    @State private var visibleRows = VisibleRows()
    @State private var pinchConsumed = false

    private var columns: Int { PhotoGridDensity.columns(forLevel: columnLevel) }
    private var spacing: CGFloat { columns >= 9 ? 1 : 2 }

    var body: some View {
        #if os(iOS)
        PhotoCollectionGrid(
            photos: photos,
            client: client,
            columnLevel: $columnLevel,
            scrollToBottomSignal: scrollToBottomSignal,
            onSelect: onSelect
        )
        // Scrolls under the bars; the collection view insets itself by the safe area.
        .ignoresSafeArea()
        #else
        swiftUIGrid
        #endif
    }

    private var swiftUIGrid: some View {
        let rows = Self.rows(from: photos, columns: columns)
        return ScrollView {
            LazyVStack(spacing: spacing) {
                ForEach(rows) { row in
                    rowView(row)
                }
            }
            .scrollTargetLayout()
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
        .onChange(of: scrollToBottomSignal) {
            // The system's own "tap the tab again" scroll-to-top fires too; going to the bottom a
            // beat later makes sure ours is the one that wins.
            Task {
                try? await Task.sleep(for: .milliseconds(80))
                withAnimation(.snappy) { scrollPosition.scrollTo(edge: .bottom) }
            }
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
                    PhotoThumbnail(photo: photo, client: client)
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

    static func accessibilityLabel(for photo: Photo) -> String {
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
