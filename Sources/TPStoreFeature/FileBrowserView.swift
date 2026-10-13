import Foundation
import SwiftUI
import TPCore
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

public struct FileBrowserView: View {
    let storeClient: StoreClient
    let rootPath: String
    let resetSignal: Int
    let isAdmin: Bool

    @State private var location: StoreLocation = .external
    @State private var path: String
    @State private var history: [(location: StoreLocation, path: String)]
    @State private var historyIndex = 0
    @StateObject private var favoritesStore = StoreFavoritesStore()

    @State private var entries: [FileEntry] = []
    @State private var disk: DiskInfo?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var isGalleryView = false

    @State private var isCreatingFolder = false
    @State private var newFolderName = ""

    @State private var renamingEntry: FileEntry?
    @State private var renameDraft = ""

    @State private var entryPendingDelete: FileEntry?
    @State private var sharingEntry: FileEntry?

    @State private var isImportingFile = false
    @State private var isUploading = false

    @State private var isExportingFile = false
    @State private var downloadDocument: RawFileDocument?
    @State private var downloadFilename = ""

    @State private var isPreviewLoading = false

    @State private var topBarHeight: CGFloat = 70
    @State private var pillWidth: CGFloat = toolbarIconDimension * 2
    @State private var menuWidth: CGFloat = toolbarIconDimension

    public init(storeClient: StoreClient, rootPath: String = "", resetSignal: Int = 0, isAdmin: Bool = false) {
        self.storeClient = storeClient
        self.rootPath = rootPath
        self.resetSignal = resetSignal
        self.isAdmin = isAdmin
        _path = State(initialValue: rootPath)
        _history = State(initialValue: [(location: .external, path: rootPath)])
    }

    public var body: some View {
        #if os(macOS)
        HStack(spacing: 0) {
            StoreSidebarView(
                favoritesStore: favoritesStore,
                rootPath: rootPath,
                isAdmin: isAdmin,
                currentLocation: location,
                currentPath: path,
                onNavigate: { newLocation, newPath in navigate(to: newPath, location: newLocation) },
                onAddFavorite: { favoritesStore.addCurrentFolder(location: location, path: path, rootPath: rootPath) }
            )
            mainContent
        }
        .frame(minWidth: 840, minHeight: 540)
        #else
        mainContent
        #endif
    }

