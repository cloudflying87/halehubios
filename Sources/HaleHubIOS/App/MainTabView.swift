import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var network: NetworkMonitor
    @EnvironmentObject var deepLink: DeepLinkHandler
    @StateObject private var notifVM = NotificationsViewModel()

    @State private var selectedTab = 0
    @State private var importedRecipeId: String? = nil
    @State private var navigateToImported = false
    /// Non-nil → the shortcut-deep-link review sheet is presented.
    /// We use a wrapped Identifiable so SwiftUI's `.sheet(item:)` can drive
    /// presentation — the older isPresented + optional id pattern raced and
    /// occasionally rendered a blank sheet because the body evaluated before
    /// the id propagated.
    @State private var importDraftRoute: ImportDraftRoute? = nil

    /// Tabs the user is allowed to see, derived from the permissions
    /// returned by /api/auth/me/. Vehicles is currently family-wide on the
    /// backend (`can_access_app('vehicles')` returns True for any role) so
    /// we keep it visible to everyone too — owners can change that by
    /// flipping a flag later. Account/More is always shown.
    private var allowedTabs: [TabSpec] {
        let user = auth.currentUser
        var tabs: [TabSpec] = []
        // Vehicles
        if user?.can("vehicles") ?? true {
            tabs.append(.vehicles)
        }
        // Meals / Recipes
        if user?.can("recipes") ?? false {
            tabs.append(.meals)
        }
        // Shopping (lists)
        if user?.can("lists") ?? false {
            tabs.append(.shopping)
        }
        // Finance
        if user?.can("finance") ?? false {
            tabs.append(.finance)
        }
        // Account / More is always present
        tabs.append(.account)
        return tabs
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(Array(allowedTabs.enumerated()), id: \.element) { index, tab in
                tabView(for: tab)
                    .tabItem { Label(tab.title, systemImage: tab.icon) }
                    .tag(index)
                    .modifier(MoreBadgeModifier(tab: tab, count: notifVM.unreadCount))
            }
        }
        .task {
            await auth.fetchCurrentUser()    // refresh permissions on every cold-launch
            await notifVM.fetchUnreadCount(token: auth.accessToken ?? "")
        }
        .onOpenURL { url in
            handleURL(url)
        }
        .sheet(item: $importDraftRoute) { route in
            RecipeImportDraftSheet(importId: route.id) { recipe in
                importDraftRoute = nil
                importedRecipeId = recipe.id.uuidString
                navigateToImported = true
            }
            .environmentObject(auth)
        }
    }

    @ViewBuilder
    private func tabView(for tab: TabSpec) -> some View {
        switch tab {
        case .vehicles:
            NavigationStack { VehiclesListView() }
        case .meals:
            NavigationStack {
                MealsHubView()
                    .navigationDestination(isPresented: $navigateToImported) {
                        if let id = importedRecipeId {
                            ImportedRecipePlaceholder(recipeId: id)
                                .environmentObject(auth)
                        }
                    }
            }
        case .shopping:
            NavigationStack { ShoppingListsView() }
        case .finance:
            NavigationStack { FinanceView() }
        case .account:
            AccountView(notifVM: notifVM)
        }
    }

    /// Find the tab index for a deep-link target, returning nil when the
    /// user doesn't have access (so we don't try to select an invisible tab).
    private func tabIndex(for tab: TabSpec) -> Int? {
        allowedTabs.firstIndex(of: tab)
    }

    private func handleURL(_ url: URL) {
        // halehub://recipes               — open Meals tab
        // halehub://recipes/<uuid>        — open Meals tab, navigate to recipe
        // halehub://recipes/review/<id>   — open Meals tab, show import review sheet
        guard url.scheme == "halehub" else { return }
        switch url.host {
        case "recipes":
            if let idx = tabIndex(for: .meals) { selectedTab = idx }
            let parts = url.pathComponents.dropFirst()
            if parts.first == "review", let id = parts.dropFirst().first, !id.isEmpty {
                // `.sheet(item:)` presents only when the optional becomes non-nil,
                // so wrapping ensures the importId is present at body-eval time.
                importDraftRoute = ImportDraftRoute(id: id)
            } else if let id = parts.first, !id.isEmpty {
                importedRecipeId = id
                navigateToImported = true
            }
        case "vehicles":
            if let idx = tabIndex(for: .vehicles) { selectedTab = idx }
        case "shopping":
            if let idx = tabIndex(for: .shopping) { selectedTab = idx }
        default:
            break
        }
    }
}

// MARK: - Shortcut review route

/// Wraps the import id so it can drive `.sheet(item:)` — the wrapped
/// optional becomes the single source of truth for both "is sheet up?"
/// and "which import?", which avoids the blank-sheet race we hit when
/// these were two separate `@State` properties.
private struct ImportDraftRoute: Identifiable, Hashable {
    let id: String
}

// MARK: - Tab spec

/// Identifies a top-level tab. Used to derive the visible tab set from the
/// user's permissions while keeping deep links robust to tab reorderings.
enum TabSpec: Hashable {
    case vehicles, meals, shopping, finance, account

    var title: String {
        switch self {
        case .vehicles: return "Vehicles"
        case .meals:    return "Meals"
        case .shopping: return "Shopping"
        case .finance:  return "Finance"
        case .account:  return "More"
        }
    }

    var icon: String {
        switch self {
        case .vehicles: return "car.fill"
        case .meals:    return "fork.knife"
        case .shopping: return "cart.fill"
        case .finance:  return "chart.line.uptrend.xyaxis"
        case .account:  return "ellipsis.circle.fill"
        }
    }
}

/// Only the More/account tab carries the notification badge.
private struct MoreBadgeModifier: ViewModifier {
    let tab: TabSpec
    let count: Int

    func body(content: Content) -> some View {
        if tab == .account {
            content.badge(count > 0 ? count : 0)
        } else {
            content
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
