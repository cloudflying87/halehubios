import Foundation

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
    @Published var categories: [RecipeCategory] = []
    @Published var isLoading = false
    @Published var searchText = ""
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
        if !searchText.isEmpty {
            result = result.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
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

        async let recipesTask: PaginatedResponse<Recipe> = APIClient.shared.get(
            "/recipes/?sort=\(sortOrder.queryValue)", token: token
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
                    ingredients: old.ingredients, categories: old.categories
                )
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
