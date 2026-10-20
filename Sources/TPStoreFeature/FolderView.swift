import Foundation
import QuickLook
import SwiftUI
import TPCore
import TPUI
import UniformTypeIdentifiers

enum StoreViewMode: String {
    case list, icons
}

/// Any folder in the store — Home, Shared, a favorite or a raw disk path. Replaces the old
/// `FileBrowserView`/`SharedView` pair, which were ~70% the same code with their own hand-drawn
/// top bars and back/forward history; navigation is now the system `NavigationStack`, so the
/// back button, swipe-back and title all come for free.
struct FolderView: View {
    let folder: StoreFolder
    let storeClient: StoreClient
    let cache: StoreDirectoryCache
    @ObservedObject var favorites: StoreFavoritesStore
    /// Pushes a folder onto the stack; used when a drag spring-loads one of this folder's subfolders.
    let openFolder: (StoreFolder) -> Void

    @AppStorage("store.viewMode") private var viewMode: StoreViewMode = .list

    @State private var shares: [TPCore.ShareLink] = []
    /// Set once the first load attempt finished, for folders that weren't cached beforehand.
    @State private var didAttemptLoad = false
    @State private var loadError: String?
    @State private var actionError: String?
    /// Non-nil while a download/upload/open is in flight; shown as a spinner in the toolbar
    /// rather than a full-screen dimming overlay that blocked the whole folder.
    @State private var activity: String?

    @State private var isCreatingFolder = false
    @State private var newFolderName = ""
    @State private var renamingEntry: FileEntry?
    @State private var renameDraft = ""
    @State private var entryPendingDelete: FileEntry?
    @State private var sharePendingDelete: TPCore.ShareLink?
    @State private var sharingEntry: FileEntry?
    @State private var iconPickerEntry: FileEntry?
    @State private var isImportingFiles = false
    @State private var exportDocument: RawFileDocument?
    @State private var exportFilename = ""
    @State private var previewURL: URL?

