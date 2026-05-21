import Foundation

// MARK: - Meal Plan API request

struct AddToMealPlanRequest: Encodable, Sendable {
    let recipeId: String
    let mealType: String
    let date: String?
}

enum DietaryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case glutenFree = "GF"
    case dairyFree = "DF"
    case vegetarian = "Vegetarian"
    case vegan = "Vegan"
    var id: String { rawValue }

    var queryParam: (String, String)? {
        switch self {
        case .all: return nil
        case .glutenFree: return ("is_gluten_free", "true")
        case .dairyFree: return ("is_dairy_free", "true")
        case .vegetarian: return ("is_vegetarian", "true")
        case .vegan: return ("is_vegan", "true")
        }
    }
}

enum RecipeSortOrder: String, CaseIterable, Identifiable {
    case title = "Name"
    case timesCooked = "Most Cooked"
    case lastCooked = "Recently Cooked"
    case rating = "Rating"
    var id: String { rawValue }
    var queryValue: String {
        switch self {
        case .title: return "title"
        case .timesCooked: return "times_cooked"
        case .lastCooked: return "last_cooked"
        case .rating: return "rating"
        }
    }
}

@MainActor
class RecipesViewModel: ObservableObject {
    @Published var recipes: [Recipe] = []
    @Published var activeMealPlan: MealPlan?
    @Published var allPlans: [MealPlan] = []
    @Published var categories: [RecipeCategory] = []
    @Published var isLoading = false
    @Published var isLoadingAllPlans = false
    @Published var searchText = ""
    @Published var searchQuery = ""
    @Published var showFavoritesOnly = false
    @Published var dietaryFilter: DietaryFilter = .all
    @Published var sortOrder: RecipeSortOrder = .title
    @Published var selectedCategoryId: UUID? = nil
    @Published var error: String?
    @Published var cacheDate: Date?
    @Published var isFromCache = false

    private let recipeCacheKey = "recipes"
    private let planCacheKey = "active_meal_plan"
    private let categoriesCacheKey = "recipe_categories"

    var filtered: [Recipe] {
        var result = recipes
        if !searchQuery.isEmpty {
            result = result.filter { $0.title.localizedCaseInsensitiveContains(searchQuery) }
        }
        if showFavoritesOnly {
            result = result.filter { $0.isFavorite }
        }
        if let catId = selectedCategoryId {
            result = result.filter { $0.categories?.contains(where: { $0.id == catId }) == true }
        }
        switch dietaryFilter {
        case .all: break
        case .glutenFree: result = result.filter { $0.isGlutenFree == true }
        case .dairyFree: result = result.filter { $0.isDairyFree == true }
        case .vegetarian: result = result.filter { $0.isVegetarian == true }
        case .vegan: result = result.filter { $0.isVegan == true }
        }
        return result
    }

    func load(token: String, isConnected: Bool = true) async {
        // Serve from cache immediately
        if recipes.isEmpty {
            if let cached: [Recipe] = await CacheManager.shared.load(key: recipeCacheKey) {
                recipes = cached
                isFromCache = true
                cacheDate = await CacheManager.shared.cacheDate(key: recipeCacheKey)
            }
            if let cachedPlan: MealPlan = await CacheManager.shared.load(key: planCacheKey) {
                activeMealPlan = cachedPlan
            }
            if let cachedCats: [RecipeCategory] = await CacheManager.shared.load(key: categoriesCacheKey) {
                categories = cachedCats
            }
        }

        guard isConnected else { return }

        isLoading = true
        error = nil

        let searchSuffix = searchQuery.isEmpty ? "" : "&search=\(searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? searchQuery)"
        async let recipesTask: PaginatedResponse<Recipe> = APIClient.shared.get(
            "/recipes/?sort=\(sortOrder.queryValue)\(searchSuffix)", token: token
        )
        async let planTask: MealPlan = APIClient.shared.get("/meal-plans/active/", token: token)
        async let categoriesTask: [RecipeCategory] = APIClient.shared.get("/recipes/categories/", token: token)

        do {
            let r = try await recipesTask
            recipes = r.results
            isFromCache = false
            cacheDate = Date()
            await CacheManager.shared.save(r.results, key: recipeCacheKey)
        } catch {
            self.error = error.localizedDescription
        }
        if let plan = try? await planTask {
            activeMealPlan = plan
            await CacheManager.shared.save(plan, key: planCacheKey)
        }
        if let c = try? await categoriesTask {
            categories = c
            await CacheManager.shared.save(c, key: categoriesCacheKey)
        }
        isLoading = false
    }

    func search(query: String, token: String) async {
        searchQuery = query
        await load(token: token)
    }

