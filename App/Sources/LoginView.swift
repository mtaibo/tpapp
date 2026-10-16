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
        ZStack {
            Color.black
                .ignoresSafeArea()
                // The number pad has no return key and the email keyboard can cover the button, so
                // tapping anywhere outside the card is the way out of the keyboard.
                .contentShape(Rectangle())
                .onTapGesture { focusedField = nil }

            GlassEffectContainer {
                Group {
                    if case .totpRequired(let email) = session.state {
                        totpStep(email: email)
                    } else {
                        passwordStep
                    }
                }
                .padding(32)
                .frame(maxWidth: 380)
                .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 22))
            }
            .padding(24)
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 420)
        #endif
    }

    private var passwordStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Login")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)

            field(label: "MAIL", accessibilityLabel: "Email") {
                // `.username`, not `.emailAddress`: AutoFill only pairs a saved login with the
                // password field when the account field is marked as the username.
                TextField("", text: $email)
                    .textContentType(.username)
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
            }

            field(label: "PASSWORD") {
                SecureField("••••••••", text: $password)
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { Task { await login() } }
            }

            errorText

            Button {
                Task { await login() }
            } label: {
                buttonLabel("Log in")
            }
            .buttonStyle(.glassProminent)
            .tint(.white.opacity(0.18))
            .disabled(email.isEmpty || password.isEmpty || isLoading)
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

    private func totpStep(email: String) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Two-factor authentication")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)

            field(label: "CODE", accessibilityLabel: "Verification code") {
                TextField("······", text: $code)
                    .textContentType(.oneTimeCode)
                    .focused($focusedField, equals: .code)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
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
            }

            errorText

            HStack(spacing: 12) {
                Button {
                    errorMessage = nil
                    code = ""
                    session.cancelTOTP()
                } label: {
                    buttonLabel("Back")
                }
                .buttonStyle(.glass)

                Button {
                    Task { await verify() }
                } label: {
                    buttonLabel("Continue")
                }
                .buttonStyle(.glassProminent)
                .tint(.white.opacity(0.18))
                .disabled(code.count != 6 || isLoading)
            }
        }
        .onAppear { focusedField = .code }
    }

    @ViewBuilder
    private var errorText: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 0.988, green: 0.647, blue: 0.647))
        }
    }

    private func field<Content: View>(label: String, accessibilityLabel: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(Color(white: 0.45))
            content()
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .rect(cornerRadius: 10))
                // The caption above is a styled label, not an accessible one (VoiceOver
                // doesn't associate sibling text with a field on its own).
                .accessibilityLabel(accessibilityLabel ?? label)
        }
    }

    private func buttonLabel(_ title: String) -> some View {
        HStack(spacing: 8) {
            if isLoading {
                ProgressView().controlSize(.small).tint(.white)
            }
            Text(title)
                .font(.system(size: 15, weight: .semibold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
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
        }
    }
}

#Preview {
    LoginView(session: AuthSession(baseURL: URL(string: "https://login.migueltaibo.com")!))
}
