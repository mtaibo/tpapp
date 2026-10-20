import CoreTransferable
import SwiftUI
import TPCore
import UniformTypeIdentifiers

extension UTType {
    /// A file or folder dragged inside the app; declared in the app's Info.plist.
    static let storeItem = UTType(exportedAs: "com.migueltaibo.tpapp.store-item", conformingTo: .data)
}

/// What a drag carries inside the app: enough to move the item with `/api/files/move`.
struct StoreDragItem: Codable, Transferable {
    let location: StoreLocation
    let path: String
    let isDirectory: Bool

    var parentPath: String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<slash])
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .storeItem)
    }
}

enum StoreDragging {
    /// The drag for a file or folder. Inside the app it carries a `StoreDragItem`, so dropping on
    /// a folder moves it. Other apps (WhatsApp, Mail, Files…) get the real file instead, downloaded
    /// only once they accept the drop — folders go out as a zip.
    static func itemProvider(for entry: FileEntry, in folder: StoreFolder, storeClient: StoreClient) -> NSItemProvider {
        let provider = NSItemProvider()
        let path = folder.entryPath(entry.name)
        let location = folder.location

        let type: UTType
        let filename: String
        if entry.isDirectory {
            type = .zip
            filename = "\(entry.name).zip"
        } else {
            type = UTType(filenameExtension: (entry.name as NSString).pathExtension) ?? .data
            filename = entry.name
        }
        provider.suggestedName = filename
        provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { completion in
            Task {
                do {
                    let data = entry.isDirectory
                        ? try await storeClient.downloadZip(path: path, location: location)
                        : try await storeClient.download(path: path, location: location)
                    completion(try writeTemporaryFile(data, named: filename), false, nil)
                } catch {
                    completion(nil, false, error)
                }
            }
            return nil
        }

        provider.register(StoreDragItem(location: location, path: path, isDirectory: entry.isDirectory))
        return provider
    }

    static func writeTemporaryFile(_ data: Data, named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }
}

/// Makes a folder (a row, a tile, or a folder's own background) accept dragged store items,
/// which are moved into it, and spring-load: holding a drag over it for a moment opens it, like
/// the Files app.
///
/// Must not sit inside a `List`: on iOS the list's collection view takes every drop for itself
/// and per-row drop destinations never fire, which is why the folder screens use a lazy stack.
struct FolderDropTarget: ViewModifier {
    let folder: StoreFolder
    let cache: StoreDirectoryCache
    /// Opens the folder when a drag lingers over it; nil for the folder you're already in.
    let springLoad: (() -> Void)?
    let highlightShape: AnyShape
    let onError: (String) -> Void

    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            // On top, not behind: rows have an opaque background of their own (for swipe actions).
            .overlay {
                if isTargeted, springLoad != nil {
                    highlightShape.fill(.tint.opacity(0.2))
                        .allowsHitTesting(false)
                }
            }
            .dropDestination(for: StoreDragItem.self) { items, _ in
                isTargeted = false
                let movable = items.filter { cache.canMove($0, into: folder) }
                guard !movable.isEmpty else { return }
                Task {
                    for item in movable {
                        do {
                            try await cache.move(item, into: folder)
                        } catch {
                            onError(apiErrorMessage(error))
                        }
                    }
                }
            }
            .onDropSessionUpdated { session in
                switch session.phase {
                case .entering, .active: if !isTargeted { isTargeted = true }
                case .exiting, .ended, .dataTransferCompleted: if isTargeted { isTargeted = false }
                @unknown default: isTargeted = false
                }
            }
            .sensoryFeedback(.selection, trigger: isTargeted) { _, new in new && springLoad != nil }
            .task(id: isTargeted) {
                guard isTargeted, let springLoad else { return }
                try? await Task.sleep(for: .seconds(0.9))
                guard !Task.isCancelled, isTargeted else { return }
                isTargeted = false
                springLoad()
            }
    }
}

extension View {
    func folderDropTarget(
        _ folder: StoreFolder,
        cache: StoreDirectoryCache,
        highlightShape: AnyShape = AnyShape(Rectangle()),
        springLoad: (() -> Void)?,
        onError: @escaping (String) -> Void
    ) -> some View {
        modifier(FolderDropTarget(folder: folder, cache: cache, springLoad: springLoad, highlightShape: highlightShape, onError: onError))
    }
}
