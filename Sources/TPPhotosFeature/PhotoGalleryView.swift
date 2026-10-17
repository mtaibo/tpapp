import SwiftUI
import TPCore
import TPUI
#if os(iOS)
import UIKit
#endif

/// Which part of the Photos tab is showing, picked from the segmented control in the nav bar.
enum PhotosSection: String, CaseIterable {
    case library, albums, shared

    var title: String {
        switch self {
        case .library: return "Library"
        case .albums: return "Albums"
        case .shared: return "Shared"
        }
    }
}

public struct PhotoGalleryView: View {
    @ObservedObject var store: PhotoGalleryStore
    @ObservedObject var syncStore: PhotoSyncStore
    let client: PhotosClient
    let ownerEmail: String
    let isAdmin: Bool

    @Environment(\.openURL) private var openURL
    @State private var section: PhotosSection = .library
    /// The album last picked under Albums; independent of `section` so a trip to Shared and back
    /// to Library keeps it.
    @State private var albumFilter: PhotosClient.Filter = .all
    @State private var detailPhotoID: Int?
    @State private var isStatusPresented = false
    /// The success message whose ✓ has already been shown for a few seconds and hidden.
    @State private var dismissedMessage: String?

    // Grid density. One pinch steps one level, like the native Photos app.
    private static let columnLevels = [1, 3, 5, 9, 15]
    @AppStorage("photos.columnLevel") private var columnLevelIndex = 1
    @State private var scrollPosition = ScrollPosition(idType: Int.self)
    @State private var visiblePhotoIDs: [Int] = []
    /// Set once the current pinch has stepped the grid, so one continuous pinch never skips
    /// several levels at once.
    @State private var pinchConsumed = false

    public init(store: PhotoGalleryStore, syncStore: PhotoSyncStore, client: PhotosClient, ownerEmail: String, isAdmin: Bool = false) {
        self.store = store
        self.syncStore = syncStore
        self.client = client
        self.ownerEmail = ownerEmail
        self.isAdmin = isAdmin
    }

    private var effectiveFilter: PhotosClient.Filter {
        section == .shared ? .shared : albumFilter
    }

