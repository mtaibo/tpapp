import SwiftUI
import TPCore

public struct SharedView: View {
    private static let rootPath = "shared"

    let storeClient: StoreClient

    @State private var path = SharedView.rootPath
    @State private var history: [String] = [SharedView.rootPath]
    @State private var historyIndex = 0

    @State private var entries: [FileEntry] = []
    @State private var shares: [TPCore.ShareLink] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var copiedToken: String?

    public init(storeClient: StoreClient) {
        self.storeClient = storeClient
    }

    public var body: some View {
        ZStack {
            TPStoreTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                toolbar
                content
            }
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 540)
        #endif
        .task { await load() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                navigationPill
                breadcrumb
                Spacer()
                Button {
                    Task { await load() }
                } label: {
                    toolbarIcon("arrow.clockwise")
                }
                .buttonStyle(.plain)
                .glassEffect(.regular, in: .circle)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }

    private var navigationPill: some View {
        NavigationPill(
            canGoBack: historyIndex > 0,
            canGoForward: historyIndex < history.count - 1,
            onBack: goBack,
            onForward: goForward
        )
    }

    private var breadcrumb: some View {
        let segments = path.split(separator: "/").map(String.init)
        let relativeSegments = Array(segments.dropFirst(1))
        return HStack(spacing: 4) {
            breadcrumbButton(title: "Shared", targetPath: Self.rootPath)
            ForEach(Array(relativeSegments.enumerated()), id: \.offset) { index, segment in
                Text("\u{203A}")
                    .font(.system(size: 13.6))
                    .foregroundStyle(TPStoreTheme.breadcrumbSeparator)
                breadcrumbButton(title: segment, targetPath: segments[0...(index + 1)].joined(separator: "/"))
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
        } else if shares.isEmpty && entries.isEmpty {
            Spacer()
            Text(path == Self.rootPath ? "No shared folders or links yet" : "Empty folder")
                .font(.system(size: 14))
                .foregroundStyle(TPStoreTheme.textMuted)
            Spacer()
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    if !shares.isEmpty {
                        sectionHeader("Links")
                        ForEach(shares) { share in
                            shareRow(share)
                            Rectangle().fill(TPStoreTheme.divider).frame(height: 0.5)
                        }
                    }
                    if !entries.isEmpty {
                        sectionHeader("Folders")
                        ForEach(entries) { entry in
                            entryRow(entry)
                            Rectangle().fill(TPStoreTheme.divider).frame(height: 0.5)
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
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)

                Button {
                    Task { await delete(share) }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(TPStoreTheme.danger)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
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
            let listing = try await storeClient.listDirectory(path: path, location: .external)
            entries = listing.entries.sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
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
}
