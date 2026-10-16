import SwiftUI
import TPCore

public struct PhotoGalleryView: View {
    @ObservedObject var store: PhotoGalleryStore
    @ObservedObject var syncStore: PhotoSyncStore
    @ObservedObject var tabBarState: PhotosTabBarState
    let client: PhotosClient
    let ownerEmail: String
    let isAdmin: Bool

    @State private var selectedPhoto: Photo?
    @State private var topBarHeight: CGFloat = 120
    @State private var isStatusPresented = false
    /// The success message whose ✓ has already been shown for a few seconds and hidden.
    @State private var dismissedMessage: String?
    /// The Albums tile last tapped — independent of `tabBarState.section` so switching to
    /// Shared and back to Gallery never loses it.
    @State private var galleryFilter: PhotosClient.Filter = .all

    public init(store: PhotoGalleryStore, syncStore: PhotoSyncStore, tabBarState: PhotosTabBarState, client: PhotosClient, ownerEmail: String, isAdmin: Bool = false) {
        self.store = store
        self.syncStore = syncStore
        self.tabBarState = tabBarState
        self.client = client
        self.ownerEmail = ownerEmail
        self.isAdmin = isAdmin
    }

    private var effectiveFilter: PhotosClient.Filter {
        tabBarState.section == .shared ? .shared : galleryFilter
    }

    public var body: some View {
        ZStack(alignment: .top) {
            TPPhotosTheme.background.ignoresSafeArea()
            content
            toolbar
        }
        .task {
            store.filter = effectiveFilter
            if store.photos.isEmpty { await store.reload() }
        }
        .onChange(of: effectiveFilter) { _, newValue in
            store.filter = newValue
        }
        .sheet(item: $selectedPhoto) { photo in
            PhotoDetailView(photo: photo, client: client) {
                Task { await store.delete(photo) }
            }
        }
    }

    // MARK: - Toolbar

    private var toolbarTitle: String {
        switch tabBarState.section {
        case .albums: return "Albums"
        case .gallery: return "Photos"
        case .shared: return "Shared"
        }
    }

    private var toolbar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack {
                Text(toolbarTitle)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                Spacer()
                if hasStatus {
                    statusButton
                }
                menuButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { topBarHeight = $0 }
    }

    private var hasStatus: Bool {
        syncStore.isRunning || syncStore.isSanitizing || syncStore.isChecking
            || syncStore.lastError != nil
            || (successMessage != nil && successMessage != dismissedMessage)
    }

    private var successMessage: String? {
        syncStore.lastSanitizeMessage ?? syncStore.lastCheckMessage
    }

    /// Sits next to the ellipsis menu: a ring that fills up while a backup uploads, a spinner for
    /// Check/Sanitize, or the last run's outcome. Tapping it explains the status in full.
    private var isBusy: Bool {
        syncStore.isRunning || syncStore.isSanitizing || syncStore.isChecking
    }

    private struct StatusDismissKey: Equatable {
        let message: String?
        let isPresented: Bool
        let isBusy: Bool
    }