    func addToMealPlan(planId: String, recipeId: String, dayOfWeek: Int, mealType: String, token: String) async throws {
        // dayOfWeek is informational; compute date from active plan's start_date if available
        var dateString: String? = nil
        if let plan = activeMealPlan, let start = plan.startDate {
            var components = Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: start)
            components.weekday = dayOfWeek + 2  // Calendar weekday: 1=Sun, Swift expects 1-based; dayOfWeek 0=Mon
            if let targetDate = Calendar.current.date(from: components) {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                dateString = formatter.string(from: targetDate)
            }
        }
        let body = AddToMealPlanRequest(recipeId: recipeId, mealType: mealType, date: dateString)
        let _: MealPlanEntry = try await APIClient.shared.post(
            "/meal-plans/\(planId)/entries/", body: body, token: token
        )
        // Refresh the active plan so the UI reflects the new entry
        if let updatedPlan: MealPlan = try? await APIClient.shared.get("/meal-plans/active/", token: token) {
            activeMealPlan = updatedPlan
            await CacheManager.shared.save(updatedPlan, key: planCacheKey)
        }
    }

    func removeFromMealPlan(entryId: String, token: String) async throws {
        try await APIClient.shared.delete("/meal-plans/entries/\(entryId)/", token: token)
        // Refresh the active plan so the UI reflects the deletion
        if let updatedPlan: MealPlan = try? await APIClient.shared.get("/meal-plans/active/", token: token) {
            activeMealPlan = updatedPlan
            await CacheManager.shared.save(updatedPlan, key: planCacheKey)
        }
    }

    // MARK: - Recipe Update

    func updateRecipe(_ recipe: Recipe, request: RecipeUpdateRequest, token: String) async throws -> Recipe {
        let updated: Recipe = try await APIClient.shared.patch(
            "/recipes/\(recipe.id)/update/", body: request, token: token
        )
        if let idx = recipes.firstIndex(where: { $0.id == updated.id }) {
            recipes[idx] = updated
        }
        await CacheManager.shared.save(recipes, key: recipeCacheKey)
        return updated
    }

    // MARK: - Recipe Import from URL

    func importRecipe(url: String, token: String) async throws -> Recipe {
        struct ImportRequest: Encodable, Sendable { let url: String }
        let recipe: Recipe = try await APIClient.shared.post(
            "/recipes/import/", body: ImportRequest(url: url), token: token
        )
        recipes.insert(recipe, at: 0)
        await CacheManager.shared.save(recipes, key: recipeCacheKey)
        return recipe
    }

    func importRecipeFromText(_ text: String, token: String) async throws -> Recipe {
        struct TextImportRequest: Encodable, Sendable {
            let recipeJson: String
        }
        let recipe: Recipe = try await APIClient.shared.post(
            "/recipes/import/shortcut/",
            body: TextImportRequest(recipeJson: text),
            token: token
        )
        recipes.insert(recipe, at: 0)
        await CacheManager.shared.save(recipes, key: recipeCacheKey)
        return recipe
    }

    // MARK: - Sides Management

    func addSideToEntry(entryId: String, recipeId: String, token: String) async throws {
        struct AddSideRequest: Encodable, Sendable { let recipeId: String }
        let _: MealPlanSide = try await APIClient.shared.post(
            "/meal-plans/entries/\(entryId)/sides/",
            body: AddSideRequest(recipeId: recipeId),
            token: token
        )
        await refreshActivePlan(token: token)
    }

    func addTextSideToEntry(entryId: String, name: String, token: String) async throws {
        struct AddTextSideRequest: Encodable, Sendable { let name: String }
        let _: MealPlanSide = try await APIClient.shared.post(
            "/meal-plans/entries/\(entryId)/sides/",
            body: AddTextSideRequest(name: name),
            token: token
        )
        await refreshActivePlan(token: token)
    }

    func removeSideFromEntry(entryId: String, sideId: String, token: String) async throws {
        try await APIClient.shared.delete("/meal-plans/entries/\(entryId)/sides/\(sideId)/", token: token)
        await refreshActivePlan(token: token)
    }

    private func refreshActivePlan(token: String) async {
        if let updated: MealPlan = try? await APIClient.shared.get("/meal-plans/active/", token: token) {
            activeMealPlan = updated
            await CacheManager.shared.save(updated, key: planCacheKey)
        }
    }

    // MARK: - Shopping List Generation

    func generateShoppingList(
        planId: String, listId: String,
        skipStaples: Bool = false, skipPantry: Bool = false,
        token: String
    ) async throws -> ShoppingList {
        struct GenerateRequest: Encodable, Sendable {
            let listId: String
            let skipStaples: Bool
            let skipPantry: Bool
        }
        return try await APIClient.shared.post(
            "/meal-plans/\(planId)/generate-shopping-list/",
            body: GenerateRequest(listId: listId, skipStaples: skipStaples, skipPantry: skipPantry),
            token: token
        )
    }

    func fetchShoppingPreview(
        planId: String,
        skipStaples: Bool = false,
        skipPantry: Bool = false,
        token: String
    ) async throws -> [ShoppingPreviewItemData] {
        let path = "/meal-plans/\(planId)/shopping-preview/?skip_staples=\(skipStaples)&skip_pantry=\(skipPantry)"
        let response: ShoppingPreviewResponse = try await APIClient.shared.get(path, token: token)
        return response.items
    }

    func addItemsToList(names: [String], listId: String, token: String) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for name in names {
                group.addTask {
                    let body = AddItemRequest(name: name, quantity: "", notes: "")
                    let _: ShoppingItem = try await APIClient.shared.post(
                        "/shopping/\(listId)/items/", body: body, token: token
                    )
                }
            }
            try await group.waitForAll()
        }
    }

    // MARK: - Shopping Session

    func createOrResumeSession(
        planId: String,
        skipStaples: Bool = true,
        skipPantry: Bool = false,
        token: String
    ) async throws -> ShoppingSession {
        struct CreateRequest: Encodable, Sendable { let skipStaples: Bool; let skipPantry: Bool }
        return try await APIClient.shared.post(
            "/meal-plans/\(planId)/shopping-session/",
            body: CreateRequest(skipStaples: skipStaples, skipPantry: skipPantry),
            token: token
        )
    }

    func dispatchSessionItems(
        planId: String, itemIds: [String], listId: String, token: String
    ) async throws -> ShoppingSession {
        struct DispatchRequest: Encodable, Sendable { let itemIds: [String]; let listId: String }
        return try await APIClient.shared.post(
            "/meal-plans/\(planId)/shopping-session/dispatch/",
            body: DispatchRequest(itemIds: itemIds, listId: listId),
            token: token
        )
    }

    func completeSession(planId: String, token: String) async throws -> ShoppingSession {
        return try await APIClient.shared.postEmpty(
            "/meal-plans/\(planId)/shopping-session/complete/", token: token
        )
    }

    func resetSession(planId: String, token: String) async throws {
        try await APIClient.shared.delete(
            "/meal-plans/\(planId)/shopping-session/", token: token
        )
    }

    // MARK: - All Plans

    func loadAllPlans(token: String) async {
        isLoadingAllPlans = true
        do {
            let response: PaginatedResponse<MealPlan> = try await APIClient.shared.get("/meal-plans/", token: token)
            allPlans = response.results
        } catch {
            self.error = error.localizedDescription
        }
        isLoadingAllPlans = false
    }

    func fetchPlanDetail(planId: UUID, token: String) async throws -> MealPlan {
        return try await APIClient.shared.get("/meal-plans/\(planId)/", token: token)
    }

    func createMealPlan(name: String, startDate: Date?, endDate: Date?, token: String) async throws -> MealPlan {
        struct CreateRequest: Encodable, Sendable {
            let name: String
            let startDate: String?
            let endDate: String?
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let plan: MealPlan = try await APIClient.shared.post(
            "/meal-plans/",
            body: CreateRequest(
                name: name,
                startDate: startDate.map { fmt.string(from: $0) },
                endDate: endDate.map { fmt.string(from: $0) }
            ),
            token: token
        )
        allPlans.insert(plan, at: 0)
        return plan
    }

    func markCooked(recipe: Recipe, token: String) async {
        do {
            let response: MarkCookedResponse = try await APIClient.shared.postEmpty(
                "/recipes/\(recipe.id)/mark-cooked/", token: token
            )
            if let idx = recipes.firstIndex(where: { $0.id == recipe.id }) {
                let old = recipes[idx]
                recipes[idx] = Recipe(
                    id: old.id, title: old.title, description: old.description,
                    prepTime: old.prepTime, cookTime: old.cookTime, totalTime: old.totalTime,
                    servings: old.servings, photoUrl: old.photoUrl,
                    isFavorite: old.isFavorite, rating: old.rating,
                    timesCooked: response.timesCooked, lastCooked: response.lastCooked,
                    instructions: old.instructions, isGlutenFree: old.isGlutenFree,
                    isDairyFree: old.isDairyFree, isEggFree: old.isEggFree,
                    isNutFree: old.isNutFree, isVegetarian: old.isVegetarian,
                    isVegan: old.isVegan, calories: old.calories, protein: old.protein,
                    carbs: old.carbs, fat: old.fat, fiber: old.fiber,
                    ingredients: old.ingredients, categories: old.categories,
                    notes: old.notes, sourceUrl: old.sourceUrl, sourceName: old.sourceName,
                    importedFrom: old.importedFrom, servingSize: old.servingSize,
                    isGrainFree: old.isGrainFree, sodium: old.sodium, sugar: old.sugar,
                    saturatedFat: old.saturatedFat, cholesterol: old.cholesterol,
                    ovenTemp: old.ovenTemp
                )
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
