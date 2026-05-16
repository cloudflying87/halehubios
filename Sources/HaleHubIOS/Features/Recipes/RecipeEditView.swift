import SwiftUI

// MARK: - Editable Ingredient

struct EditableIngredient: Identifiable {
    var id: UUID = UUID()
    var rawText: String
}

// MARK: - Request Body

struct RecipeUpdateRequest: Encodable, Sendable {
    let title: String
    let description: String?
    let servings: Int?
    let prepTime: Int?
    let cookTime: Int?
    let notes: String?
    let isVegetarian: Bool?
    let isVegan: Bool?
    let isGlutenFree: Bool?
    let isDairyFree: Bool?
    let isEggFree: Bool?
    let isNutFree: Bool?
    let rating: Int?
    let ingredients: [IngredientUpdateItem]
    let instructions: String?

    struct IngredientUpdateItem: Encodable, Sendable {
        let rawText: String
    }
}

// MARK: - RecipeEditView

struct RecipeEditView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    let recipe: Recipe
    let onSaved: (Recipe) -> Void

    // Basic Info
    @State private var title: String
    @State private var description: String
    @State private var servings: Int
    @State private var servingsText: String
    @State private var prepTimeText: String
    @State private var cookTimeText: String
    @State private var notes: String

    // Dietary
    @State private var isVegetarian: Bool
    @State private var isVegan: Bool
    @State private var isGlutenFree: Bool
    @State private var isDairyFree: Bool
    @State private var isEggFree: Bool
    @State private var isNutFree: Bool

    // Rating
    @State private var rating: Int

    // Ingredients
    @State private var editableIngredients: [EditableIngredient]

    // Instructions
    @State private var instructionsText: String

    // State
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(recipe: Recipe, onSaved: @escaping (Recipe) -> Void) {
        self.recipe = recipe
        self.onSaved = onSaved

        _title = State(initialValue: recipe.title)
        _description = State(initialValue: recipe.description ?? "")
        _servings = State(initialValue: recipe.servings ?? 4)
        _servingsText = State(initialValue: recipe.servings.map { "\($0)" } ?? "")
        _prepTimeText = State(initialValue: recipe.prepTime.map { "\($0)" } ?? "")
        _cookTimeText = State(initialValue: recipe.cookTime.map { "\($0)" } ?? "")
        _notes = State(initialValue: recipe.notes ?? "")

        _isVegetarian = State(initialValue: recipe.isVegetarian ?? false)
        _isVegan = State(initialValue: recipe.isVegan ?? false)
        _isGlutenFree = State(initialValue: recipe.isGlutenFree ?? false)
        _isDairyFree = State(initialValue: recipe.isDairyFree ?? false)
        _isEggFree = State(initialValue: recipe.isEggFree ?? false)
        _isNutFree = State(initialValue: recipe.isNutFree ?? false)

        _rating = State(initialValue: recipe.rating ?? 0)

        let ingredients = recipe.ingredients?.map {
            EditableIngredient(rawText: $0.rawText)
        } ?? []
        _editableIngredients = State(initialValue: ingredients)

        // instructions is stored as a single string; display as-is
        _instructionsText = State(initialValue: recipe.instructions ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Basic Info
                Section("Basic Info") {
                    TextField("Title", text: $title)

                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(2...4)

                    HStack {
                        Text("Servings")
                        Spacer()
                        TextField("4", text: $servingsText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                    }

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Prep (min)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("0", text: $prepTimeText)
                                .keyboardType(.numberPad)
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cook (min)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("0", text: $cookTimeText)
                                .keyboardType(.numberPad)
                        }
                    }

                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                // MARK: Dietary
                Section("Dietary") {
                    Toggle("Vegetarian", isOn: $isVegetarian)
                    Toggle("Vegan", isOn: $isVegan)
                    Toggle("Gluten Free", isOn: $isGlutenFree)
                    Toggle("Dairy Free", isOn: $isDairyFree)
                    Toggle("Egg Free", isOn: $isEggFree)
                    Toggle("Nut Free", isOn: $isNutFree)
                }

                // MARK: Rating
                Section("Rating") {
                    HStack(spacing: 8) {
                        ForEach(1...5, id: \.self) { star in
                            Button {
                                if rating == star {
                                    rating = 0
                                } else {
                                    rating = star
                                }
                            } label: {
                                Image(systemName: star <= rating ? "star.fill" : "star")
                                    .font(.title2)
                                    .foregroundStyle(star <= rating ? .yellow : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                        if rating > 0 {
                            Text("\(rating)/5")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // MARK: Ingredients
                Section("Ingredients") {
                    ForEach($editableIngredients) { $ingredient in
                        TextField("Ingredient", text: $ingredient.rawText)
                    }
                    .onDelete { offsets in
                        editableIngredients.remove(atOffsets: offsets)
                    }

                    Button {
                        editableIngredients.append(EditableIngredient(rawText: ""))
                    } label: {
                        Label("Add Ingredient", systemImage: "plus.circle")
                    }
                }

                // MARK: Instructions
                Section("Instructions") {
                    TextEditor(text: $instructionsText)
                        .frame(minHeight: 140)
                        .lineLimit(6...20)
                }

                // MARK: Error
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Edit Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task { await save() }
                        }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    // MARK: - Save

    private func save() async {
        guard let token = auth.accessToken else { return }
        isSaving = true
        errorMessage = nil

        let request = RecipeUpdateRequest(
            title: title.trimmingCharacters(in: .whitespaces),
            description: description.isEmpty ? nil : description,
            servings: Int(servingsText),
            prepTime: Int(prepTimeText),
            cookTime: Int(cookTimeText),
            notes: notes.isEmpty ? nil : notes,
            isVegetarian: isVegetarian,
            isVegan: isVegan,
            isGlutenFree: isGlutenFree,
            isDairyFree: isDairyFree,
            isEggFree: isEggFree,
            isNutFree: isNutFree,
            rating: rating == 0 ? nil : rating,
            ingredients: editableIngredients
                .filter { !$0.rawText.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { RecipeUpdateRequest.IngredientUpdateItem(rawText: $0.rawText) },
            instructions: instructionsText.isEmpty ? nil : instructionsText
        )

        do {
            let updated: Recipe = try await APIClient.shared.patch(
                "/recipes/\(recipe.id)/update/", body: request, token: token
            )
            onSaved(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
