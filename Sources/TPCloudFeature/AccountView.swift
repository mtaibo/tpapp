import SwiftUI
import TPCore

public struct AccountView: View {
    @ObservedObject var session: AuthSession
    let accountClient: CloudAccountClient

    @State private var profile: AccountProfile?
    @State private var isLoading = true
    @State private var loadError: String?

    @State private var displayNameDraft = ""
    @State private var isSavingName = false
    @State private var nameSaveError: String?

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isSavingPassword = false
    @State private var passwordMessage: (text: String, isError: Bool)?

    @State private var totpSetup: CloudAccountClient.TOTPSetup?
    @State private var totpCode = ""
    @State private var isTOTPBusy = false
    @State private var totpMessage: (text: String, isError: Bool)?

    private let errorColor = Color(red: 0.988, green: 0.647, blue: 0.647)
    private let successColor = Color(red: 0.525, green: 0.937, blue: 0.675)

    public init(session: AuthSession, accountClient: CloudAccountClient) {
        self.session = session
        self.accountClient = accountClient
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if let profile {
                        profileSection(profile)
                        passwordSection(profile)
                        totpSection(profile)
                        sessionsSection(profile)
                    } else if let loadError {
                        Text(loadError).foregroundStyle(errorColor)
                    } else {
                        ProgressView().tint(.white)
                    }
                }
                .padding(24)
                .frame(maxWidth: 480)
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 600)
        #endif
        .task { await loadProfile() }
    }

    private var header: some View {
        HStack {
            Text(profile?.email ?? "")
                .font(.system(size: 13))
                .foregroundStyle(Color(white: 0.5))
            Spacer()
            Button {
                Task { await session.signOut() }
            } label: {
                Text("Log out")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glass)
        }
    }

    // MARK: - Profile

    private func profileSection(_ profile: AccountProfile) -> some View {
        sectionCard(title: "Profile") {
            VStack(alignment: .leading, spacing: 14) {
                infoRow(label: "Email", value: profile.email)

                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Name")
                    HStack(spacing: 8) {
                        glassTextField(label: "Name") {
                            TextField("", text: $displayNameDraft)
                                .textContentType(.name)
                        }
                        if canSaveName(profile) {
                            Button {
                                Task { await saveDisplayName() }
                            } label: {
                                buttonLabel("Save", isLoading: isSavingName)
                            }
                            .buttonStyle(.glassProminent)
                            .tint(.white.opacity(0.18))
                            .disabled(isSavingName)
                        }
                    }
                }

                if let nameSaveError {
                    Text(nameSaveError).font(.system(size: 13)).foregroundStyle(errorColor)
                }
            }
        }
    }

    private func canSaveName(_ profile: AccountProfile) -> Bool {
        let trimmed = displayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != profile.displayName
    }

    // MARK: - Password

    private func passwordSection(_ profile: AccountProfile) -> some View {
        sectionCard(title: "Password") {
            VStack(alignment: .leading, spacing: 14) {
                infoRow(label: "Status", value: profile.hasPassword ? "Password set" : "No password (passkey only)")

                if profile.hasPassword {
                    VStack(alignment: .leading, spacing: 6) {
                        fieldLabel("Current password")
                        glassTextField(label: "Current password") {
                            SecureField("", text: $currentPassword)
                                .textContentType(.password)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("New password")
                    glassTextField(label: "New password") {
                        SecureField("", text: $newPassword)
                            .textContentType(.newPassword)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Confirm password")
                    glassTextField(label: "Confirm password") {
                        SecureField("", text: $confirmPassword)
                            .textContentType(.newPassword)
                    }
                }

                if let passwordMessage {
                    Text(passwordMessage.text)
                        .font(.system(size: 13))
                        .foregroundStyle(passwordMessage.isError ? errorColor : successColor)
                }

                Button {
                    Task { await changePassword(hasPassword: profile.hasPassword) }
                } label: {
                    buttonLabel(profile.hasPassword ? "Change password" : "Set password", isLoading: isSavingPassword)
                }
                .buttonStyle(.glassProminent)
                .tint(.white.opacity(0.18))
                .disabled(
                    isSavingPassword
                        || newPassword.count < 8
                        || newPassword != confirmPassword
                        || (profile.hasPassword && currentPassword.isEmpty)
                )
            }
        }
    }

    // MARK: - TOTP

    private func totpSection(_ profile: AccountProfile) -> some View {
        sectionCard(title: "Two-factor authentication (TOTP)") {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Status").font(.system(size: 14)).foregroundStyle(Color(white: 0.45))
                    Spacer()
                    statusBadge(profile.totpEnabled ? "Enabled" : "Disabled", positive: profile.totpEnabled)
                }

                if profile.totpEnabled {
                    VStack(alignment: .leading, spacing: 6) {
                        fieldLabel("Current code")
                        glassTextField(label: "Current code") {
                            TextField("······", text: $totpCode)
                                .textContentType(.oneTimeCode)
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                        }
                    }
                    totpMessageView
                    Button {
                        Task { await disableTOTP() }
                    } label: {
                        buttonLabel("Disable 2FA", isLoading: isTOTPBusy)
                    }
                    .buttonStyle(.glass)
                    .tint(errorColor.opacity(0.3))
                    .disabled(totpCode.count != 6 || isTOTPBusy)
                } else if let totpSetup {
                    if let qr = QRCodeGenerator.image(for: totpSetup.otpauthUri) {
                        qr.interpolation(.none)
                            .resizable()
                            .frame(width: 160, height: 160)
                            .padding(8)
                            .glassEffect(.regular, in: .rect(cornerRadius: 14))
                    }
                    Text("Or enter the code manually: \(totpSetup.secret)")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(white: 0.5))
                    VStack(alignment: .leading, spacing: 6) {
                        fieldLabel("Confirmation code")
                        glassTextField(label: "Confirmation code") {
                            TextField("······", text: $totpCode)
                                .textContentType(.oneTimeCode)
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                        }
                    }
                    totpMessageView
                    Button {
                        Task { await completeTOTPSetup() }
                    } label: {
                        buttonLabel("Confirm", isLoading: isTOTPBusy)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.white.opacity(0.18))
                    .disabled(totpCode.count != 6 || isTOTPBusy)
                } else {
                    Button {
                        Task { await beginTOTPSetup() }
                    } label: {
                        buttonLabel("Set up 2FA", isLoading: isTOTPBusy)
                    }
                    .buttonStyle(.glass)
                }
            }
        }
    }

    @ViewBuilder
    private var totpMessageView: some View {
        if let totpMessage {
            Text(totpMessage.text)
                .font(.system(size: 13))
                .foregroundStyle(totpMessage.isError ? errorColor : successColor)
        }
    }

    // MARK: - Sessions

    private func sessionsSection(_ profile: AccountProfile) -> some View {
        sectionCard(title: "Active sessions") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(profile.sessions.enumerated()), id: \.element.id) { index, session in
                    sessionRow(session)
                    if index < profile.sessions.count - 1 {
                        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                    }
                }
            }
        }
    }

    private func sessionRow(_ session: AccountSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(session.deviceInfo ?? "Unknown device")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                if session.current {
                    statusBadge("Current", positive: true)
                }
                statusBadge(session.authMethod, positive: false)
                Spacer()
                if !session.current {
                    Button {
                        Task { await revokeSession(session.id) }
                    } label: {
                        Text("Revoke")
                            .font(.system(size: 13))
                            .foregroundStyle(errorColor)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(sessionSubtitle(session))
                .font(.system(size: 12))
                .foregroundStyle(Color(white: 0.45))
        }
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
        let plain = ISO8601DateFormatter()
        guard let date = withFractional.date(from: iso) ?? plain.date(from: iso) else { return nil }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .short
        return relative.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Shared building blocks

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Color(white: 0.5))
            content()
        }
        .padding(20)
        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 18))
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Color(white: 0.45))
            Spacer()
            Text(value).foregroundStyle(.white)
        }
        .font(.system(size: 14))
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .medium))
            .tracking(0.6)
            .foregroundStyle(Color(white: 0.45))
    }

    private func glassTextField<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        content()
            .textFieldStyle(.plain)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .rect(cornerRadius: 10))
            // `fieldLabel` above is a styled caption, not an accessible one — VoiceOver
            // doesn't associate sibling text with a field on its own.
            .accessibilityLabel(label)
    }

    private func statusBadge(_ text: String, positive: Bool) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(positive ? successColor : Color(white: 0.6))
            .glassEffect(.regular, in: .capsule)
    }

    private func buttonLabel(_ title: String, isLoading: Bool) -> some View {
        HStack(spacing: 8) {
            if isLoading {
                ProgressView().controlSize(.small).tint(.white)
            }
            Text(title).font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func loadProfile() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let fetched = try await accountClient.profile()
            profile = fetched
            displayNameDraft = fetched.displayName
        } catch {
            loadError = apiErrorMessage(error)
        }
    }

    private func saveDisplayName() async {
        isSavingName = true
        nameSaveError = nil
        defer { isSavingName = false }
        do {
            try await accountClient.updateDisplayName(displayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines))
            await loadProfile()
        } catch {
            nameSaveError = apiErrorMessage(error)
        }
    }

    private func changePassword(hasPassword: Bool) async {
        isSavingPassword = true
        passwordMessage = nil
        defer { isSavingPassword = false }
        do {
            try await accountClient.changePassword(
                currentPassword: hasPassword ? currentPassword : nil,
                newPassword: newPassword
            )
            currentPassword = ""
            newPassword = ""
            confirmPassword = ""
            passwordMessage = ("Password updated", false)
            await loadProfile()
        } catch {
            passwordMessage = (apiErrorMessage(error), true)
        }
    }

    private func beginTOTPSetup() async {
        isTOTPBusy = true
        totpMessage = nil
        defer { isTOTPBusy = false }
        do {
            totpSetup = try await accountClient.beginTOTPSetup()
        } catch {
            totpMessage = (apiErrorMessage(error), true)
        }
    }

    private func completeTOTPSetup() async {
        isTOTPBusy = true
        totpMessage = nil
        defer { isTOTPBusy = false }
        do {
            try await accountClient.completeTOTPSetup(code: totpCode)
            totpCode = ""
            totpSetup = nil
            await loadProfile()
        } catch {
            totpMessage = (apiErrorMessage(error), true)
        }
    }

    private func disableTOTP() async {
        isTOTPBusy = true
        totpMessage = nil
        defer { isTOTPBusy = false }
        do {
            try await accountClient.disableTOTP(code: totpCode)
            totpCode = ""
            await loadProfile()
        } catch {
            totpMessage = (apiErrorMessage(error), true)
        }
    }

    private func revokeSession(_ id: String) async {
        do {
            try await accountClient.revokeSession(id)
            await loadProfile()
        } catch {
            loadError = apiErrorMessage(error)
        }
    }
}
