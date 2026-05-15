import SwiftUI

@main
struct HaleHubIOSApp: App {
    @StateObject private var auth = AuthManager()

    var body: some Scene {
        WindowGroup {
            if auth.isAuthenticated {
                MainTabView()
                    .environmentObject(auth)
            } else {
                LoginView()
                    .environmentObject(auth)
            }
        }
    }
}
