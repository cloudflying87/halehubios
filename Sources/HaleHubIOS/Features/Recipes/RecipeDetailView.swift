import SwiftUI

struct RecipeDetailView: View {
    @EnvironmentObject var auth: AuthManager
    let recipe: Recipe

    @State private var fullRecipe: Recipe?
    @State private var showCookedToast = false
    @State private var showCookMode = false

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
                    if displayed.timesCooked > 0 {
                        HStack {
                            Image(systemName: "flame.fill").foregroundStyle(.orange)
                            Text("Made \(displayed.timesCooked) time\(displayed.timesCooked == 1 ? "" : "s")")
                            if let last = displayed.lastCooked {
                                Text("· Last: \(last, style: .date)")
                                    .foregroundStyle(.secondary)
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
                Button {
                    Task { await markCooked() }
                } label: {
                    Label("Cooked It", systemImage: "checkmark.circle")
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
        .task { await loadFull() }
    }

    private func loadFull() async {
        guard let token = auth.accessToken, fullRecipe == nil else { return }
        fullRecipe = try? await APIClient.shared.get("/recipes/\(recipe.id)/", token: token)
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