    var body: some View {
        content
            .navigationTitle(folder.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
            .task { await load() }
            .alert("New Folder", isPresented: $isCreatingFolder) {
                TextField("Name", text: $newFolderName)
                Button("Create") {
                    let name = newFolderName
                    Task { await createFolder(named: name) }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert(
                "Rename",
                isPresented: Binding(get: { renamingEntry != nil }, set: { if !$0 { renamingEntry = nil } }),
                presenting: renamingEntry
            ) { entry in
                TextField("Name", text: $renameDraft)
                Button("Rename") {
                    let newName = renameDraft
                    Task { await rename(entry, to: newName) }
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(
                "Delete \(entryPendingDelete?.name ?? "")?",
                isPresented: Binding(get: { entryPendingDelete != nil }, set: { if !$0 { entryPendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: entryPendingDelete
            ) { entry in
                Button("Delete", role: .destructive) { Task { await delete(entry) } }
            } message: { entry in
                Text(entry.isDirectory ? "The folder and everything in it will be deleted." : "This can't be undone.")
            }
            .confirmationDialog(
                "Delete this link?",
                isPresented: Binding(get: { sharePendingDelete != nil }, set: { if !$0 { sharePendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: sharePendingDelete
            ) { share in
                Button("Delete Link", role: .destructive) { Task { await deleteShare(share) } }
            } message: { _ in
                Text("Anyone with the link will lose access.")
            }
            .fileImporter(isPresented: $isImportingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): Task { await upload(urls) }
                case .failure(let error): actionError = error.localizedDescription
                }
            }
            .fileExporter(
                isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
                document: exportDocument,
                contentType: .data,
                defaultFilename: exportFilename
            ) { result in
                if case .failure(let error) = result { actionError = error.localizedDescription }
            }
            .sheet(item: $sharingEntry) { entry in
                ShareSheetView(entry: entry, folder: folder, storeClient: storeClient) {
                    if folder.isSharedRoot { Task { await load() } }
                }
            }
            .sheet(item: $iconPickerEntry) { entry in
                FolderIconPicker(entry: entry, folder: folder, storeClient: storeClient) {
                    Task { try? await cache.load(folder) }
                }
            }
            .quickLookPreview($previewURL)
            .errorAlert($actionError)
    }

    // MARK: - Content

    /// Straight from the shared cache, so a prefetched folder has its contents on the very first
    /// frame of the push and slides in whole.
    private var entries: [FileEntry] {
        cache.entries(for: folder) ?? []
    }

    private var hasLoaded: Bool {
        cache.entries(for: folder) != nil || didAttemptLoad
    }

    @ViewBuilder
    private var content: some View {
        if !hasLoaded {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError, entries.isEmpty, shares.isEmpty {
            ContentUnavailableView {
                Label("Couldn't Load Folder", systemImage: "exclamationmark.triangle")
            } description: {
                Text(loadError)
            } actions: {
                Button("Try Again") { Task { await load() } }
            }
        } else if entries.isEmpty, shares.isEmpty {
            ContentUnavailableView {
                Label(
                    folder.isSharedRoot ? "Nothing Shared Yet" : "Empty Folder",
                    systemImage: folder.isSharedRoot ? "person.2" : "folder"
                )
            } description: {
                Text(folder.isSharedRoot ? "Share links and shared folders will appear here." : "Upload files or create a folder from the ••• menu.")
            }
        } else if viewMode == .list {
            listContent
        } else {
            iconContent
        }
    }

    /// A lazy stack, not a `List`: on iOS a `List` swallows every drop, so its folder rows could
    /// never take a dragged item. `swipeActionsContainer()` keeps the rows' swipe actions working.
    private var listContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !shares.isEmpty {
                    sectionHeader("Links")
                    ForEach(shares) { share in
                        ShareLinkRow(share: share, title: share.path.split(separator: "/").last.map(String.init) ?? share.path) {
                            sharePendingDelete = share
                        }
                        .padding(.horizontal, Self.rowInset)
                        .padding(.vertical, 10)
                        .background(.background)
                        rowSeparator
                    }
                    if !entries.isEmpty { sectionHeader("Folders") }
                }
                // No line above the first row, like the Files app: the list starts straight
                // under the toolbar, with a line under every row.
                ForEach(entries) { entry in
                    row(for: entry)
                    rowSeparator
                }
            }
        }
        .swipeActionsContainer()
        // Dropping on empty space (or on a file) moves the item into this folder.
        .folderDropTarget(folder, cache: cache, springLoad: nil) { actionError = $0 }
        .refreshable { await load() }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .padding(.horizontal, Self.rowInset)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    /// The side margin a plain `List` row had, kept so rows look the same size as before.
    private static let rowInset: CGFloat = 20

    /// Inset to start under the name, past the icon, like the Files app.
    private var rowSeparator: some View {
        Divider()
            .padding(.leading, Self.rowInset + 48 + 14)
    }

    private var iconContent: some View {
        ScrollView {
            if !shares.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Links")
                        .font(.headline)
                        .padding(.bottom, 4)
                    ForEach(shares) { share in
                        ShareLinkRow(share: share, title: share.path.split(separator: "/").last.map(String.init) ?? share.path) {
                            sharePendingDelete = share
                        }
                        .padding(.vertical, 8)
                        Divider()
                    }
                }
                .padding(.horizontal)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88, maximum: 136), spacing: 14)], spacing: 18) {
                ForEach(entries) { entry in
                    tile(for: entry)
                }
            }
            .padding()
        }
        .folderDropTarget(folder, cache: cache, springLoad: nil) { actionError = $0 }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func row(for entry: FileEntry) -> some View {
        Group {
            if entry.isDirectory {
                NavigationLink(value: folder.child(entry.name)) {
                    rowLabel(FileEntryLabel(entry: entry, itemCount: cache.itemCount(for: folder.child(entry.name))), isFolder: true)
                }
                .buttonStyle(StoreRowButtonStyle())
                .folderDropTarget(folder.child(entry.name), cache: cache, springLoad: { openFolder(folder.child(entry.name)) }) {
                    actionError = $0
                }
            } else {
                Button {
                    open(entry)
                } label: {
                    rowLabel(FileEntryLabel(entry: entry), isFolder: false)
                }
                .buttonStyle(StoreRowButtonStyle())
            }
        }
        .contextMenu { menuItems(for: entry) }
        .swipeActions(edge: .trailing) {
            // Not `role: .destructive`: that animates the row away before the confirmation
            // dialog has even been answered.
            Button("Delete", systemImage: "trash") { entryPendingDelete = entry }
                .tint(.red)
            Button("Share", systemImage: "link") { sharingEntry = entry }
                .tint(.blue)
        }
        .onDrag { StoreDragging.itemProvider(for: entry, in: folder, storeClient: storeClient) }
    }

    /// A row's full-width body: the label, a chevron for folders, and the row's own padding so the
    /// pressed and drop-target highlights span the whole width.
    private func rowLabel(_ label: FileEntryLabel, isFolder: Bool) -> some View {
        HStack(spacing: 8) {
            label
            if isFolder {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, Self.rowInset)
        .padding(.vertical, 10)
        .frame(minHeight: 66)
        .contentShape(.rect)
    }

    @ViewBuilder
    private func tile(for entry: FileEntry) -> some View {
        Group {
            if entry.isDirectory {
                NavigationLink(value: folder.child(entry.name)) {
                    FileEntryTile(entry: entry, thumbnailURL: nil)
                }
                .folderDropTarget(
                    folder.child(entry.name),
                    cache: cache,
                    highlightShape: AnyShape(RoundedRectangle(cornerRadius: 14)),
                    springLoad: { openFolder(folder.child(entry.name)) }
                ) {
                    actionError = $0
                }
            } else {
                Button {
                    open(entry)
                } label: {
                    FileEntryTile(
                        entry: entry,
                        thumbnailURL: FileKind(name: entry.name) == .image
                            ? storeClient.thumbnailURL(path: folder.entryPath(entry.name), location: folder.location, size: 240)
                            : nil
                    )
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu { menuItems(for: entry) }
        .onDrag { StoreDragging.itemProvider(for: entry, in: folder, storeClient: storeClient) }
    }

    @ViewBuilder
    private func menuItems(for entry: FileEntry) -> some View {
        if !entry.isDirectory {
            Button("Open", systemImage: "eye") { open(entry) }
        }
        Button(entry.isDirectory ? "Download as Zip" : "Download", systemImage: "arrow.down.circle") {
            Task { await download(entry) }
        }
        Button("Share", systemImage: "link") { sharingEntry = entry }
        Divider()
        if entry.isDirectory {
            let child = folder.child(entry.name)
            let isFavorite = favorites.contains(child)
            Button(isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: isFavorite ? "star.slash" : "star") {
                favorites.toggle(child)
            }
            Button("Change Icon…", systemImage: "folder.badge.gearshape") { iconPickerEntry = entry }
        }
        Button("Rename", systemImage: "pencil") {
            renameDraft = entry.name
            renamingEntry = entry
        }
        Button("Delete", systemImage: "trash", role: .destructive) { entryPendingDelete = entry }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if let activity {
                ProgressView()
                    .accessibilityLabel(activity)
            }
            Menu {
                Picker("View", selection: $viewMode) {
                    Label("List", systemImage: "list.bullet").tag(StoreViewMode.list)
                    Label("Icons", systemImage: "square.grid.2x2").tag(StoreViewMode.icons)
                }
                .pickerStyle(.inline)

                Section {
                    Button("New Folder", systemImage: "folder.badge.plus") {
                        newFolderName = ""
                        isCreatingFolder = true
                    }
                    Button("Upload Files", systemImage: "square.and.arrow.up") {
                        isImportingFiles = true
                    }
                }

                Section {
                    let isFavorite = favorites.contains(folder)
                    Button(isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: isFavorite ? "star.slash" : "star") {
                        favorites.toggle(folder)
                    }
                }

                if let disk = cache.disk {
                    Section("\(formatBytes(disk.used)) of \(formatBytes(disk.total)) used") {}
                }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .menuIndicator(.hidden)
        }
    }

    // MARK: - Loading

    /// Refreshes the listing (shown from the cache meanwhile), then prefetches the subfolders so
    /// the next folder opens instantly. Disk usage and share links load alongside, not after.
    private func load() async {
        async let disk: Void = cache.refreshDisk()
        async let fetchedShares: [TPCore.ShareLink]? = folder.isSharedRoot ? try? await storeClient.shares() : nil
        do {
            try await cache.load(folder)
            loadError = nil
        } catch is CancellationError {
            return
        } catch {
            // A failed refresh keeps the last good listing on screen and just reports it.
            if entries.isEmpty, shares.isEmpty {
                loadError = apiErrorMessage(error)
            } else {
                actionError = apiErrorMessage(error)
            }
        }
        if let fetched = await fetchedShares {
            shares = fetched
        }
        didAttemptLoad = true
        await disk
        await cache.prefetchChildren(of: folder)
    }

    // MARK: - Actions

    private func createFolder(named rawName: String) async {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            try await storeClient.createFolder(path: folder.entryPath(name), location: folder.location)
            await load()
        } catch {
            actionError = apiErrorMessage(error)
        }
    }

    private func rename(_ entry: FileEntry, to rawName: String) async {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != entry.name else { return }
        do {
            try await storeClient.rename(path: folder.entryPath(entry.name), newName: name, location: folder.location)
            if entry.isDirectory { cache.invalidate(folder.child(entry.name)) }
            await load()
        } catch {
            actionError = apiErrorMessage(error)
        }
    }

    private func delete(_ entry: FileEntry) async {
        do {
            try await storeClient.delete(path: folder.entryPath(entry.name), location: folder.location)
            withAnimation { cache.remove(entry, from: folder) }
            await load()
        } catch {
            actionError = apiErrorMessage(error)
        }
    }

    private func deleteShare(_ share: TPCore.ShareLink) async {
        do {
            try await storeClient.deleteShare(share.token)
            withAnimation { shares.removeAll { $0.token == share.token } }
        } catch {
            actionError = apiErrorMessage(error)
        }
    }

    private func download(_ entry: FileEntry) async {
        activity = "Downloading \(entry.name)"
        defer { activity = nil }
        do {
            let path = folder.entryPath(entry.name)
            if entry.isDirectory {
                exportFilename = "\(entry.name).zip"
                exportDocument = RawFileDocument(data: try await storeClient.downloadZip(path: path, location: folder.location))
            } else {
                exportFilename = entry.name
                exportDocument = RawFileDocument(data: try await storeClient.download(path: path, location: folder.location))
            }
        } catch {
            actionError = apiErrorMessage(error)
        }
    }

    /// Downloads to a temp file and hands it to Quick Look, which previews images, PDFs, video,
    /// text and Office files in place. (`UIApplication.open` on a local file URL, which this used
    /// before, silently does nothing on iOS.)
    private func open(_ entry: FileEntry) {
        Task {
            activity = "Opening \(entry.name)"
            defer { activity = nil }
            do {
                previewURL = try await downloadToTempFile(entry)
            } catch {
                actionError = apiErrorMessage(error)
            }
        }
    }

    private func downloadToTempFile(_ entry: FileEntry) async throws -> URL {
        let data = try await storeClient.download(path: folder.entryPath(entry.name), location: folder.location)
        return try StoreDragging.writeTemporaryFile(data, named: entry.name)
    }

    private func upload(_ urls: [URL]) async {
        for (index, url) in urls.enumerated() {
            activity = urls.count > 1 ? "Uploading \(index + 1) of \(urls.count)" : "Uploading \(url.lastPathComponent)"
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                try await storeClient.upload(
                    path: folder.path,
                    location: folder.location,
                    filename: url.lastPathComponent,
                    data: data,
                    mimeType: mimeType
                )
            } catch {
                actionError = apiErrorMessage(error)
            }
        }
        activity = nil
        await load()
    }
}

struct RawFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// The pressed look of a row outside a `List`: the same gray wash a list row gets when tapped.
private struct StoreRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.background))
    }
}
