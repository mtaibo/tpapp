import SwiftUI
import TPCore

struct RootView: View {
    @ObservedObject var session: AuthSession

    var body: some View {
        Group {
            switch session.state {
            case .signedOut, .totpRequired:
                LoginView(session: session)
            case .signedIn(let profile):
                signedIn(profile)
            }
        }
        .task { await session.restoreIfPossible() }
    }

    private func signedIn(_ profile: UserProfile) -> some View {
        VStack(spacing: 16) {
            Text("Signed in as \(profile.displayName)")
                .font(.title3)
            Text(profile.email)
                .foregroundStyle(.secondary)
            Button("Sign out") {
                Task { await session.signOut() }
            }
        }
        .padding()
    }
}

#Preview {
    RootView(session: AuthSession(baseURL: URL(string: "https://login.migueltaibo.com")!))
}