    private var mainContent: some View {
        ZStack(alignment: .top) {
            TPStoreTheme.background.ignoresSafeArea()
            content
            toolbar
            if isPreviewLoading {
                Color.black.opacity(0.3).ignoresSafeArea()
                ProgressView().tint(.white)
            }
        }
        .task { await load() }
        .onChange(of: resetSignal) { _, _ in
            resetToRoot()
        }
        .alert("New folder", isPresented: $isCreatingFolder) {
            TextField("Name", text: $newFolderName)
            Button("Create") { Task { await createFolder() } }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        }
        .alert(
            "Rename \(renamingEntry?.name ?? "")",
            isPresented: Binding(
                get: { renamingEntry != nil },
                set: { if !$0 { renamingEntry = nil } }
            )
        ) {
            TextField("Name", text: $renameDraft)
            Button("Rename") { Task { await renameSelected() } }
            Button("Cancel", role: .cancel) { renamingEntry = nil }
        }
        .confirmationDialog(
            "Delete \(entryPendingDelete?.name ?? "")?",
            isPresented: Binding(
                get: { entryPendingDelete != nil },
                set: { if !$0 { entryPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { Task { await deleteSelected() } }
            Button("Cancel", role: .cancel) { entryPendingDelete = nil }
        }
        .fileImporter(isPresented: $isImportingFile, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                Task { await upload(urls) }
            case .failure(let error):
                loadError = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $isExportingFile,
            document: downloadDocument,
            contentType: .data,
            defaultFilename: downloadFilename
        ) { result in
            if case .failure(let error) = result {
                loadError = error.localizedDescription
            }
        }
        .sheet(item: $sharingEntry) { entry in
            ShareSheetView(entry: entry, parentPath: path, location: location, storeClient: storeClient)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        GlassEffectContainer(spacing: 10) {
            ZStack {
                // Centered on the full toolbar width (not just the gap between the
                // buttons), but padded away from the pill/menu zones -- using their
                // real measured widths, not a guess -- so a long name truncates
                // with a trailing "..." instead of sliding underneath them.
                Text(currentFolderTitle)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, titleSideInset)

                HStack(spacing: 10) {
                    navigationPill
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { pillWidth = $0 }
                    Spacer()
                    Menu {
                        if let disk {
                            Text("\(formatBytes(disk.used)) of \(formatBytes(disk.total)) used")
                            Divider()
                        }
                        Button {
                            isGalleryView.toggle()
                        } label: {
                            Label(isGalleryView ? "List view" : "Gallery view", systemImage: isGalleryView ? "list.bullet" : "square.grid.2x2")
                        }
                        Button {
                            newFolderName = ""
                            isCreatingFolder = true
                        } label: {
                            Label("New folder", systemImage: "folder.badge.plus")
                        }
                        Button {
                            isImportingFile = true
                        } label: {
                            Label("Upload", systemImage: "arrow.up.circle")
                        }
                        Button {
                            Task { await load() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        // Deliberately NOT toolbarIcon(): that helper hard-codes a
                        // 46x46/32x32 inner frame which floors the glass button's
                        // size no matter what outer frame/controlSize is applied on
                        // top. This label is sized just for this button.
                        Image(systemName: "ellipsis")
                            .font(.system(size: ellipsisIconFontSize, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: ellipsisIconDimension, height: ellipsisIconDimension)
                    }
                    .menuIndicator(.hidden)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { menuWidth = $0 }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { newHeight in
            topBarHeight = newHeight
        }
    }

    /// Symmetric padding that keeps the title's truncation box centered on the
    /// full toolbar width while still clearing the wider of the two side buttons
    /// on both edges. Measured from the actual rendered buttons (rather than a
    /// guessed width) so it reserves no more space than is really needed.
    private var titleSideInset: CGFloat {
        max(pillWidth, menuWidth) + 8
    }

    private var currentFolderTitle: String {
        if path == rootPath, location == .external {
            return rootPath.isEmpty ? "Store" : "Home"
        }
        if path.isEmpty {
            return location == .server ? "System" : "Disk"
        }
        let last = path.split(separator: "/").last.map(String.init) ?? path
        return last == "shared" ? "Shared" : last
    }

    private var navigationPill: some View {
        NavigationPill(
            canGoBack: historyIndex > 0,
            canGoForward: historyIndex < history.count - 1,
            onBack: goBack,
            onForward: goForward
        )
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading && entries.isEmpty && loadError == nil {
            VStack {
                Spacer()
                ProgressView().tint(.white)
                Spacer()
            }
        } else if let loadError {
            VStack {
                Spacer()
                Text(loadError).foregroundStyle(TPStoreTheme.danger)
                Spacer()
            }
        } else if entries.isEmpty {
            VStack {
                Spacer()
                Text("Empty folder")
                    .font(.system(size: 14))
                    .foregroundStyle(TPStoreTheme.textMuted)
                Spacer()
            }
        } else {
            ZStack(alignment: .top) {
                if isGalleryView { galleryContent } else { listContent }
                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .padding(.top, topBarHeight + 16)
                }
            }
            .opacity(isLoading ? 0.45 : 1.0)
            .allowsHitTesting(!isLoading)
            .animation(.easeOut(duration: 0.15), value: isLoading)
        }
    }

    private var listContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.clear.frame(height: topBarHeight)
                listHeader
                ForEach(entries) { entry in
                    entryRow(entry)
                    Rectangle().fill(TPStoreTheme.divider).frame(height: 0.5)
                }
            }
        }
    }

    private var listHeader: some View {
        HStack {
            Text("NAME")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("SIZE")
                .frame(width: 90, alignment: .trailing)
        }
        .font(.system(size: 11.2, weight: .medium))
        .tracking(0.8)
        .foregroundStyle(TPStoreTheme.textMuted)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 0.5)
        }
    }

    private var galleryContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.clear.frame(height: topBarHeight)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
                    ForEach(entries) { entry in
                        galleryTile(entry)
                    }
                }
                .padding(16)
                .padding(.horizontal, 4)
            }
        }
    }

    private func entryRow(_ entry: FileEntry) -> some View {
        let row = HStack(spacing: 11) {
            icon(for: entry)
                .frame(width: 20, height: 20)

            Text(entry.name)
                .font(.system(size: 16))
                .foregroundStyle(TPStoreTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if let size = entry.size {
                Text(formatBytes(size))
                    .font(.system(size: 14))
                    .foregroundStyle(TPStoreTheme.textMuted)
                    .frame(width: 90, alignment: .trailing)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .contentShape(Rectangle())

        return Group {
            if entry.isDirectory {
                // No double-tap recognizer here: mixing single+double tap on the
                // same row forces SwiftUI to wait out the double-tap timeout
                // before firing navigation, which is what made folder taps feel slow.
                Button {
                    navigate(to: path.isEmpty ? entry.name : "\(path)/\(entry.name)")
                } label: {
                    row
                }
                .buttonStyle(RowPressButtonStyle())
            } else {
                row.onTapGesture(count: 2) {
                    openPreview(entry)
                }
            }
        }
        .contextMenu { contextMenuItems(entry) }
        .onDrag { fileItemProvider(for: entry) }
    }

    private func galleryTile(_ entry: FileEntry) -> some View {
        let tile = VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 110, height: 110)
                if entry.type == .file, isImage(entry.name) {
                    AsyncImage(url: storeClient.thumbnailURL(path: entryPath(entry), location: location)) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 110, height: 110)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            icon(for: entry).font(.system(size: 36))
                        }
                    }
                } else {
                    icon(for: entry).font(.system(size: 36))
                }
            }
            Text(entry.name)
                .font(.system(size: 12))
                .foregroundStyle(TPStoreTheme.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .contentShape(RoundedRectangle(cornerRadius: 10))

        return Group {
            if entry.isDirectory {
                Button {
                    navigate(to: path.isEmpty ? entry.name : "\(path)/\(entry.name)")
                } label: {
                    tile
                }
                .buttonStyle(RowPressButtonStyle())
            } else {
                tile.onTapGesture(count: 2) {
                    openPreview(entry)
                }
            }
        }
        .contextMenu { contextMenuItems(entry) }
        .onDrag { fileItemProvider(for: entry) }
    }

    @ViewBuilder
    private func contextMenuItems(_ entry: FileEntry) -> some View {
        if entry.isDirectory {
            Button("Download as zip") { Task { await startDownloadZip(entry) } }
        } else {
            Button("Download") { Task { await startDownload(entry) } }
        }
        Button("Share") {
            sharingEntry = entry
        }
        Button("Rename") {
            renamingEntry = entry
            renameDraft = entry.name
        }
        Button("Delete", role: .destructive) {
            entryPendingDelete = entry
        }
    }

    private func icon(for entry: FileEntry) -> some View {
        let (symbol, color) = iconInfo(for: entry)
        return Image(systemName: symbol).foregroundStyle(color)
    }

    private func iconInfo(for entry: FileEntry) -> (String, Color) {
        if entry.isDirectory {
            return ("folder.fill", TPStoreTheme.accentGray)
        }
        switch entry.type {
        case .shareLink:
            return ("folder.badge.person.crop", TPStoreTheme.accentGray)
        case .uploadPending:
            return ("icloud.and.arrow.up", TPStoreTheme.warning)
        default:
            break
        }
        let ext = (entry.name as NSString).pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "gif", "webp", "svg", "bmp", "tiff", "heic"].contains(ext) {
            return ("photo", TPStoreTheme.textDisabled)
        }
        if ["mp4", "mkv", "avi", "mov", "webm", "flv", "m4v"].contains(ext) {
            return ("film", TPStoreTheme.textDisabled)
        }
        if ["mp3", "wav", "flac", "ogg", "aac", "m4a", "opus"].contains(ext) {
            return ("music.note", TPStoreTheme.textDisabled)
        }
        if ["zip", "tar", "gz", "bz2", "7z", "rar", "xz", "zst"].contains(ext) {
            return ("archivebox", TPStoreTheme.textDisabled)
        }
        if ["js", "ts", "py", "go", "rs", "java", "c", "cpp", "h", "css", "html", "json", "yaml", "sh", "bash", "zsh", "toml", "xml", "vue", "jsx", "tsx"].contains(ext) {
            return ("chevron.left.forwardslash.chevron.right", TPStoreTheme.textDisabled)
        }
        if ["pdf", "txt", "md", "doc", "docx", "odt", "rtf", "csv", "xls", "xlsx"].contains(ext) {
            return ("doc.text", TPStoreTheme.textDisabled)
        }
        return ("doc", TPStoreTheme.textDisabled)
    }

    private func isImage(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "gif", "webp", "bmp", "tiff", "heic"].contains(ext)
    }

    private func entryPath(_ entry: FileEntry) -> String {
        path.isEmpty ? entry.name : "\(path)/\(entry.name)"
    }

    // MARK: - Navigation

    private func navigate(to newPath: String, location newLocation: StoreLocation? = nil) {
        if let newLocation { location = newLocation }
        path = newPath
        history.removeSubrange((historyIndex + 1)...)
        history.append((location: location, path: newPath))
        historyIndex = history.count - 1
        Task { await load() }
    }

    private func goBack() {
        guard historyIndex > 0 else { return }
        historyIndex -= 1
        (location, path) = history[historyIndex]
        Task { await load() }
    }

    private func goForward() {
        guard historyIndex < history.count - 1 else { return }
        historyIndex += 1
        (location, path) = history[historyIndex]
        Task { await load() }
    }

    private func resetToRoot() {
        guard path != rootPath || location != .external else { return }
        location = .external
        path = rootPath
        history = [(location: .external, path: rootPath)]
        historyIndex = 0
        Task { await load() }
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            async let listing = storeClient.listDirectory(path: path, location: location)
            async let diskInfo = storeClient.diskInfo()
            let (fetchedListing, fetchedDisk) = try await (listing, diskInfo)
            entries = fetchedListing.entries.sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            disk = fetchedDisk
        } catch {
            loadError = apiErrorMessage(error)
        }
    }

    private func createFolder() async {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        newFolderName = ""
        guard !name.isEmpty else { return }
        do {
            let folderPath = path.isEmpty ? name : "\(path)/\(name)"
            try await storeClient.createFolder(path: folderPath, location: location)
            await load()
        } catch {
            loadError = apiErrorMessage(error)
        }
    }

    private func renameSelected() async {
        guard let entry = renamingEntry else { return }
        let newName = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        renamingEntry = nil
        guard !newName.isEmpty, newName != entry.name else { return }
        do {
            let entryPath = path.isEmpty ? entry.name : "\(path)/\(entry.name)"
            try await storeClient.rename(path: entryPath, newName: newName, location: location)
            await load()
        } catch {
            loadError = apiErrorMessage(error)
        }
    }

    private func deleteSelected() async {
        guard let entry = entryPendingDelete else { return }
        entryPendingDelete = nil
        do {
            let entryPath = path.isEmpty ? entry.name : "\(path)/\(entry.name)"
            try await storeClient.delete(path: entryPath, location: location)
            await load()
        } catch {
            loadError = apiErrorMessage(error)
        }
    }

    private func startDownload(_ entry: FileEntry) async {
        do {
            let entryPath = path.isEmpty ? entry.name : "\(path)/\(entry.name)"
            let data = try await storeClient.download(path: entryPath, location: location)
            downloadDocument = RawFileDocument(data: data)
            downloadFilename = entry.name
            isExportingFile = true
        } catch {
            loadError = apiErrorMessage(error)
        }
    }

    private func downloadToTempFile(_ entry: FileEntry) async throws -> URL {
        let entryPath = path.isEmpty ? entry.name : "\(path)/\(entry.name)"
        let data = try await storeClient.download(path: entryPath, location: location)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let tempURL = tempDir.appendingPathComponent(entry.name)
        try data.write(to: tempURL)
        return tempURL
    }

    private func openPreview(_ entry: FileEntry) {
        Task {
            isPreviewLoading = true
            defer { isPreviewLoading = false }
            do {
                let tempURL = try await downloadToTempFile(entry)
                #if os(macOS)
                NSWorkspace.shared.open(tempURL)
                #elseif os(iOS)
                await UIApplication.shared.open(tempURL)
                #endif
            } catch {
                loadError = apiErrorMessage(error)
            }
        }
    }

    /// Lazily downloads the file only once a drop target actually accepts it, mirroring Finder's file-promise drag.
    private func fileItemProvider(for entry: FileEntry) -> NSItemProvider {
        let provider = NSItemProvider()
        guard !entry.isDirectory else { return provider }
        let utType = UTType(filenameExtension: (entry.name as NSString).pathExtension) ?? .data
        provider.suggestedName = entry.name
        provider.registerFileRepresentation(forTypeIdentifier: utType.identifier, fileOptions: [], visibility: .all) { completion in
            Task {
                do {
                    let tempURL = try await downloadToTempFile(entry)
                    completion(tempURL, false, nil)
                } catch {
                    completion(nil, false, error)
                }
            }
            return nil
        }
        return provider
    }

    private func startDownloadZip(_ entry: FileEntry) async {
        do {
            let entryPath = path.isEmpty ? entry.name : "\(path)/\(entry.name)"
            let data = try await storeClient.downloadZip(path: entryPath, location: location)
            downloadDocument = RawFileDocument(data: data)
            downloadFilename = "\(entry.name).zip"
            isExportingFile = true
        } catch {
            loadError = apiErrorMessage(error)
        }
    }

    private func upload(_ urls: [URL]) async {
        isUploading = true
        defer { isUploading = false }
        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                try await storeClient.upload(
                    path: path,
                    location: location,
                    filename: url.lastPathComponent,
                    data: data,
                    mimeType: mimeType(for: url)
                )
            } catch {
                loadError = apiErrorMessage(error)
            }
        }
        await load()
    }

    private func mimeType(for url: URL) -> String {
        guard let type = UTType(filenameExtension: url.pathExtension), let mime = type.preferredMIMEType else {
            return "application/octet-stream"
        }
        return mime
    }
}