    private var statusButton: some View {
        Button {
            isStatusPresented.toggle()
        } label: {
            Group {
                if syncStore.isRunning {
                    progressRing
                } else if syncStore.isSanitizing || syncStore.isChecking {
                    ProgressView().tint(.white)
                } else if syncStore.lastError != nil {
                    Image(systemName: "exclamationmark")
                        .font(.system(size: ellipsisIconFontSize, weight: .semibold))
                        .foregroundStyle(TPPhotosTheme.danger)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: ellipsisIconFontSize, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: ellipsisIconDimension, height: ellipsisIconDimension)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .task(id: StatusDismissKey(message: successMessage, isPresented: isStatusPresented, isBusy: isBusy)) {
            // Errors stay until acted on; a plain success ✓ only lingers briefly — and never
            // vanishes while its popover is open or another run is underway.
            if isBusy { dismissedMessage = nil } // a new run's result may repeat the old text
            guard let message = successMessage, syncStore.lastError == nil,
                  !isStatusPresented, !isBusy else { return }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation { dismissedMessage = message }
        }
        .popover(isPresented: $isStatusPresented, arrowEdge: .top) {
            statusDetail
                .padding(16)
                .frame(width: 280, alignment: .leading)
                .presentationCompactAdaptation(.popover)
        }
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 2.5)
            if syncStore.progressTotal == 0 {
                // Still scanning/checking which photos are new: no fraction to show yet.
                ProgressView().tint(.white).controlSize(.small)
            } else {
                Circle()
                    .trim(from: 0, to: syncStore.progressFraction)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut, value: syncStore.progressFraction)
            }
        }
        .padding(4)
    }

    @ViewBuilder
    private var statusDetail: some View {
        if syncStore.isRunning {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Subiendo fotos")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    if syncStore.progressTotal > 0 {
                        Text("\(Int(syncStore.progressFraction * 100))%")
                            .font(.system(size: 14, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                if syncStore.progressTotal == 0 {
                    ProgressView().progressViewStyle(.linear)
                } else {
                    ProgressView(value: syncStore.progressFraction)
                }
                Text(syncStore.progressTotal == 0 ? "Comprobando fotos existentes…" : syncStore.progressLabel)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                failureList
            }
        } else if syncStore.isSanitizing {
            statusLine("Reorganizando fotos…", showsSpinner: true)
        } else if syncStore.isChecking {
            statusLine("Comprobando fotos…", showsSpinner: true)
        } else if let error = syncStore.lastError {
            VStack(alignment: .leading, spacing: 10) {
                statusLine(error).foregroundStyle(TPPhotosTheme.danger)
                failureList
            }
        } else if let message = syncStore.lastSanitizeMessage ?? syncStore.lastCheckMessage {
            statusLine(message)
        }
    }

    /// The backup's failures grouped by reason, most frequent first.
    @ViewBuilder
    private var failureList: some View {
        if !syncStore.failureReasons.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(syncStore.failureReasons.sorted { $0.value > $1.value }, id: \.key) { reason, count in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(count)")
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(TPPhotosTheme.danger)
                        Text(reason)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func statusLine(_ text: String, showsSpinner: Bool = false) -> some View {
        HStack(spacing: 8) {
            if showsSpinner { ProgressView().controlSize(.small) }
            Text(text)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.secondary)
    }

    private var menuButton: some View {
        Menu {
            Button {
                Task {
                    await syncStore.backupNow(ownerEmail: ownerEmail)
                    await store.reload()
                }
            } label: {
                Label("Backup now", systemImage: "icloud.and.arrow.up")
            }
            Button {
                Task {
                    await syncStore.checkNow(ownerEmail: ownerEmail)
                    await store.reload()
                }
            } label: {
                Label("Check", systemImage: "checkmark.icloud")
            }
            if isAdmin {
                Button {
                    Task { await syncStore.sanitizeNow() }
                } label: {
                    Label("Sanitize", systemImage: "wand.and.stars")
                }
            }
        } label: {
            Group {
                if syncStore.isRunning || syncStore.isSanitizing || syncStore.isChecking {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "ellipsis")
                        .font(.system(size: ellipsisIconFontSize, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: ellipsisIconDimension, height: ellipsisIconDimension)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .disabled(syncStore.isRunning || syncStore.isSanitizing || syncStore.isChecking)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch tabBarState.section {
        case .albums:
            albumsContent
        case .gallery, .shared:
            galleryContent
        }
    }

    /// Drives `tabBarState.isCollapsed` from scroll direction, not absolute position: scrolling
    /// further into the grid collapses the real tab bar into `PhotosCollapsedBar`, scrolling
    /// back toward the top (or reaching it) restores it — same as Apple's own Photos app.
    private func trackingTabBarCollapse<Content: View>(_ view: Content) -> some View {
        view.onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { oldValue, newValue in
            let delta = newValue - oldValue
            if newValue <= 24 {
                if tabBarState.isCollapsed { withAnimation(.snappy) { tabBarState.isCollapsed = false } }
            } else if delta > 6 {
                if !tabBarState.isCollapsed { withAnimation(.snappy) { tabBarState.isCollapsed = true } }
            } else if delta < -6 {
                if tabBarState.isCollapsed { withAnimation(.snappy) { tabBarState.isCollapsed = false } }
            }
        }
    }

    private var albumsContent: some View {
        trackingTabBarCollapse(
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: topBarHeight)
                    AlbumsGridView { filter in
                        galleryFilter = filter
                        withAnimation(.snappy(duration: 0.25)) { tabBarState.section = .gallery }
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
        )
    }

    @ViewBuilder
    private var galleryContent: some View {
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
            // Inverted-list trick: the API already returns newest-first with pagination toward
            // older items, so flipping the whole scroll view 180° (and counter-flipping each
            // tile's content) makes the newest photo land at the visual bottom — where the
            // ScrollView naturally rests on first appearance — and "load more" naturally extends
            // upward off-screen with no jump, all without touching PhotoGalleryStore's ordering.
            // Note: because the whole stack below is y-flipped, its *local* top-to-bottom order
            // renders as the *visual* bottom-to-top order — so the grid is listed first (it ends
            // up visually at the bottom/newest end) and the top-bar clearance spacer last (it
            // ends up visually at the very top, under the floating toolbar).
            trackingTabBarCollapse(
                ScrollView {
                    VStack(spacing: 0) {
                        LazyVGrid(columns: gridColumns, spacing: Self.tileSpacing) {
                            ForEach(Array(store.photos.enumerated()), id: \.element.id) { index, photo in
                                tile(for: photo)
                                    .onAppear { Task { await store.loadMoreIfNeeded(currentIndex: index) } }
                            }
                        }
                        .padding(.bottom, 24)

                        if store.isLoadingMore {
                            ProgressView().tint(.white).padding(.vertical, 16)
                        }

                        Color.clear.frame(height: topBarHeight)
                    }
                }
                .scaleEffect(x: 1, y: -1)
                .gesture(pinchZoomGesture)
            )
        }
    }

    // MARK: - Pinch-to-zoom grid density

    /// The column counts the pinch gesture snaps between — 1 means "one photo at a time,
    /// stacked for a vertical scroll" (fully zoomed in), 30 is the densest zoomed-out grid.
    private static let columnLevels = [1, 3, 5, 15, 30]
    private static let tileSpacing: CGFloat = 1

    @State private var columnLevelIndex = 1 // columnLevels[1] == 3, the grid's starting density

    private var columnCount: Int { Self.columnLevels[columnLevelIndex] }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Self.tileSpacing), count: columnCount)
    }

    /// Finer-grained thumbnails as tiles grow from a 30-across grid up to a single full-width
    /// photo, so zooming in doesn't just blow up a blurry 160px thumbnail.
    private var thumbnailSize: Int {
        switch columnCount {
        case 1: return 800
        case 3: return 300
        case 5: return 200
        case 15: return 120
        default: return 80
        }
    }

    /// Only the gesture's *direction* past a deadzone matters — one pinch steps the grid one
    /// level denser or sparser, same as the native Photos app's own zoom levels.
    private var pinchZoomGesture: some Gesture {
        MagnificationGesture()
            .onEnded { value in
                withAnimation(.snappy) {
                    if value > 1.15 {
                        columnLevelIndex = max(0, columnLevelIndex - 1)
                    } else if value < 0.85 {
                        columnLevelIndex = min(Self.columnLevels.count - 1, columnLevelIndex + 1)
                    }
                }
            }
    }

    private func tile(for photo: Photo) -> some View {
        Button {
            selectedPhoto = photo
        } label: {
            GeometryReader { proxy in
                Group {
                    if let cached = PhotoThumbnailCache.image(forChecksum: photo.checksum) {
                        cached
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        AsyncImage(url: client.thumbnailURL(for: photo, size: thumbnailSize)) { phase in
                            if let image = phase.image {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                Rectangle().fill(Color.white.opacity(0.05))
                            }
                        }
                    }
                }
                .id(photo.id)
                .frame(width: proxy.size.width, height: proxy.size.width)
                .clipped()
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .scaleEffect(x: 1, y: -1)
    }
}

// Mirrors TPStoreFeature's ellipsis Menu sizing: .buttonStyle(.glass) only adds chrome around
// the label's own size rather than shrinking it, so the label itself must be sized small.
private var ellipsisIconDimension: CGFloat {
    #if os(macOS)
    23
    #else
    30
    #endif
}

private var ellipsisIconFontSize: CGFloat {
    #if os(macOS)
    12
    #else
    16
    #endif
}

enum TPPhotosTheme {
    static let background = Color.black
    static let textPrimary = Color(white: 1.0)
    static let textMuted = Color(red: 0.322, green: 0.322, blue: 0.322)
    static let danger = Color(red: 1.0, green: 0.271, blue: 0.227)
}
