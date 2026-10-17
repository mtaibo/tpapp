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
    case .directory: return ("folder.fill", AnyShapeStyle(.tint))
    case .shareLink: return ("folder.fill.badge.person.crop", AnyShapeStyle(.tint))
    case .uploadPending: return ("icloud.and.arrow.up", AnyShapeStyle(.orange))
    case .file: return (FileKind(name: entry.name).systemImage, AnyShapeStyle(.secondary))
    }
}

private func subtitle(for entry: FileEntry) -> String {
    let modified = Date(timeIntervalSince1970: entry.modified).formatted(date: .abbreviated, time: .shortened)
    if entry.type == .uploadPending, let received = entry.bytesReceived {
        return "Uploading · \(formatBytes(received))"
    }
    if let size = entry.size, !entry.isDirectory {
        return "\(formatBytes(size)) · \(modified)"
    }
    return modified
}

/// One row in the list view: icon, name, then size and date underneath, like the Files app.
struct FileEntryLabel: View {
    let entry: FileEntry

    var body: some View {
        let icon = iconInfo(for: entry)
        HStack(spacing: 12) {
            Image(systemName: icon.symbol)
                .font(.title2)
                .foregroundStyle(icon.style)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle(for: entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
    }
}

/// One cell in the icon view. Images get a real thumbnail; everything else its kind's symbol.
struct FileEntryTile: View {
    let entry: FileEntry
    let thumbnailURL: URL?

    var body: some View {
        let icon = iconInfo(for: entry)
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.fill.quaternary)
                if let thumbnailURL {
                    RemoteImage(url: thumbnailURL)
                        .clipShape(.rect(cornerRadius: 12))
                } else {
                    Image(systemName: icon.symbol)
                        .font(.system(.largeTitle))
                        .foregroundStyle(icon.style)
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
            Image(systemName: share.isFile ? "doc.fill" : "folder.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 34)
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
