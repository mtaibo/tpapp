import SwiftUI
import TPCore
import UniformTypeIdentifiers

public struct SharedView: View {
    private static let rootPath = "shared"

    let storeClient: StoreClient
    let resetSignal: Int

    @State private var path = SharedView.rootPath
    @State private var history: [String] = [SharedView.rootPath]
    @State private var historyIndex = 0

    @State private var entries: [FileEntry] = []
    @State private var shares: [TPCore.ShareLink] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var copiedToken: String?
    @State private var topBarHeight: CGFloat = 70
    @State private var disk: DiskInfo?

    @State private var isGalleryView = false
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""
    @State private var isImportingFile = false
    @State private var isUploading = false

    @State private var isExportingFile = false
    @State private var downloadDocument: RawFileDocument?
    @State private var downloadFilename = ""

    public init(storeClient: StoreClient, resetSignal: Int = 0) {
        self.storeClient = storeClient
        self.resetSignal = resetSignal
    }

    public var body: some View {
        ZStack(alignment: .top) {
            TPStoreTheme.background.ignoresSafeArea()
            content
            toolbar
            if isUploading {
                Color.black.opacity(0.3).ignoresSafeArea()
                ProgressView().tint(.white)
            }
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 540)
        #endif
        .task { await load() }
        .onChange(of: resetSignal) { _, _ in
            resetToRoot()
        }
        .alert("New folder", isPresented: $isCreatingFolder) {
            TextField("Name", text: $newFolderName)
            Button("Create") { Task { await createFolder() } }
            Button("Cancel", role: .cancel) { newFolderName = "" }
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
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        GlassEffectContainer(spacing: 10) {
            ZStack {
                Text(currentFolderTitle)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack(spacing: 10) {
                    navigationPill
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
                        Image(systemName: "ellipsis")
                            .font(.system(size: ellipsisIconFontSize, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: ellipsisIconDimension, height: ellipsisIconDimension)
                    }
                    .menuIndicator(.hidden)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { newHeight in
            topBarHeight = newHeight
        }
    }

    private var currentFolderTitle: String {
        path == Self.rootPath ? "Shared" : (path.split(separator: "/").last.map(String.init) ?? path)
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
        if isLoading {
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
        } else if shares.isEmpty && entries.isEmpty {
            VStack {
                Spacer()
                Text(path == Self.rootPath ? "No shared folders or links yet" : "Empty folder")
                    .font(.system(size: 14))
                    .foregroundStyle(TPStoreTheme.textMuted)
                Spacer()
            }
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: topBarHeight)
                    if !shares.isEmpty {
                        sectionHeader("Links")
                        ForEach(shares) { share in
                            shareRow(share)
                            Rectangle().fill(TPStoreTheme.divider).frame(height: 0.5)
                        }
                    }
                    if !entries.isEmpty {
                        sectionHeader("Folders")
                        if isGalleryView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
                                ForEach(entries) { entry in
                                    galleryTile(entry)
                                }
                            }
                            .padding(.horizontal, 16)
                        } else {
                            ForEach(entries) { entry in
                                entryRow(entry)
                                Rectangle().fill(TPStoreTheme.divider).frame(height: 0.5)
                            }
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11.2, weight: .medium))
            .tracking(0.8)
            .foregroundStyle(TPStoreTheme.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
    }

    private func entryRow(_ entry: FileEntry) -> some View {
        HStack(spacing: 11) {
            Image(systemName: entry.isDirectory ? "folder.fill" : "doc.fill")
                .font(.system(size: 16))
                .foregroundStyle(TPStoreTheme.accentGray)
                .frame(width: 20, height: 20)

            Text(entry.name)
                .font(.system(size: 16))
                .foregroundStyle(TPStoreTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .onTapGesture {
            guard entry.isDirectory else { return }
            navigate(to: "\(path)/\(entry.name)")
        }
        .contextMenu { downloadMenuItem(entry) }
    }

    private func galleryTile(_ entry: FileEntry) -> some View {
        let tile = VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 110, height: 110)
                Image(systemName: entry.isDirectory ? "folder.fill" : "doc.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(TPStoreTheme.accentGray)
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

        return tile
            .contentShape(Rectangle())
            .onTapGesture {
                guard entry.isDirectory else { return }
                navigate(to: "\(path)/\(entry.name)")
            }
            .contextMenu { downloadMenuItem(entry) }
    }

    /// Tapping a file entry here was a silent no-op (only folders navigate) — this gives it
    /// somewhere to go, the same "Download"/"Download as zip" action `FileBrowserView` offers.
    @ViewBuilder
    private func downloadMenuItem(_ entry: FileEntry) -> some View {
        if entry.isDirectory {
            Button("Download as zip") { Task { await startDownloadZip(entry) } }
        } else {
            Button("Download") { Task { await startDownload(entry) } }
        }
    }

    private func shareRow(_ share: TPCore.ShareLink) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 11) {
                Image(systemName: share.isFile ? "doc.fill" : "folder.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(TPStoreTheme.accentGray)
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName(for: share))
                        .font(.system(size: 16))
                        .foregroundStyle(TPStoreTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(share.url)
                        .font(.system(size: 12))
                        .foregroundStyle(TPStoreTheme.urlRowText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button {
                    copyToClipboard(share.url)
                    copiedToken = share.token
                } label: {
                    Image(systemName: copiedToken == share.token ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(copiedToken == share.token ? TPStoreTheme.success : TPStoreTheme.copyIdle)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy link")

                Button {
                    Task { await delete(share) }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(TPStoreTheme.danger)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete link")
            }

            if share.hasPassword || share.editable || share.isPublic {
                HStack(spacing: 6) {
                    if share.hasPassword { badge("Password") }
                    if share.editable { badge("Editable") }
                    if share.isPublic { badge("Public") }
                }
                .padding(.leading, 31)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
    }

    private func badge(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(0.3)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(TPStoreTheme.accentGray)
            .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    private func displayName(for share: TPCore.ShareLink) -> String {
        share.path.split(separator: "/").last.map(String.init) ?? share.path
    }

    private func formatBytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
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

    private func resetToRoot() {
        guard path != Self.rootPath else { return }
        path = Self.rootPath
        history = [Self.rootPath]
        historyIndex = 0
        Task { await load() }
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            async let listing = storeClient.listDirectory(path: path, location: .external)
            async let diskInfo = storeClient.diskInfo()
            let (fetchedListing, fetchedDisk) = try await (listing, diskInfo)
            entries = fetchedListing.entries.sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            disk = fetchedDisk
            shares = path == Self.rootPath ? try await storeClient.shares() : []
        } catch {
            loadError = apiErrorMessage(error)
        }
    }

    private func delete(_ share: TPCore.ShareLink) async {
        do {
            try await storeClient.deleteShare(share.token)
            shares.removeAll { $0.token == share.token }
        } catch {
            loadError = apiErrorMessage(error)
        }
    }

    private func createFolder() async {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        newFolderName = ""
        guard !name.isEmpty else { return }
        do {
            try await storeClient.createFolder(path: "\(path)/\(name)", location: .external)
            await load()
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
                    location: .external,
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

    private func startDownload(_ entry: FileEntry) async {
        do {
            let data = try await storeClient.download(path: "\(path)/\(entry.name)", location: .external)
            downloadDocument = RawFileDocument(data: data)
            downloadFilename = entry.name
            isExportingFile = true
        } catch {
            loadError = apiErrorMessage(error)
        }
    }

    private func startDownloadZip(_ entry: FileEntry) async {
        do {
            let data = try await storeClient.downloadZip(path: "\(path)/\(entry.name)", location: .external)
            downloadDocument = RawFileDocument(data: data)
            downloadFilename = "\(entry.name).zip"
            isExportingFile = true
        } catch {
            loadError = apiErrorMessage(error)
        }
    }

    private func mimeType(for url: URL) -> String {
        guard let type = UTType(filenameExtension: url.pathExtension), let mime = type.preferredMIMEType else {
            return "application/octet-stream"
        }
        return mime
    }
}