var toolbarIconDimension: CGFloat {
    #if os(macOS)
    32
    #else
    46
    #endif
}

// Smaller than toolbarIconDimension on purpose: unlike the nav pill (which uses
// the manual .glassEffect() API), the ellipsis Menu uses .buttonStyle(.glass),
// which only adds padding/chrome around whatever size its label already is --
// it never shrinks it. So the label itself must be small for the button to be small.
var ellipsisIconDimension: CGFloat {
    #if os(macOS)
    23
    #else
    30
    #endif
}

var ellipsisIconFontSize: CGFloat {
    #if os(macOS)
    12
    #else
    16
    #endif
}

func toolbarIcon(_ systemImage: String, enabled: Bool = true) -> some View {
    #if os(macOS)
    let fontSize: CGFloat = 13
    #else
    let fontSize: CGFloat = 17
    #endif
    return Image(systemName: systemImage)
        .font(.system(size: fontSize, weight: .medium))
        .foregroundStyle(enabled ? Color.white : Color.white.opacity(0.3))
        .frame(width: toolbarIconDimension, height: toolbarIconDimension)
}

struct NavigationPill: View {
    let canGoBack: Bool
    let canGoForward: Bool
    let onBack: () -> Void
    let onForward: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            pillButton(systemImage: "chevron.left", enabled: canGoBack, action: onBack)
            pillButton(systemImage: "chevron.right", enabled: canGoForward, action: onForward)
        }
        // .interactive() is the system's own press animation for a glass
        // shape (the same machinery behind .buttonStyle(.glass)), applied to
        // the capsule as a whole -- so pressing either chevron grows/lightens
        // the entire pill together with native quality, not a hand-rolled one.
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func pillButton(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            toolbarIcon(systemImage, enabled: enabled)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Highlights a file/folder row while pressed, mirroring the Files app's
/// instant tap feedback before the navigation/action actually completes.
private struct RowPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.white.opacity(0.08) : Color.clear)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