    public var body: some View {
        NavigationStack {
            Group {
                switch section {
                case .albums:
                    AlbumsListView(selected: albumFilter) { filter in
                        albumFilter = filter
                        withAnimation(.snappy) { section = .library }
                    }
                case .library, .shared:
                    galleryContent
                }
            }
            .navigationTitle(section.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
        }
        .task {
            store.filter = effectiveFilter
            if store.photos.isEmpty { await store.reload() }
        }
        .onChange(of: effectiveFilter) { _, newValue in
            store.filter = newValue
        }
        #if os(iOS)
        .fullScreenCover(item: detailBinding) { selection in
            detail(startingAt: selection.id)
        }
        #else
        .sheet(item: detailBinding) { selection in
            detail(startingAt: selection.id)
                .frame(minWidth: 720, minHeight: 540)
        }
        #endif
    }

    private struct DetailSelection: Identifiable {
        let id: Int
    }

    private var detailBinding: Binding<DetailSelection?> {
        Binding(
            get: { detailPhotoID.map(DetailSelection.init) },
            set: { detailPhotoID = $0?.id }
        )
    }

    private func detail(startingAt id: Int) -> some View {
        PhotoDetailView(photos: displayedPhotos, initialPhotoID: id, client: client) { photo in
            Task { await store.delete(photo) }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Section", selection: $section.animation(.snappy)) {
                ForEach(PhotosSection.allCases, id: \.self) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if hasStatus {
                statusButton
            }
            menuButton
        }
    }

    private var isBusy: Bool {
        syncStore.isRunning || syncStore.isSanitizing || syncStore.isChecking
    }

    private var successMessage: String? {
        syncStore.lastSanitizeMessage ?? syncStore.lastCheckMessage
    }

    private var hasStatus: Bool {
        isBusy || syncStore.lastError != nil || (successMessage != nil && successMessage != dismissedMessage)
    }

    private struct StatusDismissKey: Equatable {
        let message: String?
        let isPresented: Bool
        let isBusy: Bool
    }

    /// Sits next to the ••• menu: a ring that fills up while a backup uploads, a spinner for
    /// Check/Sanitize, or the last run's outcome. Tapping it explains the status in full.
    private var statusButton: some View {
        Button {
            isStatusPresented.toggle()
        } label: {
            Group {
                if syncStore.isRunning {
                    BackupProgressRing(fraction: syncStore.progressTotal == 0 ? nil : syncStore.progressFraction)
                } else if isBusy {
                    ProgressView()
                } else if syncStore.lastError != nil {
                    Image(systemName: "exclamationmark.icloud")
                        .foregroundStyle(.red)
                } else {
                    Image(systemName: "checkmark.icloud")
                }
            }
            .frame(width: 24, height: 24)
        }
        .accessibilityLabel("Backup Status")
        .task(id: StatusDismissKey(message: successMessage, isPresented: isStatusPresented, isBusy: isBusy)) {
            // Errors stay until acted on; a plain success ✓ only lingers briefly — and never
            // vanishes while its popover is open or another run is underway.
            if isBusy { dismissedMessage = nil } // a new run's result may repeat the old text
            guard let message = successMessage, syncStore.lastError == nil, !isStatusPresented, !isBusy else { return }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation { dismissedMessage = message }
        }
        .popover(isPresented: $isStatusPresented) {
            BackupStatusDetail(syncStore: syncStore) { url in openURL(url) }
                .padding()
                .frame(width: 300, alignment: .leading)
                .presentationCompactAdaptation(.popover)
        }
    }

    private var menuButton: some View {
        Menu {
            Section {
                Button("Back Up Now", systemImage: "icloud.and.arrow.up") {
                    Task {
                        await syncStore.backupNow(ownerEmail: ownerEmail)
                        await store.reload()
                    }
                }
                Button("Check Library", systemImage: "checkmark.icloud") {
                    Task {
                        await syncStore.checkNow(ownerEmail: ownerEmail)
                        await store.reload()
                    }
                }
                if isAdmin {
                    Button("Sanitize Server", systemImage: "wand.and.stars") {
                        Task { await syncStore.sanitizeNow() }
                    }
                }
            }
            .disabled(isBusy)

            if section != .albums {
                // The pinch gesture's equivalent for VoiceOver, keyboards and Macs without a trackpad.
                Section {
                    Button("Zoom In", systemImage: "plus.magnifyingglass") { stepColumns(by: -1) }
                        .disabled(columnLevelIndex == 0)
                    Button("Zoom Out", systemImage: "minus.magnifyingglass") { stepColumns(by: 1) }
                        .disabled(columnLevelIndex == Self.columnLevels.count - 1)
                }
            }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
        .menuIndicator(.hidden)
    }

    // MARK: - Grid

    /// Oldest first, so the newest photo sits at the bottom of the grid like the Photos app.
    /// (The API pages newest-first; this used to be done by flipping the whole scroll view
    /// upside down, which also reversed VoiceOver order and broke the pinch gesture.)
    private var displayedPhotos: [Photo] {
        store.photos.reversed()
    }

    private var columnCount: Int {
        Self.columnLevels[min(max(columnLevelIndex, 0), Self.columnLevels.count - 1)]
    }

    private var spacing: CGFloat { columnCount >= 9 ? 1 : 2 }

    /// Bigger thumbnails as tiles grow, so zooming in doesn't just blow up a blurry one.
    private var thumbnailSize: Int {
        switch columnCount {
        case 1: return 800
        case 3: return 400
        case 5: return 240
        default: return 120
        }
    }

    @ViewBuilder
    private var galleryContent: some View {
        if store.isLoading && store.photos.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = store.errorMessage, store.photos.isEmpty {
            ContentUnavailableView {
                Label("Couldn't Load Photos", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") { Task { await store.reload() } }
            }
        } else if store.photos.isEmpty {
            ContentUnavailableView {
                Label(section == .shared ? "No Shared Photos" : "No Photos Yet", systemImage: "photo.on.rectangle")
            } description: {
                if section == .library {
                    Text("Back up this device's library from the ••• menu.")
                }
            }
        } else {
            grid
        }
    }

    private var grid: some View {
        let photos = displayedPhotos
        let count = photos.count
        return ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnCount),
                spacing: spacing
            ) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { offset, photo in
                    tile(for: photo)
                        .onAppear {
                            // `store` indexes newest-first; the grid shows oldest-first.
                            Task { await store.loadMoreIfNeeded(currentIndex: count - 1 - offset) }
                        }
                }
            }
            .scrollTargetLayout()

            if store.isLoadingMore {
                ProgressView().padding()
            }
        }
        .scrollPosition($scrollPosition)
        // Open on the newest photos, and keep the view still while older pages are added above.
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.5) { ids in
            visiblePhotoIDs = ids
        }
        // Simultaneous, not `.gesture`: a plain gesture on a ScrollView loses every two-finger
        // touch to the scroll view's own pan, which is why pinching never changed the columns.
        .simultaneousGesture(pinchGesture)
        .refreshable { await store.reload() }
    }

    private func tile(for photo: Photo) -> some View {
        Button {
            detailPhotoID = photo.id
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
                .clipShape(.rect(cornerRadius: columnCount >= 9 ? 0 : 4))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .id(photo.id)
        .accessibilityLabel(accessibilityLabel(for: photo))
    }

    private func accessibilityLabel(for photo: Photo) -> String {
        var parts = [photo.isScreenshot ? "Screenshot" : "Photo"]
        if let takenAt = photo.takenAt.flatMap(PhotoDates.parse) {
            parts.append(takenAt.formatted(date: .long, time: .shortened))
        }
        return parts.joined(separator: ", ")
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.05)
            .onChanged { value in
                guard !pinchConsumed else { return }
                if value.magnification > 1.25 {
                    pinchConsumed = true
                    stepColumns(by: -1)
                } else if value.magnification < 0.8 {
                    pinchConsumed = true
                    stepColumns(by: 1)
                }
            }
            .onEnded { _ in
                pinchConsumed = false
            }
    }

    /// Negative zooms in (fewer, bigger columns). Keeps the photo that was in the middle of the
    /// screen in the middle afterwards, instead of jumping to wherever the new layout puts the
    /// same scroll offset.
    private func stepColumns(by delta: Int) {
        let newIndex = min(max(columnLevelIndex + delta, 0), Self.columnLevels.count - 1)
        guard newIndex != columnLevelIndex else { return }
        let anchorID = visiblePhotoIDs.isEmpty ? nil : visiblePhotoIDs[visiblePhotoIDs.count / 2]
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        withAnimation(.snappy(duration: 0.3)) {
            columnLevelIndex = newIndex
            if let anchorID {
                scrollPosition.scrollTo(id: anchorID, anchor: .center)
            }
        }
    }
}

