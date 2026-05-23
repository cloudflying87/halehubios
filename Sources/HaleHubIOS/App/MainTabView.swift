import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var network: NetworkMonitor
    @EnvironmentObject var deepLink: DeepLinkHandler
    @StateObject private var notifVM = NotificationsViewModel()

    @State private var selectedTab = 0
    @State private var importedRecipeId: String? = nil
    @State private var navigateToImported = false
    @State private var importDraftId: String? = nil
    @State private var showImportReview = false

    var body: some View {
        Group {
        if auth.currentUser?.totesOnly == true {
            // Totes-only users: single tab, no distractions
            NavigationStack {
                TotesListView()
            }
        } else {
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
        }
        }  // Group
        .task {
            await notifVM.fetchUnreadCount(token: auth.accessToken ?? "")
        }
        .onOpenURL { url in
            handleURL(url)
        }
        .sheet(isPresented: $showImportReview) {
            if let id = importDraftId {
                RecipeImportDraftSheet(importId: id) { recipe in
                    showImportReview = false
                    importedRecipeId = recipe.id.uuidString
                    navigateToImported = true
                }
                .environmentObject(auth)
            }
        }
    }

    private func handleURL(_ url: URL) {
        // halehub://recipes               — open Meals tab
        // halehub://recipes/<uuid>        — open Meals tab, navigate to recipe
        // halehub://recipes/review/<id>   — open Meals tab, show import review sheet
        guard url.scheme == "halehub" else { return }
        switch url.host {
        case "recipes":
            selectedTab = 1
            let parts = url.pathComponents.dropFirst()
            if parts.first == "review", let id = parts.dropFirst().first, !id.isEmpty {
                importDraftId = id
                showImportReview = true
            } else if let id = parts.first, !id.isEmpty {
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
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.3)
                    Text("Loading imported recipe…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let r = recipe {
                RecipeDetailView(recipe: r)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "fork.knife.circle")
                        .font(.system(size: 52))
                        .foregroundStyle(.secondary)
                    VStack(spacing: 8) {
                        Text("Recipe Not Found")
                            .font(.title3.bold())
                        if let msg = errorMessage {
                            Text(msg)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        } else {
                            Text("The recipe could not be loaded. It may still be processing — try again in a moment.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    Button("Try Again") {
                        Task { await load() }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Imported Recipe")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        guard let token = auth.accessToken else {
            errorMessage = "Not signed in — please open HaleHub and sign in, then try the shortcut again."
            isLoading = false
            return
        }
        do {
            recipe = try await APIClient.shared.get("/recipes/\(recipeId)/", token: token)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
