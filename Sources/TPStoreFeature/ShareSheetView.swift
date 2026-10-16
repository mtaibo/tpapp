import SwiftUI
import TPCore

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ShareSheetView: View {
    let entry: FileEntry
    let parentPath: String
    let location: StoreLocation
    let storeClient: StoreClient

    @Environment(\.dismiss) private var dismiss

    @State private var shares: [TPCore.ShareLink] = []
    @State private var isLoading = true
    @State private var loadError: String?

    @State private var isHidden = true
    @State private var slug = ""
    @State private var password = ""
    @State private var editable = false
    @State private var isPublic = false
    @State private var isCreating = false
    @State private var createError: String?

    @State private var copiedToken: String?

    private var targetPath: String { parentPath.isEmpty ? entry.name : "\(parentPath)/\(entry.name)" }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider().overlay(Color.white.opacity(0.08))
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        createSection
                        existingSharesSection
                    }
                    .padding(20)
                }
            }
            .frame(width: 320)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(TPStoreTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(TPStoreTheme.modalBorder, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 480)
        #endif
        .task { await loadShares() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(TPStoreTheme.accentGray)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("Share").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Text(entry.name).font(.system(size: 11)).foregroundStyle(TPStoreTheme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(TPStoreTheme.textMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.init(top: 18, leading: 20, bottom: 14, trailing: 20))
    }

    // MARK: - Create

    private var createSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("New link")

            slugModeSelector

            if !isHidden {
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Custom slug")
                    glassTextField(label: "Custom slug") { TextField("my-link", text: $slug) }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Password (optional)")
                glassTextField(label: "Password") {
                    SecureField("", text: $password)
                        .textContentType(.newPassword)
                }
            }

            Toggle("Allow edits", isOn: $editable)
                .toggleStyle(.switch)
                .tint(TPStoreTheme.accentGray)
                .foregroundStyle(.white)
                .font(.system(size: 13))

            Toggle("List publicly", isOn: $isPublic)
                .toggleStyle(.switch)
                .tint(TPStoreTheme.accentGray)
                .foregroundStyle(.white)
                .font(.system(size: 13))

            if let createError {
                Text(createError).font(.system(size: 12)).foregroundStyle(TPStoreTheme.danger)
            }

            Button {
                Task { await createShare() }
            } label: {
                HStack(spacing: 8) {
                    if isCreating {
                        ProgressView().controlSize(.small).tint(.white)
                    }
                    Text("Create link").font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
            }
            .buttonStyle(.glassProminent)
            .tint(TPStoreTheme.accentGray.opacity(0.4))
            .disabled(isCreating || (!isHidden && slug.trimmingCharacters(in: .whitespaces).isEmpty))
        }
    }

    private var slugModeSelector: some View {
        HStack(spacing: 6) {
            slugModeOption(title: "Random", isSelected: isHidden) { isHidden = true }
            slugModeOption(title: "Custom", isSelected: !isHidden) { isHidden = false }
        }
    }

    private func slugModeOption(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(isSelected ? .white : TPStoreTheme.urlRowText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isSelected ? TPStoreTheme.accentGray.opacity(0.15) : Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(isSelected ? TPStoreTheme.accentGray.opacity(0.3) : Color.white.opacity(0.08), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Existing

    @ViewBuilder
    private var existingSharesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Active links")
            if isLoading {
                ProgressView().tint(.white)
            } else if let loadError {
                Text(loadError).font(.system(size: 12)).foregroundStyle(TPStoreTheme.danger)
            } else if shares.isEmpty {
                Text("No links yet").font(.system(size: 12)).foregroundStyle(TPStoreTheme.textMuted)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(shares.enumerated()), id: \.element.id) { index, share in
                        shareRow(share)
                        if index < shares.count - 1 {
                            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
                        }
                    }
                }
            }
        }
    }

    private func shareRow(_ share: TPCore.ShareLink) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(share.url)
                    .font(.system(size: 12.8))
                    .foregroundStyle(TPStoreTheme.urlRowText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    copyToClipboard(share.url)
                    copiedToken = share.token
                } label: {
                    Image(systemName: copiedToken == share.token ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(copiedToken == share.token ? TPStoreTheme.success : TPStoreTheme.copyIdle)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy link")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(TPStoreTheme.urlRowBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(TPStoreTheme.urlRowBorder, lineWidth: 0.5)
            )

            HStack(spacing: 6) {
                if share.hasPassword { badge("Password") }
                if share.editable { badge("Editable") }
                if share.isPublic { badge("Public") }
                Spacer()
                Button {
                    Task { await deleteShare(share) }
                } label: {
                    Text("Delete")
                        .font(.system(size: 11.5))
                        .foregroundStyle(TPStoreTheme.danger)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
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

    // MARK: - Shared building blocks

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11.2, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(TPStoreTheme.textMuted)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .medium))
            .tracking(0.5)
            .foregroundStyle(TPStoreTheme.textMuted)
    }

    private func glassTextField<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        content()
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(TPStoreTheme.urlRowBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(TPStoreTheme.urlRowBorder, lineWidth: 0.5)
            )
            // `fieldLabel` above is a styled caption, not an accessible one.
            .accessibilityLabel(label)
    }

    // MARK: - Actions

    private func loadShares() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            shares = try await storeClient.shares(path: targetPath)
        } catch {
            loadError = apiErrorMessage(error)
        }
    }

    private func createShare() async {
        isCreating = true
        createError = nil
        defer { isCreating = false }
        do {
            _ = try await storeClient.createShare(
                location: location,
                path: targetPath,
                hidden: isHidden,
                slug: isHidden ? nil : slug.trimmingCharacters(in: .whitespaces),
                password: password.isEmpty ? nil : password,
                editable: editable,
                isPublic: isPublic
            )
            slug = ""
            password = ""
            editable = false
            isPublic = false
            await loadShares()
        } catch {
            createError = apiErrorMessage(error)
        }
    }

    private func deleteShare(_ share: TPCore.ShareLink) async {
        do {
            try await storeClient.deleteShare(share.token)
            await loadShares()
        } catch {
            loadError = apiErrorMessage(error)
        }
    }
}

func copyToClipboard(_ string: String) {
    #if os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
    #else
    UIPasteboard.general.string = string
    #endif
}
