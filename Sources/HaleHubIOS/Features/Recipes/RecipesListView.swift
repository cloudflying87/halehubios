import SwiftUI

struct RecipesListView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = RecipesViewModel()
    @State private var showImportURL = false
    @State private var importedRecipe: Recipe?
    @State private var navigateToImported = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        // The search bar lives on this always-present container so it is never
        // torn down and recreated when loading state changes — that teardown was
        // what made the field jump and lose focus mid-typing.
        VStack(spacing: 0) {
            FilterBar(vm: vm)
                .padding(.vertical, 8)
            Divider()
            recipeContent
        }
        .navigationDestination(isPresented: $navigateToImported) {
            if let imported = importedRecipe {
                RecipeDetailView(recipe: imported).environmentObject(auth)
            }
        }
        .searchable(
            text: $vm.searchQuery,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search recipes…"
        )
        .onChange(of: vm.searchQuery) { _, query in
            // Results filter instantly client-side (vm.filtered). This debounced
            // server search just augments for large libraries; cancel the prior
            // one so a burst of keystrokes fires at most one request.
            searchTask?.cancel()
            let token = auth.accessToken ?? ""
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                await vm.search(query: query, token: token)
            }
        }
        .navigationTitle("Recipes")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { Task { await vm.load(token: auth.accessToken ?? "", isConnected: true) } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(vm.isLoading)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Section("Sort") {
                        ForEach(RecipeSortOrder.allCases) { order in
                            Button {
                                vm.sortOrder = order
                                Task { await vm.load(token: auth.accessToken ?? "") }
                            } label: {
                                if vm.sortOrder == order {
                                    Label(order.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(order.rawValue)
                                }
                            }
                        }
                    }
                    Section {
                        Button {
                            vm.showFavoritesOnly.toggle()
                        } label: {
                            Label(
                                vm.showFavoritesOnly ? "All Recipes" : "Favorites Only",
                                systemImage: vm.showFavoritesOnly ? "heart.slash" : "heart.fill"
                            )
                        }
                    }
                    Section {
                        Button {
                            showImportURL = true
                        } label: {
                            Label("Import from URL", systemImage: "square.and.arrow.down")
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .sheet(isPresented: $showImportURL) {
            ImportRecipeFromURLSheet(vm: vm) { recipe in
                importedRecipe = recipe
                navigateToImported = true
            }
            .environmentObject(auth)
        }
        .task { await vm.load(token: auth.accessToken ?? "") }
    }

    @ViewBuilder
    private var recipeContent: some View {
        // Only show the full-screen spinner on the initial load (no recipes yet
        // and not searching) — never while typing a search, so the field stays put.
        if vm.isLoading && vm.recipes.isEmpty && vm.searchQuery.isEmpty {
            ProgressView("Loading recipes…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.filtered.isEmpty {
            ContentUnavailableView {
                Label(vm.searchQuery.isEmpty ? "No Recipes" : "No Matches",
                      systemImage: "magnifyingglass")
            } description: {
                Text(vm.searchQuery.isEmpty
                     ? "Import a recipe to get started."
                     : "No recipes match \u{201C}\(vm.searchQuery)\u{201D}.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(vm.filtered) { recipe in
                    NavigationLink(destination: RecipeDetailView(recipe: recipe, onDelete: { id in
                        vm.recipes.removeAll { $0.id == id }
                    }).environmentObject(auth)) {
                        RecipeRow(recipe: recipe)
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - Import Recipe Sheet (URL + Paste Text → Review)

struct ImportRecipeFromURLSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: RecipesViewModel
    let onSuccess: (Recipe) -> Void

    enum ImportMode: String, CaseIterable { case url = "URL", text = "Paste Text" }

    @State private var mode: ImportMode = .url
    @State private var urlText = ""
    @State private var pastedText = ""
    @State private var isParsing = false
    @State private var errorMessage: String?
    @State private var parsedData: ParsedRecipeData?
    @State private var showReview = false

    private var canContinue: Bool {
        switch mode {
        case .url:  return !urlText.trimmingCharacters(in: .whitespaces).isEmpty
        case .text: return !pastedText.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Mode", selection: $mode) {
                        ForEach(ImportMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                .listRowBackground(Color.clear)

                switch mode {
                case .url:
                    Section {
                        TextField("https://", text: $urlText)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    } header: {
                        Text("Recipe URL")
                    } footer: {
                        Text("Paste the URL of any recipe website. Most major food sites are supported.")
                    }

                case .text:
                    Section {
                        TextEditor(text: $pastedText)
                            .frame(minHeight: 200)
                            .autocorrectionDisabled()
                    } header: {
                        Text("Recipe Text")
                    } footer: {
                        Text("Paste the recipe — including title, ingredients, and instructions.")
                    }
                }

                if isParsing {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Parsing recipe…").foregroundStyle(.secondary)
                        }
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.callout)
                    }
                }
            }
            .navigationTitle("Import Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isParsing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") {
                        Task { await parse() }
                    }
                    .disabled(!canContinue || isParsing)
                }
            }
            .navigationDestination(isPresented: $showReview) {
                if let data = parsedData {
                    RecipeImportReviewView(vm: vm, parsed: data) { recipe in
                        dismiss()
                        onSuccess(recipe)
                    }
                    .environmentObject(auth)
                }
            }
        }
    }

    private func parse() async {
        guard let token = auth.accessToken else { return }
        isParsing = true
        errorMessage = nil
        do {
            switch mode {
            case .url:
                parsedData = try await vm.parseRecipeFromURL(
                    url: urlText.trimmingCharacters(in: .whitespaces), token: token
                )
            case .text:
                parsedData = try await vm.parseRecipeFromText(
                    pastedText.trimmingCharacters(in: .whitespaces), token: token
                )
            }
            showReview = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isParsing = false
    }
}

// MARK: - Recipe Import Review

struct RecipeImportReviewView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: RecipesViewModel
    let onSuccess: (Recipe) -> Void

    @State private var parsed: ParsedRecipeData
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var duplicates: [RecipeDuplicateMatch] = []

    init(vm: RecipesViewModel, parsed: ParsedRecipeData, onSuccess: @escaping (Recipe) -> Void) {
        self.vm = vm
        self._parsed = State(initialValue: parsed)
        self.onSuccess = onSuccess
    }

    var body: some View {
        Form {
            if !duplicates.isEmpty {
                Section {
                    Label("You may already have this recipe", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.orange)
                    ForEach(duplicates) { dup in
                        Text(dup.title).font(.callout).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("You can still save it as a separate recipe.")
                }
            }

            if let warning = parsed.parseWarning {
                Section {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }

            // Image preview
            if !parsed.imageUrl.isEmpty, let url = URL(string: parsed.imageUrl) {
                Section {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: Color(.systemGray5)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipped()
                    .listRowInsets(.init())
                }
            }

            Section("Title") {
                TextField("Recipe title", text: $parsed.title)
            }

            Section("Times & Servings") {
                HStack {
                    Text("Prep")
                    Spacer()
                    OptionalIntField("min", value: $parsed.prepTime)
                }
                HStack {
                    Text("Cook")
                    Spacer()
                    OptionalIntField("min", value: $parsed.cookTime)
                }
                HStack {
                    Text("Total")
                    Spacer()
                    OptionalIntField("min", value: $parsed.totalTime)
                }
                HStack {
                    Text("Servings")
                    Spacer()
                    OptionalIntField("servings", value: $parsed.servings)
                }
            }

            if !parsed.ingredients.isEmpty {
                Section("Ingredients (\(parsed.ingredients.count))") {
                    ForEach(parsed.ingredients, id: \.self) { ing in
                        Text(ing).font(.callout)
                    }
                }
            }

            if !parsed.instructions.isEmpty {
                Section("Instructions (\(parsed.instructions.count) steps)") {
                    ForEach(Array(parsed.instructions.enumerated()), id: \.offset) { idx, step in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(idx + 1).")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 20, alignment: .trailing)
                            Text(step).font(.callout)
                        }
                    }
                }
            }

            if !parsed.sourceUrl.isEmpty {
                Section("Source") {
                    Text(parsed.sourceName.isEmpty ? parsed.sourceUrl : parsed.sourceName)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = errorMessage {
                Section {
                    Text(error).foregroundStyle(.red).font(.callout)
                }
            }
        }
        .navigationTitle("Review Recipe")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isSaving)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(parsed.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .task {
            duplicates = await vm.checkDuplicate(
                title: parsed.title, sourceUrl: parsed.sourceUrl,
                token: auth.accessToken ?? ""
            )
        }
    }

    private func save() async {
        guard let token = auth.accessToken else { return }
        isSaving = true
        errorMessage = nil
        do {
            let recipe = try await vm.confirmImport(parsed, token: token)
            onSuccess(recipe)
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }
}

// Small helper for optional Int text fields
private struct OptionalIntField: View {
    let placeholder: String
    @Binding var value: Int?

    init(_ placeholder: String, value: Binding<Int?>) {
        self.placeholder = placeholder
        self._value = value
    }

    var body: some View {
        TextField(placeholder, text: Binding(
            get: { value.map { String($0) } ?? "" },
            set: { value = Int($0) }
        ))
        .keyboardType(.numberPad)
        .multilineTextAlignment(.trailing)
        .frame(width: 80)
    }
}

// MARK: - Import Draft Sheet (opened via deep link from shortcut)

struct RecipeImportDraftSheet: View {
    @EnvironmentObject var auth: AuthManager
    let importId: String
    let onSuccess: (Recipe) -> Void

    @StateObject private var vm = RecipesViewModel()
    @State private var parsed: ParsedRecipeData?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading recipe…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let p = parsed {
                    RecipeImportReviewView(vm: vm, parsed: p, onSuccess: onSuccess)
                        .environmentObject(auth)
                } else {
                    ContentUnavailableView {
                        Label("Draft Expired", systemImage: "clock.badge.xmark")
                    } description: {
                        Text(errorMessage ?? "This import link has expired. Please import the recipe again.")
                    }
                }
            }
            .navigationTitle("Review Recipe")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await loadDraft() }
    }

    private func loadDraft() async {
        guard let token = auth.accessToken else { isLoading = false; return }
        do {
            parsed = try await APIClient.shared.get(
                "/recipes/import/draft/\(importId)/", token: token
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Filter Bar

struct FilterBar: View {
    @ObservedObject var vm: RecipesViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Dietary filters
                ForEach(DietaryFilter.allCases) { filter in
                    FilterChip(
                        label: filter.rawValue,
                        isSelected: vm.dietaryFilter == filter
                    ) {
                        vm.dietaryFilter = filter
                    }
                }

                if !vm.categories.isEmpty {
                    Divider().frame(height: 24)

                    // Category chips
                    FilterChip(label: "All Categories", isSelected: vm.selectedCategoryId == nil) {
                        vm.selectedCategoryId = nil
                    }
                    ForEach(vm.categories) { cat in
                        FilterChip(
                            label: cat.displayName,
                            isSelected: vm.selectedCategoryId == cat.id
                        ) {
                            vm.selectedCategoryId = cat.id
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.systemGray6), in: Capsule())
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recipe Row

struct RecipeRow: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 12) {
            RecipeThumbnail(url: recipe.photoUrl)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(recipe.title)
                        .font(.headline)
                        .lineLimit(1)
                    if recipe.isFavorite {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                HStack(spacing: 10) {
                    if let time = recipe.totalTime {
                        Label("\(time) min", systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if recipe.timesCooked > 0 {
                        Text("Made \(recipe.timesCooked)×")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let rating = recipe.rating {
                        StarRating(rating: rating, size: 10)
                    }
                }

                dietBadges
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    var dietBadges: some View {
        let badges = [
            recipe.isVegetarian == true ? "V" : nil,
            recipe.isVegan == true ? "VG" : nil,
            recipe.isGlutenFree == true ? "GF" : nil,
            recipe.isDairyFree == true ? "DF" : nil,
        ].compactMap { $0 }

        if !badges.isEmpty {
            HStack(spacing: 4) {
                ForEach(badges, id: \.self) { DietBadge($0) }
            }
        }
    }
}

struct RecipeThumbnail: View {
    let url: String?

    var body: some View {
        Group {
            if let urlString = url, let imageURL = URL(string: urlString) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholderView
                    default:
                        Color(.systemGray5)
                    }
                }
            } else {
                placeholderView
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    var placeholderView: some View {
        Color(.systemGray5)
            .overlay(
                Image(systemName: "fork.knife")
                    .foregroundStyle(.tertiary)
            )
    }
}

struct DietBadge: View {
    let label: String
    init(_ label: String) { self.label = label }
    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.green)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.green, lineWidth: 1))
    }
}

struct StarRating: View {
    let rating: Int
    var size: CGFloat = 14

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= rating ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(i <= rating ? Color.yellow : Color(.tertiaryLabel))
            }
        }
    }
}
