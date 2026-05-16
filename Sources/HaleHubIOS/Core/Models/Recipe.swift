import Foundation

struct RecipeCategory: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let name: String
    let icon: String?
    let color: String?
    let order: Int
    var displayName: String { [icon, name].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " ") }
}

struct Recipe: Identifiable, Codable, Sendable {
    let id: UUID
    let title: String
    let description: String?
    let prepTime: Int?
    let cookTime: Int?
    let totalTime: Int?
    let servings: Int?
    let photoUrl: String?
    let isFavorite: Bool
    let rating: Int?
    let timesCooked: Int
    let lastCooked: Date?
    let instructions: String?
    let isGlutenFree: Bool?
    let isDairyFree: Bool?
    let isEggFree: Bool?
    let isNutFree: Bool?
    let isVegetarian: Bool?
    let isVegan: Bool?
    let calories: Int?
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    let fiber: Double?
    let ingredients: [Ingredient]?
    let categories: [RecipeCategory]?
    let notes: String?
    let sourceUrl: String?
    let sourceName: String?
    let importedFrom: String?
    let servingSize: String?
    let isGrainFree: Bool?
    let sodium: Double?
    let sugar: Double?
    let saturatedFat: Double?
    let cholesterol: Double?
    let ovenTemp: Int?

    var parsedSteps: [String] {
        guard let text = instructions, !text.isEmpty else { return [] }
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return lines.map { line in
            // Strip leading "1." or "1)" or "Step 1:" numbering
            let stripped = line.replacingOccurrences(of: #"^\d+[\.\)]\s*"#, with: "", options: .regularExpression)
            let noStep = stripped.replacingOccurrences(of: #"^[Ss]tep\s+\d+[:\.]\s*"#, with: "", options: .regularExpression)
            return noStep.isEmpty ? line : noStep
        }
    }
}

struct Ingredient: Identifiable, Codable, Sendable {
    let id: UUID
    let rawText: String
    let name: String?
    let quantity: String?
    let unit: String?
    let preparation: String?
    let isOptional: Bool
}

struct MealPlan: Identifiable, Codable, Sendable {
    let id: UUID
    let name: String?
    let displayName: String
    let startDate: Date?
    let endDate: Date?
    let isActive: Bool
    let createdAt: Date?
    let entries: [MealPlanEntry]?
}

struct MealPlanEntry: Identifiable, Codable, Sendable {
    let id: UUID
    let recipe: Recipe?
    let customName: String?
    let displayName: String
    let mealType: String?
    let date: Date?
    let servingsOverride: Int?
    let order: Int
    let sides: [MealPlanSide]?
}

struct MealPlanSide: Identifiable, Codable, Sendable {
    let id: UUID
    let name: String?
    let recipeTitle: String?
    let displayName: String
    let servingsOverride: Int?
    let order: Int
}

struct MarkCookedResponse: Decodable, Sendable {
    let id: UUID
    let timesCooked: Int
    let lastCooked: Date?
}

struct PaginatedResponse<T: Decodable & Sendable>: Decodable, Sendable {
    let count: Int
    let next: String?
    let previous: String?
    let results: [T]
}
