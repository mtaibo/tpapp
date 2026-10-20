import SwiftUI
import TPCore
import TPUI

/// Picks the glyph pressed into a folder's icon, like Files' "Customize" for a folder: a live
/// preview of the folder on top, every icon grouped by category underneath, searchable by name.
/// Saving stores the web frontend's icon name, so the web shows the same icon.
struct FolderIconPicker: View {
    let entry: FileEntry
    let folder: StoreFolder
    let storeClient: StoreClient
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selection: String?
    @State private var search = ""
    @State private var isSaving = false
    @State private var error: String?

    init(entry: FileEntry, folder: StoreFolder, storeClient: StoreClient, onSaved: @escaping () -> Void) {
        self.entry = entry
        self.folder = folder
        self.storeClient = storeClient
        self.onSaved = onSaved
        // One-time seed from the folder's current icon; the picker owns the choice from here.
        _selection = State(initialValue: entry.iconName.flatMap { FolderIconCatalog.symbol(for: $0) == nil ? nil : $0 })
    }

    private var categories: [FolderIconCatalog.Category] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return FolderIconCatalog.categories }
        let matches = FolderIconCatalog.categories
            .flatMap(\.icons)
            .filter { FolderIconCatalog.label(for: $0).localizedStandardContains(query) }
        return matches.isEmpty ? [] : [FolderIconCatalog.Category(label: "Results", icons: matches)]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    FolderIcon(name: entry.name, iconName: selection)
                        .frame(width: 110)
                        .animation(.snappy, value: selection)
                    Text(entry.name)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.vertical, 20)

                LazyVStack(alignment: .leading, spacing: 20, pinnedViews: []) {
                    if search.isEmpty {
                        iconGrid(label: nil, icons: [nil])
                    }
                    ForEach(categories) { category in
                        iconGrid(label: category.label, icons: category.icons)
                    }
                    if categories.isEmpty {
                        ContentUnavailableView.search(text: search)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Folder Icon")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $search, prompt: "Search Icons")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Done", role: .confirm) {
                            Task { await save() }
                        }
                    }
                }
            }
            .errorAlert($error)
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
    }

    /// `nil` in `icons` is the "no icon" cell that puts the folder back to its default look.
    private func iconGrid(label: String?, icons: [String?]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let label {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 10)], spacing: 10) {
                ForEach(icons, id: \.self) { icon in
                    cell(for: icon)
                }
            }
        }
    }

    private func cell(for icon: String?) -> some View {
        let isSelected = selection == icon
        return Button {
            selection = icon
        } label: {
            Image(systemName: icon.flatMap(FolderIconCatalog.symbol(for:)) ?? "nosign")
                .font(.title3)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .frame(width: 48, height: 48)
                .background(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icon.map(FolderIconCatalog.label(for:)) ?? "No Icon")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func save() async {
        guard selection != entry.iconName else {
            dismiss()
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await storeClient.setFolderIcon(path: folder.entryPath(entry.name), location: folder.location, iconName: selection)
            onSaved()
            dismiss()
        } catch {
            self.error = apiErrorMessage(error)
        }
    }
}
