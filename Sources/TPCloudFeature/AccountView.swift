import SwiftUI
import TPCore
import TPUI

/// Profile, password, two-factor and active sessions, as a standard grouped form. Pushed from the
/// More tab, so it has no background or sign-out button of its own anymore.
public struct AccountView: View {
    let accountClient: CloudAccountClient

    @State private var profile: AccountProfile?
    @State private var loadError: String?
    @State private var errorMessage: String?

    @State private var displayNameDraft = ""
    @State private var isSavingName = false

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isSavingPassword = false
    @State private var passwordUpdated = false

    @State private var totpSetup: CloudAccountClient.TOTPSetup?
    @State private var totpCode = ""
    @State private var isTOTPBusy = false

    public init(accountClient: CloudAccountClient) {
        self.accountClient = accountClient
    }

    public var body: some View {
        Form {
            if let profile {
                profileSection(profile)
                passwordSection(profile)
                totpSection(profile)
                sessionsSection(profile)
            } else if let loadError {
                ContentUnavailableView {
                    Label("Couldn't Load Account", systemImage: "person.crop.circle.badge.exclamationmark")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Try Again") { Task { await loadProfile() } }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Account")
        .task { await loadProfile() }
        .refreshable { await loadProfile() }
        .errorAlert($errorMessage)
    }

    // MARK: - Profile

    private func profileSection(_ profile: AccountProfile) -> some View {
        Section("Profile") {
            LabeledContent("Email", value: profile.email)
            HStack {
                TextField("Name", text: $displayNameDraft)
                    .textContentType(.name)
                    .onSubmit { Task { await saveDisplayName() } }
                if canSaveName(profile) {
                    Button {
                        Task { await saveDisplayName() }
                    } label: {
                        if isSavingName { ProgressView() } else { Text("Save") }
                    }
                    .buttonStyle(.borderless)
                    .disabled(isSavingName)
                }
            }
            if profile.isAdmin {
                LabeledContent("Role") { StatusBadge("Admin", tint: .blue) }
            }
        }
    }

    private func canSaveName(_ profile: AccountProfile) -> Bool {
        let trimmed = displayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != profile.displayName
    }

    // MARK: - Password

    private func passwordSection(_ profile: AccountProfile) -> some View {
        Section {
            if profile.hasPassword {
                SecureField("Current Password", text: $currentPassword)
                    .textContentType(.password)
            }
            SecureField("New Password", text: $newPassword)
                .textContentType(.newPassword)
            SecureField("Confirm Password", text: $confirmPassword)
                .textContentType(.newPassword)
            Button {
                Task { await changePassword(hasPassword: profile.hasPassword) }
            } label: {
                HStack {
                    Text(profile.hasPassword ? "Change Password" : "Set Password")
                    Spacer()
                    if isSavingPassword { ProgressView() }
                }
            }
            .disabled(
                isSavingPassword
                    || newPassword.count < 8
                    || newPassword != confirmPassword
                    || (profile.hasPassword && currentPassword.isEmpty)
            )
        } header: {
            Text("Password")
        } footer: {
            if passwordUpdated {
                Label("Password updated", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if !newPassword.isEmpty, newPassword.count < 8 {
                Text("Use at least 8 characters.")
            } else if !confirmPassword.isEmpty, newPassword != confirmPassword {
                Text("The passwords don't match.")
            } else if !profile.hasPassword {
                Text("This account signs in with a passkey only.")
            }
        }
    }

    // MARK: - Two-factor

    @ViewBuilder
    private func totpSection(_ profile: AccountProfile) -> some View {
        Section {
            LabeledContent("Status") {
                StatusBadge(profile.totpEnabled ? "On" : "Off", tint: profile.totpEnabled ? .green : .secondary)
            }

            if profile.totpEnabled {
                codeField("Current Code")
                Button(role: .destructive) {
                    Task { await disableTOTP() }
                } label: {
                    HStack {
                        Text("Turn Off Two-Factor")
                        Spacer()
                        if isTOTPBusy { ProgressView() }
                    }
                }
                .disabled(totpCode.count != 6 || isTOTPBusy)
            } else if let totpSetup {
                if let qr = QRCodeGenerator.image(for: totpSetup.otpauthUri) {
                    qr.interpolation(.none)
                        .resizable()
                        .frame(width: 180, height: 180)
                        .padding(10)
                        .background(.white, in: .rect(cornerRadius: 12))
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Setup QR code")
                }
                LabeledContent("Setup Key") {
                    Text(totpSetup.secret)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
                Button("Copy Setup Key", systemImage: "doc.on.doc") { copyToClipboard(totpSetup.secret) }
                codeField("Code from Your App")
                Button {
                    Task { await completeTOTPSetup() }
                } label: {
                    HStack {
                        Text("Confirm")
                        Spacer()
                        if isTOTPBusy { ProgressView() }
                    }
                }
                .disabled(totpCode.count != 6 || isTOTPBusy)
            } else {
                Button {
                    Task { await beginTOTPSetup() }
                } label: {
                    HStack {
                        Text("Set Up Two-Factor")
                        Spacer()
                        if isTOTPBusy { ProgressView() }
                    }
                }
                .disabled(isTOTPBusy)
            }
        } header: {
            Text("Two-Factor Authentication")
        } footer: {
            if totpSetup != nil, !profile.totpEnabled {
                Text("Scan the code with an authenticator app, or enter the setup key by hand, then type the 6-digit code it shows.")
            }
        }
    }

    private func codeField(_ title: String) -> some View {
        TextField(title, text: $totpCode)
            .textContentType(.oneTimeCode)
            .monospacedDigit()
            #if os(iOS)
            .keyboardType(.numberPad)
            #endif
            .onChange(of: totpCode) { _, newValue in
                let digits = String(newValue.filter(\.isNumber).prefix(6))
                if digits != newValue { totpCode = digits }
            }
    }

    // MARK: - Sessions

    private func sessionsSection(_ profile: AccountProfile) -> some View {
        Section("Active Sessions") {
            ForEach(profile.sessions) { session in
                sessionRow(session)
                    .swipeActions {
                        if !session.current {
                            Button("Revoke", role: .destructive) {
                                Task { await revokeSession(session.id) }
                            }
                        }
                    }
                    .contextMenu {
                        if !session.current {
                            Button("Revoke", systemImage: "xmark.circle", role: .destructive) {
                                Task { await revokeSession(session.id) }
                            }
                        }
                    }
            }
        }
    }

    private func sessionRow(_ session: AccountSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(session.deviceInfo ?? "Unknown device")
                    .lineLimit(1)
                if session.current {
                    StatusBadge("This device", tint: .green)
                }
                Spacer(minLength: 0)
                StatusBadge(session.authMethod)
            }
            Text(sessionSubtitle(session))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func sessionSubtitle(_ session: AccountSession) -> String {
        var parts: [String] = []
        if let location = session.location { parts.append(location) }
        if let ip = session.ipAddress { parts.append(ip) }
        if let started = relativeDate(session.createdAt) { parts.append("Started \(started)") }
        if let expires = relativeDate(session.expiresAt) { parts.append("Expires \(expires)") }
        return parts.joined(separator: " · ")
    }

    private func relativeDate(_ iso: String) -> String? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = withFractional.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return nil }
        return date.formatted(.relative(presentation: .named))
    }

    // MARK: - Actions

    private func loadProfile() async {
        do {
            let fetched = try await accountClient.profile()
            profile = fetched
            displayNameDraft = fetched.displayName
            loadError = nil
        } catch {
            if profile == nil {
                loadError = apiErrorMessage(error)
            } else {
                errorMessage = apiErrorMessage(error)
            }
        }
    }

    private func saveDisplayName() async {
        guard let profile, canSaveName(profile) else { return }
        isSavingName = true
        defer { isSavingName = false }
        do {
            try await accountClient.updateDisplayName(displayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines))
            await loadProfile()
        } catch {
            errorMessage = apiErrorMessage(error)
        }
    }

    private func changePassword(hasPassword: Bool) async {
        isSavingPassword = true
        passwordUpdated = false
        defer { isSavingPassword = false }
        do {
            try await accountClient.changePassword(
                currentPassword: hasPassword ? currentPassword : nil,
                newPassword: newPassword
            )
            currentPassword = ""
            newPassword = ""
            confirmPassword = ""
            passwordUpdated = true
            await loadProfile()
        } catch {
            errorMessage = apiErrorMessage(error)
        }
    }

    private func beginTOTPSetup() async {
        isTOTPBusy = true
        defer { isTOTPBusy = false }
        do {
            totpCode = ""
            totpSetup = try await accountClient.beginTOTPSetup()
        } catch {
            errorMessage = apiErrorMessage(error)
        }
    }

    private func completeTOTPSetup() async {
        isTOTPBusy = true
        defer { isTOTPBusy = false }
        do {
            try await accountClient.completeTOTPSetup(code: totpCode)
            totpCode = ""
            totpSetup = nil
            await loadProfile()
        } catch {
            errorMessage = apiErrorMessage(error)
        }
    }

    private func disableTOTP() async {
        isTOTPBusy = true
        defer { isTOTPBusy = false }
        do {
            try await accountClient.disableTOTP(code: totpCode)
            totpCode = ""
            await loadProfile()
        } catch {
            errorMessage = apiErrorMessage(error)
        }
    }

    private func revokeSession(_ id: String) async {
        do {
            try await accountClient.revokeSession(id)
            await loadProfile()
        } catch {
            errorMessage = apiErrorMessage(error)
        }
    }
}
