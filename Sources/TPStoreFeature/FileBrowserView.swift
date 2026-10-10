import Foundation
import SwiftUI
import TPCore
import UniformTypeIdentifiers

public struct FileBrowserView: View {
    let storeClient: StoreClient

    @State private var location: StoreLocation = .external
    @State private var path = ""
    @State private var history: [String] = [""]
    @State private var historyIndex = 0

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

    public init(storeClient: StoreClient) {
        self.storeClient = storeClient
    }

    public var body: some View {
        ZStack {
            TPStoreTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                toolbar
                content
                bottomBar
            }
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 540)
        #endif
        .task { await load() }
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
        HStack(spacing: 10) {
            navigationPill
            Spacer()
            toolbarCircleButton(systemImage: isGalleryView ? "list.bullet" : "square.grid.2x2") {
                isGalleryView.toggle()
            }
            Menu {
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
                toolbarCircleLabel(systemImage: "ellipsis")
            }
            .menuIndicator(.hidden)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var navigationPill: some View {
        HStack(spacing: 0) {
            pillButton(systemImage: "chevron.left", enabled: historyIndex > 0) { goBack() }
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 0.5, height: 14)
            pillButton(systemImage: "chevron.right", enabled: historyIndex < history.count - 1) { goForward() }
        }
        .background {
            Capsule()
                .fill(Color.white.opacity(0.07))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
        }
    }

    private func pillButton(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(enabled ? Color.white.opacity(0.85) : Color.white.opacity(0.2))
                .frame(width: 40, height: 36)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func toolbarCircleButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            toolbarCircleLabel(systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }

    private func toolbarCircleLabel(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.85))
            .frame(width: 36, height: 36)
            .background {
                Circle()
                    .fill(Color.white.opacity(0.07))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
            }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(Color.white.opacity(0.05)).frame(height: 0.5)
            VStack(alignment: .leading, spacing: 8) {
                breadcrumb
                if let disk {
                    diskUsageBar(disk)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private var breadcrumb: some View {
        let segments = path.split(separator: "/").map(String.init)
        return HStack(spacing: 4) {
            breadcrumbButton(title: "Store", targetPath: "")
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                Text("\u{203A}")
                    .font(.system(size: 13.6))
                    .foregroundStyle(TPStoreTheme.breadcrumbSeparator)
                breadcrumbButton(title: segment, targetPath: segments[0...index].joined(separator: "/"))
            }
        }
    }

    private func breadcrumbButton(title: String, targetPath: String) -> some View {
        Button {
            navigate(to: targetPath)
        } label: {
            Text(title)
                .font(.system(size: 13.6, weight: .medium))
                .foregroundStyle(targetPath == path ? .white : TPStoreTheme.breadcrumbMuted)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 128, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func diskUsageBar(_ disk: DiskInfo) -> some View {
        let fraction = disk.total > 0 ? Double(disk.used) / Double(disk.total) : 0
        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(Color.white.opacity(0.35))
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 4)

            Text("\(formatBytes(disk.used)) of \(formatBytes(disk.total)) used")
                .font(.system(size: 11))
                .foregroundStyle(TPStoreTheme.textMuted)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            Spacer()
            ProgressView().tint(.white)
            Spacer()
        } else if let loadError {
            Spacer()
            Text(loadError).foregroundStyle(TPStoreTheme.danger)
            Spacer()
        } else if entries.isEmpty {
            Spacer()
            Text("Empty folder")
                .font(.system(size: 14))
                .foregroundStyle(TPStoreTheme.textMuted)
            Spacer()
        } else if isGalleryView {
            galleryContent
        } else {
            listContent
        }
    }

    private var listContent: some View {
        ScrollView {
            VStack(spacing: 0) {
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
                ForEach(entries) { entry in
                    galleryTile(entry)
                }
            }
            .padding(16)
            .padding(.horizontal, 4)
        }
    }

    private func entryRow(_ entry: FileEntry) -> some View {
        HStack(spacing: 11) {
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
        .onTapGesture {
            guard entry.isDirectory else { return }
            navigate(to: path.isEmpty ? entry.name : "\(path)/\(entry.name)")
        }
        .contextMenu { contextMenuItems(entry) }
    }

    private func galleryTile(_ entry: FileEntry) -> some View {
        VStack(spacing: 8) {
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
        .onTapGesture {
            guard entry.isDirectory else { return }
            navigate(to: path.isEmpty ? entry.name : "\(path)/\(entry.name)")
        }
        .contextMenu { contextMenuItems(entry) }
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

    private func navigate(to newPath: String) {
        path = newPath
        history.removeSubrange((historyIndex + 1)...)
        history.append(newPath)
        historyIndex = history.count - 1
        Task { await load() }
    }

    private func goBack() {
        guard historyIndex > 0 else { return }
        historyIndex -= 1
        path = history[historyIndex]
        Task { await load() }
    }

    private func goForward() {
        guard historyIndex < history.count - 1 else { return }
        historyIndex += 1
        path = history[historyIndex]
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
