import SwiftUI

struct RecipesListView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = RecipesViewModel()
    @State private var showImportURL = false
    @State private var importedRecipe: Recipe?
    @State private var navigateToImported = false

    var body: some View {
        Group {
            if vm.isLoading && vm.recipes.isEmpty {
                ProgressView("Loading recipes…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    FilterBar(vm: vm)
                        .padding(.vertical, 8)
                    Divider()
                    List {
                        ForEach(vm.filtered) { recipe in
                            NavigationLink(destination: RecipeDetailView(recipe: recipe).environmentObject(auth)) {
                                RecipeRow(recipe: recipe)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .navigationDestination(isPresented: $navigateToImported) {
                        if let imported = importedRecipe {
                            RecipeDetailView(recipe: imported).environmentObject(auth)
                        }
                    }
                }
                .searchable(text: $vm.searchQuery, prompt: "Search recipes…")
                .onChange(of: vm.searchQuery) { _, query in
                    let token = auth.accessToken ?? ""
                    Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        await vm.search(query: query, token: token)
                    }
                }
                .refreshable { await vm.load(token: auth.accessToken ?? "") }
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
}

// MARK: - Import Recipe Sheet (URL + Paste Text)

struct ImportRecipeFromURLSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: RecipesViewModel
    let onSuccess: (Recipe) -> Void

    enum ImportMode: String, CaseIterable { case url = "URL", text = "Paste Text" }

    @State private var mode: ImportMode = .url
    @State private var urlText = ""
    @State private var pastedText = ""
    @State private var isImporting = false
    @State private var errorMessage: String?

    private var canImport: Bool {
        switch mode {
        case .url:  return !urlText.trimmingCharacters(in: .whitespaces).isEmpty
        case .text: return !pastedText.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Mode picker
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
                        Text("Paste the recipe — including title, ingredients, and instructions. The more detail you include, the better the import.")
                    }
                }

                if isImporting {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Importing recipe…").foregroundStyle(.secondary)
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
                    Button("Cancel") { dismiss() }.disabled(isImporting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        Task { await performImport() }
                    }
                    .disabled(!canImport || isImporting)
                }
            }
        }
    }

    private func performImport() async {
        guard let token = auth.accessToken else { return }
        isImporting = true
        errorMessage = nil
        do {
            let recipe: Recipe
            switch mode {
            case .url:
                recipe = try await vm.importRecipe(
                    url: urlText.trimmingCharacters(in: .whitespaces),
                    token: token
                )
            case .text:
                recipe = try await vm.importRecipeFromText(
                    pastedText.trimmingCharacters(in: .whitespaces),
                    token: token
                )
            }
            dismiss()
            onSuccess(recipe)
        } catch {
            errorMessage = error.localizedDescription
        }
        isImporting = false
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
