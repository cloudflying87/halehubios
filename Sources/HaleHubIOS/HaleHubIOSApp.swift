import SwiftUI

@main
struct HaleHubIOSApp: App {
    @StateObject private var auth = AuthManager()
    @StateObject private var network = NetworkMonitor()
    @StateObject private var deepLink = DeepLinkHandler()

    var body: some Scene {
        WindowGroup {
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
                    // currentUser not yet loaded from the server — fetch and wait
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .environmentObject(auth)
                        .task { await auth.fetchCurrentUser() }
                }
            } else {
                LoginView()
                    .environmentObject(auth)
            }
        }
        .handlesExternalEvents(matching: ["*"])
        .onChange(of: deepLink.pendingURL) { _, url in
            guard url != nil else { return }
            // Handled by MainTabView once authenticated
        }
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
