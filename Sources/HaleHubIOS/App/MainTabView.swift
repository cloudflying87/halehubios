import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var network: NetworkMonitor
    @StateObject private var notifVM = NotificationsViewModel()

    var body: some View {
        TabView {
            NavigationStack {
                VehiclesListView()
            }
            .tabItem { Label("Vehicles", systemImage: "car.fill") }

            NavigationStack {
                MealsHubView()
            }
            .tabItem { Label("Meals", systemImage: "fork.knife") }

            NavigationStack {
                ShoppingListsView()
            }
            .tabItem { Label("Shopping", systemImage: "cart.fill") }

            AccountView(notifVM: notifVM)
                .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
                .badge(notifVM.unreadCount > 0 ? notifVM.unreadCount : 0)
        }
        .task {
            await notifVM.fetchUnreadCount(token: auth.accessToken ?? "")
        }
    }
}
