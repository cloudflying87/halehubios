import SwiftUI

struct RecipeDetailView: View {
    @EnvironmentObject var auth: AuthManager
    let recipe: Recipe

    @State private var fullRecipe: Recipe?
    @State private var loadError: String?
    @State private var isLoadingFull = false
    @State private var showCookedToast = false
    @State private var showCookMode = false
    @State private var showAddToMealPlan = false
    @State private var showEditRecipe = false

    var displayed: Recipe { fullRecipe ?? recipe }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Hero image
                HeroImage(url: displayed.photoUrl)

                VStack(alignment: .leading, spacing: 20) {
                    // Title + rating
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top) {
                            Text(displayed.title)
                                .font(.title2.bold())
                            Spacer()
                            if displayed.isFavorite {
                                Image(systemName: "heart.fill")
                                    .foregroundStyle(.red)
                                    .font(.title3)
                            }
                        }
                        if let rating = displayed.rating {
                            StarRating(rating: rating)
                        }
                        if let desc = displayed.description, !desc.isEmpty {
                            Text(desc)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Stat pills
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            if let prep = displayed.prepTime { StatPill(label: "Prep", value: "\(prep)m") }
                            if let cook = displayed.cookTime { StatPill(label: "Cook", value: "\(cook)m") }
                            if let total = displayed.totalTime { StatPill(label: "Total", value: "\(total)m") }
                            if let servings = displayed.servings { StatPill(label: "Serves", value: "\(servings)") }
                            if let cal = displayed.calories { StatPill(label: "Cal", value: "\(cal)") }
                        }
                    }

                    // Dietary badges
                    let dietBadges = [
                        displayed.isVegetarian == true ? "Vegetarian" : nil,
                        displayed.isVegan == true ? "Vegan" : nil,
                        displayed.isGlutenFree == true ? "Gluten Free" : nil,
                        displayed.isDairyFree == true ? "Dairy Free" : nil,
                        displayed.isEggFree == true ? "Egg Free" : nil,
                        displayed.isNutFree == true ? "Nut Free" : nil,
                    ].compactMap { $0 }
                    if !dietBadges.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(dietBadges, id: \.self) { badge in
                                    Text(badge)
                                        .font(.caption.bold())
                                        .foregroundStyle(.green)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.green.opacity(0.1), in: Capsule())
                                }
                            }
                        }
                    }

                    Divider()

                    // Loading / error state while fetching full recipe
                    if isLoadingFull {
                        HStack {
                            ProgressView()
                            Text("Loading details…").foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                    if let err = loadError {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Couldn't load full recipe: \(err)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Retry") { Task { fullRecipe = nil; await loadFull() } }
                                .font(.caption)
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                        }
                        .padding(.vertical, 4)
                    }

                    // Nutrition
                    if displayed.calories != nil || displayed.protein != nil {
                        NutritionSection(recipe: displayed)
                        Divider()
                    }

                    // Ingredients
                    if let ingredients = displayed.ingredients, !ingredients.isEmpty {
                        IngredientsSection(ingredients: ingredients)
                        Divider()
                    }

                    // Instructions
                    if !displayed.parsedSteps.isEmpty {
                        InstructionsSection(steps: displayed.parsedSteps, onCookMode: {
                            showCookMode = true
                        })
                    }

                    // Stats footer
                    if displayed.timesCooked > 0 || displayed.importedFrom != nil {
                        VStack(alignment: .leading, spacing: 4) {
                            if displayed.timesCooked > 0 {
                                HStack {
                                    Image(systemName: "flame.fill").foregroundStyle(.orange)
                                    Text("Made \(displayed.timesCooked) time\(displayed.timesCooked == 1 ? "" : "s")")
                                    if let last = displayed.lastCooked {
                                        Text("· Last: \(last, style: .date)")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            if let source = displayed.importedFrom {
                                HStack {
                                    Image(systemName: "square.and.arrow.down").foregroundStyle(.secondary)
                                    Text("Imported from \(source)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        Task { await markCooked() }
                    } label: {
                        Label("Cooked It", systemImage: "checkmark.circle")
                    }
                    Button {
                        showAddToMealPlan = true
                    } label: {
                        Label("Add to Meal Plan", systemImage: "calendar.badge.plus")
                    }
                    Button {
                        showEditRecipe = true
                    } label: {
                        Label("Edit Recipe", systemImage: "pencil")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .overlay(alignment: .bottom) {
            if showCookedToast {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Marked as cooked!")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 32)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: showCookedToast)
        .fullScreenCover(isPresented: $showCookMode) {
            if !displayed.parsedSteps.isEmpty {
                CookModeView(title: displayed.title, steps: displayed.parsedSteps)
            }
        }
        .sheet(isPresented: $showAddToMealPlan) {
            AddToMealPlanSheet(recipe: displayed)
                .environmentObject(auth)
        }
        .sheet(isPresented: $showEditRecipe) {
            RecipeEditView(recipe: displayed) { updatedRecipe in
                fullRecipe = updatedRecipe
            }
            .environmentObject(auth)
        }
        .task { await loadFull() }
    }

    private func loadFull() async {
        guard let token = auth.accessToken, fullRecipe == nil else { return }
        isLoadingFull = true
        do {
            fullRecipe = try await APIClient.shared.get("/recipes/\(recipe.id)/", token: token)
        } catch {
            loadError = error.localizedDescription
        }
        isLoadingFull = false
    }

    private func markCooked() async {
        guard let token = auth.accessToken else { return }
        do {
            let _: MarkCookedResponse = try await APIClient.shared.postEmpty(
                "/recipes/\(recipe.id)/mark-cooked/", token: token
            )
            showCookedToast = true
            try? await Task.sleep(for: .seconds(2))
            showCookedToast = false
        } catch {}
    }
}

// MARK: - Add to Meal Plan Sheet

struct AddToMealPlanSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe

    @State private var mealPlans: [MealPlan] = []
    @State private var selectedPlanId: String = ""
    @State private var selectedDayOfWeek: Int = 0
    @State private var selectedMealType: String = "dinner"
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let mealTypes = ["breakfast", "lunch", "dinner", "snack"]
    private let daysOfWeek = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    var body: some View {
        NavigationStack {
            Form {
                if isLoading {
                    Section {
                        ProgressView("Loading meal plans…")
                    }
                } else if mealPlans.isEmpty {
                    Section {
                        Text("No meal plans found. Create one on the website first.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Meal Plan") {
                        Picker("Plan", selection: $selectedPlanId) {
                            ForEach(mealPlans, id: \.id) { plan in
                                Text(plan.displayName).tag(plan.id.uuidString)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Section("Schedule") {
                        Picker("Day", selection: $selectedDayOfWeek) {
                            ForEach(Array(daysOfWeek.enumerated()), id: \.offset) { index, day in
                                Text(day).tag(index)
                            }
                        }
                        .pickerStyle(.menu)

                        Picker("Meal", selection: $selectedMealType) {
                            ForEach(mealTypes, id: \.self) { type in
                                Text(type.capitalized).tag(type)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    if let error = errorMessage {
                        Section {
                            Text(error).foregroundStyle(.red).font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Add to Meal Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task { await addToMealPlan() }
                    }
                    .disabled(selectedPlanId.isEmpty || isSaving || isLoading)
                }
            }
        }
        .task { await loadMealPlans() }
    }

    private func loadMealPlans() async {
        guard let token = auth.accessToken else { return }
        isLoading = true
        do {
            let response: PaginatedResponse<MealPlan> = try await APIClient.shared.get("/meal-plans/", token: token)
            mealPlans = response.results
            if let first = mealPlans.first {
                selectedPlanId = first.id.uuidString
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func addToMealPlan() async {
        guard let token = auth.accessToken, !selectedPlanId.isEmpty else { return }
        isSaving = true
        errorMessage = nil
        let body = AddToMealPlanRequest(
            recipeId: recipe.id.uuidString,
            mealType: selectedMealType,
            date: nil
        )
        do {
            let _: MealPlanEntry = try await APIClient.shared.post(
                "/meal-plans/\(selectedPlanId)/entries/", body: body, token: token
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}

// MARK: - Hero Image

struct HeroImage: View {
    let url: String?
    var body: some View {
        Group {
            if let urlString = url, let imageURL = URL(string: urlString) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Color(.systemGray5)
                    }
                }
            } else {
                Color(.systemGray5)
                    .overlay(Image(systemName: "fork.knife").font(.largeTitle).foregroundStyle(.tertiary))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 240)
        .clipped()
    }
}

// MARK: - Nutrition Section

struct NutritionSection: View {
    let recipe: Recipe
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nutrition per serving")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                if let cal = recipe.calories { NutrientCell(label: "Calories", value: "\(cal)") }
                if let p = recipe.protein { NutrientCell(label: "Protein", value: "\(p)g") }
                if let c = recipe.carbs { NutrientCell(label: "Carbs", value: "\(c)g") }
                if let f = recipe.fat { NutrientCell(label: "Fat", value: "\(f)g") }
                if let fi = recipe.fiber { NutrientCell(label: "Fiber", value: "\(fi)g") }
            }
        }
    }
}

struct NutrientCell: View {
    let label: String
    let value: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Ingredients Section

struct IngredientsSection: View {
    let ingredients: [Ingredient]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ingredients")
                .font(.headline)
            ForEach(ingredients) { ing in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)
                    Text(ing.rawText)
                        .font(.body)
                    if ing.isOptional {
                        Spacer()
                        Text("optional")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}

// MARK: - Instructions Section

struct InstructionsSection: View {
    let steps: [String]
    let onCookMode: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Instructions")
                    .font(.headline)
                Spacer()
                Button("Cook Mode", action: onCookMode)
                    .font(.subheadline)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Color.accentColor, in: Circle())
                    Text(step)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Shared Components

struct StatPill: View {
    let label: String
    let value: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(minWidth: 52)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
    }
}
