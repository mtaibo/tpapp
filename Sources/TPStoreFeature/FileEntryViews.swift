import SwiftUI
import TPCore
import TPUI

/// Broad file category from the extension, driving both the icon and whether a thumbnail exists.
enum FileKind: Equatable {
    case image, video, audio, archive, code, document, other

    init(name: String) {
        switch (name as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "gif", "webp", "bmp", "tiff", "heic": self = .image
        case "mp4", "mkv", "avi", "mov", "webm", "flv", "m4v": self = .video
        case "mp3", "wav", "flac", "ogg", "aac", "m4a", "opus": self = .audio
        case "zip", "tar", "gz", "bz2", "7z", "rar", "xz", "zst": self = .archive
        case "js", "ts", "py", "go", "rs", "java", "c", "cpp", "h", "css", "html", "json", "yaml", "sh", "bash", "zsh",
             "toml", "xml", "vue", "jsx", "tsx", "swift":
            self = .code
        case "pdf", "txt", "md", "doc", "docx", "odt", "rtf", "csv", "xls", "xlsx", "pages", "numbers", "key": self = .document
        default: self = .other
        }
    }

    var systemImage: String {
        switch self {
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "music.note"
        case .archive: return "archivebox"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .document: return "doc.text"
        case .other: return "doc"
        }
    }
}

private func iconInfo(for entry: FileEntry) -> (symbol: String, style: AnyShapeStyle) {
    switch entry.type {
    case .directory, .shareLink: return ("folder.fill", AnyShapeStyle(.tint))
    case .uploadPending: return ("icloud.and.arrow.up", AnyShapeStyle(.orange))
    case .file: return (FileKind(name: entry.name).systemImage, AnyShapeStyle(.secondary))
    }
}

/// "22/06/2026 - 11 items" for folders and "22/07/2026 - 140 KB" for files, like the Files app.
/// A folder's count only shows once its listing has been loaded or prefetched.
private func subtitle(for entry: FileEntry, itemCount: Int?) -> String {
    if entry.type == .uploadPending, let received = entry.bytesReceived {
        return "Uploading - \(formatBytes(received))"
    }
    let modified = Date(timeIntervalSince1970: entry.modified).formatted(date: .numeric, time: .omitted)
    if entry.isDirectory {
        guard let itemCount else { return modified }
        return "\(modified) - \(itemCount == 1 ? "1 item" : "\(itemCount) items")"
    }
    if let size = entry.size {
        return "\(modified) - \(formatBytes(size))"
    }
    return modified
}

/// The Files app's folder: a light blue folder with a darker tab behind it, and for well-known
/// folders (Downloads, Documents, Shared…) a glyph pressed into the front, instead of a flat
/// `folder.fill` symbol in the accent color.
struct FolderIcon: View {
    let glyph: String?

    init(glyph: String? = nil) {
        self.glyph = glyph
    }

    init(name: String, isShared: Bool = false) {
        self.glyph = isShared ? "person.2.fill" : Self.glyph(forFolderNamed: name)
    }

    private static let back = Color(red: 0.36, green: 0.66, blue: 0.89)
    private static let frontTop = Color(red: 0.55, green: 0.80, blue: 0.97)
    private static let frontBottom = Color(red: 0.45, green: 0.74, blue: 0.94)
    private static let glyphColor = Color(red: 0.25, green: 0.55, blue: 0.80)

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let radius = height * 0.1
            let frontTop = height * 0.2
            ZStack(alignment: .topLeading) {
                // Back panel and its tab.
                UnevenRoundedRectangle(topLeadingRadius: radius, topTrailingRadius: radius)
                    .fill(Self.back)
                    .frame(width: width * 0.42, height: frontTop + radius)
                RoundedRectangle(cornerRadius: radius)
                    .fill(Self.back)
                    .frame(width: width, height: height - height * 0.08)
                    .offset(y: height * 0.08)

                // Front panel, with a faint highlight along its top edge.
                RoundedRectangle(cornerRadius: radius)
                    .fill(LinearGradient(colors: [Self.frontTop, Self.frontBottom], startPoint: .top, endPoint: .bottom))
                    .overlay(alignment: .top) {
                        Capsule()
                            .fill(.white.opacity(0.35))
                            .frame(height: max(height * 0.025, 0.5))
                            .padding(.horizontal, radius)
                    }
                    .frame(width: width, height: height - frontTop)
                    .offset(y: frontTop)

                if let glyph {
                    Image(systemName: glyph)
                        .resizable()
                        .scaledToFit()
                        .fontWeight(.semibold)
                        .foregroundStyle(Self.glyphColor.shadow(.inner(color: .black.opacity(0.3), radius: 0.5, y: 0.5)))
                        .frame(width: width * 0.4, height: (height - frontTop) * 0.52)
                        .frame(width: width, height: height - frontTop)
                        .offset(y: frontTop)
                }
            }
        }
        .aspectRatio(1.25, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// Glyphs the Files app uses for its own well-known folders, matched in English and Spanish.
    static func glyph(forFolderNamed name: String) -> String? {
        switch name.lowercased() {
        case "downloads", "descargas": return "arrow.down.circle"
        case "documents", "documentos": return "doc"
        case "desktop", "escritorio": return "menubar.dock.rectangle"
        case "photos", "fotos", "pictures", "imágenes", "imagenes": return "photo"
        case "music", "música", "musica": return "music.note"
        case "movies", "videos", "vídeos", "películas", "peliculas": return "film"
        case "shared", "compartido": return "person.2.fill"
        case "backups", "backup", "copias": return "clock.arrow.circlepath"
        default: return nil
        }
    }
}

