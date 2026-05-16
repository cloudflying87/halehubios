import SwiftUI

// MARK: - Generate Shopping List Sheet

struct GenerateShoppingListSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    let plan: MealPlan
    @ObservedObject var vm: RecipesViewModel

    @State private var shoppingLists: [ShoppingList] = []
    @State private var selectedListId: String = ""
    @State private var isLoadingLists = false
    @State private var isGenerating = false
    @State private var newListName = ""
    @State private var isCreatingNew = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var generatedList: ShoppingList?

    var body: some View {
        NavigationStack {
            Form {
                if isLoadingLists {
                    Section {
                        HStack {
                            ProgressView().padding(.trailing, 8)
                            Text("Loading lists…").foregroundStyle(.secondary)
                        }
                    }
                } else {
                    // Existing lists picker
                    if !shoppingLists.isEmpty {
                        Section("Choose a Shopping List") {
                            ForEach(shoppingLists) { list in
                                Button {
                                    selectedListId = list.id.uuidString
                                    isCreatingNew = false
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(list.name).foregroundStyle(.primary)
                                            Text("\(list.itemCount) items")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if selectedListId == list.id.uuidString && !isCreatingNew {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(Color.accentColor)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }

                            Button {
                                isCreatingNew = true
                                selectedListId = ""
                            } label: {
                                HStack {
                                    Label("Create New List", systemImage: "plus.circle")
                                    Spacer()
                                    if isCreatingNew {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Create new list inline
                    if isCreatingNew || shoppingLists.isEmpty {
                        Section("New List Name") {
                            TextField("e.g. Weekly Groceries", text: $newListName)
                                .autocorrectionDisabled()
                        }
                    }
                }

                // Success / error
                if let success = successMessage {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(success)
                                .foregroundStyle(.green)
                                .font(.callout)
                            if let list = generatedList {
                                NavigationLink(destination: ShoppingListDetailView(list: list).environmentObject(auth)) {
                                    Label("View Shopping List", systemImage: "cart")
                                        .font(.callout.bold())
                                }
                            }
                        }
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.callout)
                    }
                }
            }
            .navigationTitle("Generate Shopping List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isGenerating {
                        ProgressView()
                    } else {
                        Button("Generate") {
                            Task { await performGenerate() }
                        }
                        .disabled(generateButtonDisabled)
                    }
                }
            }
            .task { await loadLists() }
        }
    }

    private var generateButtonDisabled: Bool {
        if isCreatingNew || shoppingLists.isEmpty {
            return newListName.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return selectedListId.isEmpty
    }

    private func loadLists() async {
        guard let token = auth.accessToken else { return }
        isLoadingLists = true
        do {
            let response: PaginatedResponse<ShoppingList> = try await APIClient.shared.get("/shopping/", token: token)
            shoppingLists = response.results
            if let first = shoppingLists.first {
                selectedListId = first.id.uuidString
            } else {
                isCreatingNew = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingLists = false
    }

    private func performGenerate() async {
        guard let token = auth.accessToken else { return }
        errorMessage = nil
        isGenerating = true

        do {
            var listId = selectedListId

            // Create a new list first if needed
            if isCreatingNew || shoppingLists.isEmpty {
                let trimmed = newListName.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { isGenerating = false; return }
                let body = CreateShoppingListRequest(name: trimmed, store: nil)
                let created: ShoppingList = try await APIClient.shared.post("/shopping/", body: body, token: token)
                listId = created.id.uuidString
            }

            let result = try await vm.generateShoppingList(
                planId: plan.id.uuidString, listId: listId, token: token
            )
            generatedList = result
            let addedCount = result.itemCount
            let listName = result.name
            successMessage = "Added \(addedCount) item\(addedCount == 1 ? "" : "s") to \(listName)"
        } catch {
            errorMessage = error.localizedDescription
        }
        isGenerating = false
    }
}

// MARK: - Add Side Sheet

struct AddSideSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    let entry: MealPlanEntry
    @ObservedObject var vm: RecipesViewModel

    @State private var searchText = ""
    @State private var isAdding = false
    @State private var errorMessage: String?

    var filteredRecipes: [Recipe] {
        if searchText.isEmpty { return vm.recipes }
        return vm.recipes.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
                if isAdding {
                    Section {
                        HStack {
                            ProgressView().padding(.trailing, 8)
                            Text("Adding side…").foregroundStyle(.secondary)
                        }
                    }
                }
                ForEach(filteredRecipes) { recipe in
                    Button {
                        Task { await addSide(recipe: recipe) }
                    } label: {
                        HStack(spacing: 12) {
                            RecipeThumbnail(url: recipe.photoUrl)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(recipe.title)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                if let time = recipe.totalTime {
                                    Text("\(time) min")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isAdding)
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Search recipes…")
            .navigationTitle("Add a Side")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func addSide(recipe: Recipe) async {
        guard let token = auth.accessToken else { return }
        isAdding = true
        errorMessage = nil
        do {
            try await vm.addSideToEntry(
                entryId: entry.id.uuidString,
                recipeId: recipe.id.uuidString,
                token: token
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isAdding = false
    }
}

// MARK: - Meals Hub (root of the Meals tab)

struct MealsHubView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = RecipesViewModel()

    var body: some View {
        List {
            Section {
                NavigationLink(destination: RecipesListView().environmentObject(auth)) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Recipes").font(.headline)
                            Text("Browse and search all recipes")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "book.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }

                NavigationLink(destination: MealPlanView(vm: vm).environmentObject(auth)) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("This Week").font(.headline)
                            if let plan = vm.activeMealPlan, let entries = plan.entries, !entries.isEmpty {
                                Text("\(entries.count) meals planned")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("View the weekly meal plan")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: "calendar")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
        .navigationTitle("Meals")
        .task { await vm.load(token: auth.accessToken ?? "") }
    }
}

// MARK: - Meal Plan View

struct MealPlanView: View {
    @EnvironmentObject var auth: AuthManager
    @ObservedObject var vm: RecipesViewModel

    var body: some View {
        Group {
            if vm.isLoading {
                ProgressView("Loading meal plan…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let plan = vm.activeMealPlan {
                MealPlanContent(plan: plan, vm: vm)
            } else {
                ContentUnavailableView(
                    "No Meal Plan",
                    systemImage: "fork.knife.circle",
                    description: Text("Set up a meal plan on the website.")
                )
            }
        }
        .navigationTitle("This Week")
        .refreshable { await vm.load(token: auth.accessToken ?? "") }
    }
}

// MARK: - Meal Plan Content

struct MealPlanContent: View {
    let plan: MealPlan
    @ObservedObject var vm: RecipesViewModel
    @EnvironmentObject private var auth: AuthManager
    @State private var showGenerateSheet = false

    var hasDates: Bool {
        plan.entries?.contains(where: { $0.date != nil }) == true
    }

    var body: some View {
        List {
            // Shopping list generation button
            Section {
                Button {
                    showGenerateSheet = true
                } label: {
                    Label("Generate Shopping List", systemImage: "cart.badge.plus")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }

            // Plan header
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.displayName).font(.headline)
                    if let start = plan.startDate, let end = plan.endDate {
                        Text("\(start, style: .date) – \(end, style: .date)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    let entryCount = plan.entries?.count ?? 0
                    Text("\(entryCount) meal\(entryCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            if hasDates {
                DayGroupedEntries(plan: plan, vm: vm)
            } else {
                MealTypeGroupedEntries(plan: plan, vm: vm)
            }
        }
        .sheet(isPresented: $showGenerateSheet) {
            GenerateShoppingListSheet(plan: plan, vm: vm)
                .environmentObject(auth)
        }
    }
}

// MARK: - Day-Grouped (when entries have dates)

struct DayGroupedEntries: View {
    let plan: MealPlan
    @ObservedObject var vm: RecipesViewModel

    var days: [(Date, [MealPlanEntry])] {
        guard let entries = plan.entries else { return [] }
        let withDates = entries.filter { $0.date != nil }
        let grouped = Dictionary(grouping: withDates) { entry -> Date in
            Calendar.current.startOfDay(for: entry.date!)
        }
        return grouped.sorted { $0.key < $1.key }
    }

    var body: some View {
        ForEach(days, id: \.0) { date, entries in
            Section {
                ForEach(entries) { entry in
                    MealEntryRow(entry: entry, vm: vm)
                }
            } header: {
                DayHeader(date: date)
            }
        }
    }
}

struct DayHeader: View {
    let date: Date
    var isToday: Bool { Calendar.current.isDateInToday(date) }
    var isTomorrow: Bool { Calendar.current.isDateInTomorrow(date) }

    var label: String {
        if isToday { return "Today" }
        if isTomorrow { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide).month().day())
    }

    var body: some View {
        HStack {
            Text(label)
            if isToday {
                Text("TODAY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor, in: Capsule())
            }
        }
    }
}

// MARK: - Meal-Type Grouped (fallback when no dates)

struct MealTypeGroupedEntries: View {
    let plan: MealPlan
    @ObservedObject var vm: RecipesViewModel

    private let mealOrder = ["breakfast", "lunch", "dinner", "snack", ""]

    var grouped: [(String, [MealPlanEntry])] {
        guard let entries = plan.entries else { return [] }
        return mealOrder.compactMap { type in
            let group = entries.filter { ($0.mealType ?? "") == type }
            guard !group.isEmpty else { return nil }
            return (type.isEmpty ? "Other" : type.capitalized, group)
        }
    }

    var body: some View {
        ForEach(grouped, id: \.0) { label, entries in
            Section(label) {
                ForEach(entries) { entry in
                    MealEntryRow(entry: entry, vm: vm)
                }
            }
        }
    }
}

// MARK: - Meal Entry Row

struct MealEntryRow: View {
    let entry: MealPlanEntry
    @ObservedObject var vm: RecipesViewModel
    @EnvironmentObject var auth: AuthManager
    @State private var cooked = false
    @State private var showAddSide = false

    var hasSides: Bool { !(entry.sides?.isEmpty ?? true) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    if let recipe = entry.recipe {
                        NavigationLink(destination: RecipeDetailView(recipe: recipe).environmentObject(auth)) {
                            Text(recipe.title)
                                .font(.body.weight(cooked ? .regular : .medium))
                                .foregroundStyle(cooked ? .secondary : .primary)
                                .strikethrough(cooked)
                        }
                    } else {
                        Text(entry.displayName)
                            .font(.body.weight(.medium))
                            .foregroundStyle(cooked ? .secondary : .primary)
                            .strikethrough(cooked)
                    }

                    // Meal type badge + servings
                    HStack(spacing: 6) {
                        if let mealType = entry.mealType, !mealType.isEmpty {
                            Text(mealType.capitalized)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(.systemGray5), in: Capsule())
                        }
                        if let servings = entry.servingsOverride {
                            Text("Serves \(servings)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                if entry.recipe != nil {
                    Button {
                        withAnimation { cooked.toggle() }
                        if cooked {
                            Task { await vm.markCooked(recipe: entry.recipe!, token: auth.accessToken ?? "") }
                        }
                    } label: {
                        Image(systemName: cooked ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(cooked ? .green : .secondary)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Sides
            if hasSides {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(entry.sides!) { side in
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(side.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task {
                                    guard let token = auth.accessToken else { return }
                                    try? await vm.removeSideFromEntry(
                                        entryId: entry.id.uuidString,
                                        sideId: side.id.uuidString,
                                        token: token
                                    )
                                }
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.leading, 4)
            }

            // "+ side" button
            Button {
                showAddSide = true
            } label: {
                Text("＋ side")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task {
                    guard let token = auth.accessToken else { return }
                    try? await vm.removeFromMealPlan(entryId: entry.id.uuidString, token: token)
                }
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showAddSide) {
            AddSideSheet(entry: entry, vm: vm)
                .environmentObject(auth)
        }
    }
}
