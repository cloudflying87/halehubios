import SwiftUI

struct MainTabView: View {
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

            AccountView()
                .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
        }
    }
}