/// The icon in front of a row or tile: a Files-style folder for folders, a symbol otherwise.
private struct EntryIcon: View {
    let entry: FileEntry
    let symbolFont: Font

    var body: some View {
        if entry.isDirectory || entry.type == .shareLink {
            FolderIcon(name: entry.name, isShared: entry.type == .shareLink)
        } else {
            let icon = iconInfo(for: entry)
            Image(systemName: icon.symbol)
                .font(symbolFont)
                .foregroundStyle(icon.style)
        }
    }
}

/// One row in the list view: icon, name, then date and size or item count underneath, like the
/// Files app.
struct FileEntryLabel: View {
    let entry: FileEntry
    var itemCount: Int?

    var body: some View {
        HStack(spacing: 12) {
            EntryIcon(entry: entry, symbolFont: .title)
                .frame(width: 40, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle(for: entry, itemCount: itemCount))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .contentShape(.rect)
    }
}

/// One cell in the icon view. Images get a real thumbnail, folders the Files-style folder, and
/// everything else its kind's symbol.
struct FileEntryTile: View {
    let entry: FileEntry
    let thumbnailURL: URL?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                if entry.isDirectory || entry.type == .shareLink {
                    EntryIcon(entry: entry, symbolFont: .largeTitle)
                        .padding(6)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.fill.quaternary)
                    if let thumbnailURL {
                        RemoteImage(url: thumbnailURL)
                            .clipShape(.rect(cornerRadius: 12))
                    } else {
                        EntryIcon(entry: entry, symbolFont: .largeTitle)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)

            Text(entry.name)
                .font(.caption)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// A share link: what it points to, its URL, its options, and copy/share/delete actions.
struct ShareLinkRow: View {
    let share: TPCore.ShareLink
    let title: String
    let onDelete: () -> Void

    @State private var didCopy = false

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if share.isFile {
                    Image(systemName: "doc.fill")
                        .font(.title)
                        .foregroundStyle(.tint)
                } else {
                    FolderIcon(name: title)
                }
            }
            .frame(width: 40, height: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(share.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if share.hasPassword || share.editable || share.isPublic {
                    HStack(spacing: 4) {
                        if share.hasPassword { StatusBadge("Password") }
                        if share.editable { StatusBadge("Editable") }
                        if share.isPublic { StatusBadge("Public", tint: .blue) }
                    }
                }
            }
            Spacer(minLength: 0)
            Button {
                copyToClipboard(share.url)
                withAnimation { didCopy = true }
            } label: {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(didCopy ? "Copied" : "Copy Link")
            .task(id: didCopy) {
                guard didCopy else { return }
                try? await Task.sleep(for: .seconds(2))
                withAnimation { didCopy = false }
            }
        }
        .contextMenu {
            Button("Copy Link", systemImage: "doc.on.doc") { copyToClipboard(share.url) }
            if let url = URL(string: share.url) {
                SwiftUI.ShareLink(item: url) { Label("Share…", systemImage: "square.and.arrow.up") }
            }
            Divider()
            Button("Delete Link", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", action: onDelete)
                .tint(.red)
        }
    }
}