/// The ring in the status button: fills with the backup's progress, or spins while the library is
/// still being scanned and there's no fraction to show yet.
private struct BackupProgressRing: View {
    let fraction: Double?

    var body: some View {
        ZStack {
            Circle().stroke(.secondary.opacity(0.35), lineWidth: 2.5)
            if let fraction {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut, value: fraction)
            } else {
                ProgressView().controlSize(.mini)
            }
        }
        .padding(2)
    }
}

/// The status popover's contents: what's running, how far along, and what went wrong.
private struct BackupStatusDetail: View {
    @ObservedObject var syncStore: PhotoSyncStore
    let openURL: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if syncStore.isRunning {
                HStack {
                    Text("Backing Up Photos").font(.headline)
                    Spacer()
                    if syncStore.progressTotal > 0 {
                        Text(syncStore.progressFraction, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                if syncStore.progressTotal == 0 {
                    ProgressView()
                        .progressViewStyle(.linear)
                    Text("Checking which photos are already backed up…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView(value: syncStore.progressFraction)
                    Text(syncStore.progressLabel)
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                failureList
            } else if syncStore.isSanitizing {
                Label("Reorganizing photos on the server…", systemImage: "wand.and.stars")
            } else if syncStore.isChecking {
                Label("Checking the library…", systemImage: "checkmark.icloud")
            } else if let error = syncStore.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                #if os(iOS)
                if syncStore.permissionDenied, let url = URL(string: UIApplication.openSettingsURLString) {
                    Button("Open Settings") { openURL(url) }
                }
                #endif
                failureList
            } else if let message = syncStore.lastSanitizeMessage ?? syncStore.lastCheckMessage {
                Label(message, systemImage: "checkmark.circle.fill")
            }
        }
        .font(.subheadline)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The backup's failures grouped by reason, most frequent first.
    @ViewBuilder
    private var failureList: some View {
        if !syncStore.failureReasons.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(syncStore.failureReasons.sorted { $0.value > $1.value }, id: \.key) { reason, count in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(count)")
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .foregroundStyle(.red)
                        Text(reason)
                            .foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                }
            }
        }
    }
}

/// The server sends ISO-8601, sometimes with fractional seconds.
enum PhotoDates {
    static func parse(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}
