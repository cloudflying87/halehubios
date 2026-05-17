import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var network: NetworkMonitor
    @EnvironmentObject var deepLink: DeepLinkHandler
    @StateObject private var notifVM = NotificationsViewModel()

    @State private var selectedTab = 0
    @State private var importedRecipeId: String? = nil
    @State private var navigateToImported = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                VehiclesListView()
            }
            .tabItem { Label("Vehicles", systemImage: "car.fill") }
            .tag(0)

            NavigationStack {
                MealsHubView()
                    .navigationDestination(isPresented: $navigateToImported) {
                        if let id = importedRecipeId {
                            ImportedRecipePlaceholder(recipeId: id)
                                .environmentObject(auth)
                        }
                    }
            }
            .tabItem { Label("Meals", systemImage: "fork.knife") }
            .tag(1)

            NavigationStack {
                ShoppingListsView()
            }
            .tabItem { Label("Shopping", systemImage: "cart.fill") }
            .tag(2)

            if auth.currentUser?.canViewFinances == true {
                NavigationStack {
                    FinanceView()
                }
                .tabItem { Label("Finance", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(4)
            }

            AccountView(notifVM: notifVM)
                .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
                .badge(notifVM.unreadCount > 0 ? notifVM.unreadCount : 0)
                .tag(3)
        }
        .task {
            await notifVM.fetchUnreadCount(token: auth.accessToken ?? "")
        }
        .onOpenURL { url in
            handleURL(url)
        }
    }

    private func handleURL(_ url: URL) {
        // halehub://recipes — open Meals tab
        // halehub://recipes/<id> — open Meals tab and navigate to specific recipe
        guard url.scheme == "halehub" else { return }
        switch url.host {
        case "recipes":
            selectedTab = 1
            let pathId = url.pathComponents.dropFirst().first
            if let id = pathId, !id.isEmpty {
                importedRecipeId = id
                navigateToImported = true
            }
        case "vehicles":
            selectedTab = 0
        case "shopping":
            selectedTab = 2
        default:
            break
        }
    }
}

// Loads a recipe by ID and navigates to its detail view
struct ImportedRecipePlaceholder: View {
    @EnvironmentObject var auth: AuthManager
    let recipeId: String
    @State private var recipe: Recipe?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading recipe…")
            } else if let r = recipe {
                RecipeDetailView(recipe: r)
            } else {
                ContentUnavailableView("Recipe not found", systemImage: "fork.knife.circle")
            }
        }
        .task {
            guard let token = auth.accessToken else { isLoading = false; return }
            recipe = try? await APIClient.shared.get("/recipes/\(recipeId)/", token: token)
            isLoading = false
        }
    }
}
