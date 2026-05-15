import SwiftUI

@main
struct HaleHubIOSApp: App {
    @StateObject private var auth = AuthManager()
    @StateObject private var network = NetworkMonitor()

    var body: some Scene {
        WindowGroup {
            if auth.isAuthenticated {
                MainTabView()
                    .environmentObject(auth)
                    .environmentObject(network)
            } else {
                LoginView()
                    .environmentObject(auth)
            }
        }
    }
}
