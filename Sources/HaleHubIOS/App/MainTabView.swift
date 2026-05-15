import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var network: NetworkMonitor

    var body: some View {
        TabView {
            NavigationStack {
                VehiclesListView()
            }
            .tabItem { Label("Vehicles", systemImage: "car.fill") }

            NavigationStack {
                MealPlanView()
            }
            .tabItem { Label("Meals", systemImage: "fork.knife") }

            NavigationStack {
                ShoppingListsView()
            }
            .tabItem { Label("Shopping", systemImage: "cart.fill") }

            AccountView()
                .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
        }
    }
}
