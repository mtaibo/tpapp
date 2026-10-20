import CoreTransferable
import SwiftUI
import TPCore
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

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
        // Only runs once the other app accepts the drop. On iPhone that app is in front by then and
        // this one is in the background, where iOS freezes its networking within seconds — which
        // left the other app "loading" forever. So the download asks for background time, streams
        // to disk instead of memory, and reports real progress the other app can show and cancel.
        provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { completion in
            let progress = Progress(totalUnitCount: 100)
            Task {
                let activity = await BackgroundActivity.begin(named: "Drag \(filename)")
                defer { Task { await activity.end() } }
                do {
                    let downloaded = try await storeClient.downloadFile(
                        path: path,
                        location: location,
                        asZip: entry.isDirectory,
                        progress: progress
                    )
                    completion(try moveToTemporaryFile(downloaded, named: filename), false, nil)
                } catch {
                    completion(nil, false, error)
                }
            }
            return progress
        }

        provider.register(StoreDragItem(location: location, path: path, isDirectory: entry.isDirectory))
        return provider
    }

    /// Gives a downloaded file its real name, in a folder of its own so names never clash.
    static func moveToTemporaryFile(_ file: URL, named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try FileManager.default.moveItem(at: file, to: url)
        return url
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

/// Keeps the app running in the background (iOS grants about 30 seconds) while it finishes
/// something another app is waiting on. A no-op on macOS, where apps aren't suspended.
@MainActor
final class BackgroundActivity {
    #if os(iOS)
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    #endif

    static func begin(named name: String) -> BackgroundActivity {
        let activity = BackgroundActivity()
        #if os(iOS)
        activity.identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak activity] in
            activity?.end()
        }
        #endif
        return activity
    }

    func end() {
        #if os(iOS)
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
        #endif
    }
}
