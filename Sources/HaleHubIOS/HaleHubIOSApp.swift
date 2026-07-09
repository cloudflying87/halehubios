import SwiftUI

@main
struct HaleHubIOSApp: App {
    @StateObject private var auth = AuthManager()
    @StateObject private var network = NetworkMonitor()
    @StateObject private var deepLink = DeepLinkHandler()

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isAuthenticated {
                    if let user = auth.currentUser {
                        if user.isBabysitterOnly {
                            NavigationStack {
                                BabysitterPortalView()
                            }
                            .environmentObject(auth)
                        } else {
                            MainTabView()
                                .environmentObject(auth)
                                .environmentObject(network)
                                .environmentObject(deepLink)
                        }
                    } else {
                        // currentUser not yet loaded — fetch, but never dead-end here.
                        AccountLoadingGate()
                            .environmentObject(auth)
                    }
                } else {
                    LoginView()
                        .environmentObject(auth)
                }
            }
            // Any authenticated 401 → drop straight to the login screen (no error to read).
            .onReceive(NotificationCenter.default.publisher(for: .sessionExpired).receive(on: RunLoop.main)) { _ in
                if auth.isAuthenticated { auth.logout() }
            }
        }
        .handlesExternalEvents(matching: ["*"])
        .onChange(of: deepLink.pendingURL) { _, url in
            guard url != nil else { return }
            // Handled by MainTabView once authenticated
        }
    }
}

// MARK: - Account loading gate

/// Shown when the app has a token but hasn't loaded the user yet. Fetches
/// /auth/me/ and, crucially, offers Retry + Sign Out on failure so a bad
/// connection (or a stale token) can never trap the user on a spinner forever.
struct AccountLoadingGate: View {
    @EnvironmentObject var auth: AuthManager
    @State private var loading = true

    var body: some View {
        VStack(spacing: 18) {
            if loading {
                ProgressView("Loading…")
            } else {
                Image(systemName: "wifi.exclamationmark")
                    .font(.largeTitle).foregroundStyle(.secondary)
                Text("Couldn't load your account").font(.headline)
                Text("Check your connection and try again.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry") { Task { await attempt() } }
                    .buttonStyle(.borderedProminent)
                Button("Sign Out", role: .destructive) { auth.logout() }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await attempt() }
    }

    private func attempt() async {
        loading = true
        // One retry with a short backoff smooths over launch-time network flakiness.
        if await auth.fetchCurrentUser() { return }
        try? await Task.sleep(for: .seconds(1))
        _ = await auth.fetchCurrentUser()
        loading = false     // if currentUser loaded, this view is replaced anyway
    }
}

// MARK: - Deep Link Handler

@MainActor
class DeepLinkHandler: ObservableObject {
    @Published var pendingURL: URL?

    func handle(_ url: URL) {
        pendingURL = url
    }

    func consume() -> URL? {
        defer { pendingURL = nil }
        return pendingURL
    }
}
