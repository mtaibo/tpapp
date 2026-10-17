import SwiftUI
import TPCore

struct LoginView: View {
    @ObservedObject var session: AuthSession

    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var errorMessage: String?
    @State private var isLoading = false

    private let credentialStore = LoginCredentialStore()

    private enum Field: Hashable { case email, password, code }
    @FocusState private var focusedField: Field?

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                Group {
                    if case .totpRequired = session.state {
                        totpStep
                    } else {
                        passwordStep
                    }
                }
                .frame(maxWidth: 380)
            }
            .padding(24)
            .padding(.top, 60)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        // The number pad has no return key and the email keyboard can cover the button, so
        // dragging the form (or tapping the button) is the way out of the keyboard.
        .scrollDismissesKeyboard(.interactively)
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 480)
        #endif
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("TPCloud")
                .font(.largeTitle.bold())
            Text(isTOTPStep ? "Enter the 6-digit code from your authenticator app." : "Sign in to your files, photos and home.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var isTOTPStep: Bool {
        if case .totpRequired = session.state { return true }
        return false
    }

    private var passwordStep: some View {
        VStack(spacing: 12) {
            // `.username`, not `.emailAddress`: AutoFill only pairs a saved login with the
            // password field when the account field is marked as the username.
            TextField("Email", text: $email)
                .textContentType(.username)
                .focused($focusedField, equals: .email)
                .submitLabel(.next)
                .onSubmit { focusedField = .password }
                #if os(iOS)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .loginFieldStyle()

            SecureField("Password", text: $password)
                .textContentType(.password)
                .focused($focusedField, equals: .password)
                .submitLabel(.go)
                .onSubmit { Task { await login() } }
                .loginFieldStyle()

            errorText

            primaryButton("Sign In") { await login() }
                .disabled(email.isEmpty || password.isEmpty || isLoading)
                .padding(.top, 8)
        }
        .onAppear {
            if email.isEmpty, password.isEmpty, let saved = credentialStore.load() {
                email = saved.email
                password = saved.password
            } else {
                focusedField = .email
            }
        }
    }

    private var totpStep: some View {
        VStack(spacing: 12) {
            TextField("Verification Code", text: $code)
                .textContentType(.oneTimeCode)
                .focused($focusedField, equals: .code)
                .font(.title2.monospacedDigit())
                .multilineTextAlignment(.center)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .loginFieldStyle()
                .onChange(of: code) { _, newValue in
                    let digits = String(newValue.filter(\.isNumber).prefix(6))
                    if digits != newValue {
                        code = digits // re-enters onChange with the cleaned value
                    } else if digits.count == 6, !isLoading {
                        // An AutoFilled code arrives all at once, and the number pad has no
                        // return key to submit it — so a full code submits itself.
                        Task { await verify() }
                    }
                }
                .onSubmit { Task { await verify() } }

            errorText

            primaryButton("Continue") { await verify() }
                .disabled(code.count != 6 || isLoading)
                .padding(.top, 8)

            Button("Use a Different Account") {
                errorMessage = nil
                code = ""
                session.cancelTOTP()
            }
            .buttonStyle(.borderless)
            .padding(.top, 4)
        }
        .onAppear { focusedField = .code }
    }

    @ViewBuilder
    private var errorText: some View {
        if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func primaryButton(_ title: String, action: @escaping () async -> Void) -> some View {
        Button {
            focusedField = nil
            Task { await action() }
        } label: {
            HStack(spacing: 8) {
                if isLoading { ProgressView() }
                Text(title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
    }

    private func login() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await session.login(email: email, password: password)
            // Reaching here means the server accepted the password, even if 2FA is still pending.
            credentialStore.save(email: email, password: password)
        } catch {
            errorMessage = apiErrorMessage(error)
        }
    }

    private func verify() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await session.verifyTOTP(code)
        } catch {
            errorMessage = apiErrorMessage(error)
            code = ""
        }
    }
}

private extension View {
    func loginFieldStyle() -> some View {
        textFieldStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.fill.tertiary, in: .rect(cornerRadius: 14))
    }
}

#Preview {
    LoginView(session: AuthSession(baseURL: URL(string: "https://login.migueltaibo.com")!))
}
