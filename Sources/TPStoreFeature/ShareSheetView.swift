import SwiftUI
import TPCore
import TPUI

/// Creates and manages the share links for one file or folder. A plain `Form` in a sheet with
/// detents — previously this drew its own 320pt card and dimming backdrop *inside* the system
/// sheet, so iOS showed two stacked modals.
struct ShareSheetView: View {
    let entry: FileEntry
    let folder: StoreFolder
    let storeClient: StoreClient
    /// Called after a link is created or deleted, so a list showing links can refresh.
    let onChange: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var shares: [TPCore.ShareLink] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    @State private var usesCustomSlug = false
    @State private var slug = ""
    @State private var password = ""
    @State private var editable = false
    @State private var isPublic = false
    @State private var isCreating = false
    @State private var sharePendingDelete: TPCore.ShareLink?

    private var targetPath: String { folder.entryPath(entry.name) }

    private var canCreate: Bool {
        !isCreating && (!usesCustomSlug || !slug.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Link", selection: $usesCustomSlug) {
                        Text("Random").tag(false)
                        Text("Custom").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                    if usesCustomSlug {
                        TextField("Custom slug", text: $slug, prompt: Text("my-link"))
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                    }
                    SecureField("Password (optional)", text: $password)
                        .textContentType(.newPassword)
                    Toggle("Allow Edits", isOn: $editable)
                    Toggle("List Publicly", isOn: $isPublic)
                } header: {
                    Text("New Link")
                }

                Section {
                    Button {
                        Task { await createShare() }
                    } label: {
                        HStack {
                            Text("Create Link")
                            Spacer()
                            if isCreating { ProgressView() }
                        }
                    }
                    .disabled(!canCreate)
                }

                Section("Active Links") {
                    if isLoading {
                        ProgressView()
                    } else if shares.isEmpty {
                        Text("No links yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(shares) { share in
                            ShareLinkRow(share: share, title: share.url.split(separator: "/").last.map(String.init) ?? share.url) {
                                sharePendingDelete = share
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Share \(entry.name)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
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
            .errorAlert($errorMessage)
        }
        .presentationDetents([.medium, .large])
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #endif
        .task { await loadShares() }
    }

    private func loadShares() async {
        defer { isLoading = false }
        do {
            shares = try await storeClient.shares(path: targetPath)
        } catch {
            errorMessage = apiErrorMessage(error)
        }
    }

    private func createShare() async {
        isCreating = true
        defer { isCreating = false }
        do {
            _ = try await storeClient.createShare(
                location: folder.location,
                path: targetPath,
                hidden: !usesCustomSlug,
                slug: usesCustomSlug ? slug.trimmingCharacters(in: .whitespaces) : nil,
                password: password.isEmpty ? nil : password,
                editable: editable,
                isPublic: isPublic
            )
            slug = ""
            password = ""
            editable = false
            isPublic = false
            await loadShares()
            onChange()
        } catch {
            errorMessage = apiErrorMessage(error)
        }
    }

    private func deleteShare(_ share: TPCore.ShareLink) async {
        do {
            try await storeClient.deleteShare(share.token)
            withAnimation { shares.removeAll { $0.token == share.token } }
            onChange()
        } catch {
            errorMessage = apiErrorMessage(error)
        }
    }
}