enum TPStoreTheme {
    static let background = Color.black
    static let textPrimary = Color(white: 1.0)
    static let textSecondary = Color(red: 0.820, green: 0.820, blue: 0.839)
    static let textMuted = Color(red: 0.322, green: 0.322, blue: 0.322)
    static let textDisabled = Color(red: 0.388, green: 0.388, blue: 0.4)
    static let accentGray = Color(red: 0.557, green: 0.557, blue: 0.576)
    static let danger = Color(red: 1.0, green: 0.271, blue: 0.227)
    static let success = Color(red: 0.188, green: 0.820, blue: 0.345)
    static let warning = Color(red: 1.0, green: 0.624, blue: 0.039)
    static let info = Color(red: 0.039, green: 0.518, blue: 1.0)
    static let divider = Color.white.opacity(0.05)
    static let breadcrumbMuted = Color(red: 0.451, green: 0.451, blue: 0.451)
    static let breadcrumbSeparator = Color(red: 0.251, green: 0.251, blue: 0.251)
    static let surface = Color(red: 0.110, green: 0.110, blue: 0.118).opacity(0.97)
    static let modalBorder = Color.white.opacity(0.14)
    static let urlRowBackground = Color.white.opacity(0.05)
    static let urlRowBorder = Color.white.opacity(0.1)
    static let urlRowText = Color(red: 0.671, green: 0.671, blue: 0.671)
    static let copyIdle = Color(red: 0.388, green: 0.388, blue: 0.4)
}

private struct RawFileDocument: FileDocument {
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

private func formatBytes(_ count: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
}
