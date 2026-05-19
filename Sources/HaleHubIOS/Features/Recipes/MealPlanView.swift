import SwiftUI

// MARK: - Generate Shopping List Sheet

struct GenerateShoppingListSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    let plan: MealPlan
    @ObservedObject var vm: RecipesViewModel
    var onNavigate: ((ShoppingList) -> Void)? = nil

    @State private var shoppingLists: [ShoppingList] = []
    @State private var selectedListId: String = ""
    @State private var isLoadingLists = false
    @State private var isGenerating = false
    @State private var newListName = ""
    @State private var isCreatingNew = false
    @State private var skipStaples = true
    @State private var skipPantry = false
    @State private var errorMessage: String?

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

                    Section("Filters") {
                        Toggle("Skip staples (tsp, tbsp, pinch…)", isOn: $skipStaples)
                        Toggle("Skip items I already have", isOn: $skipPantry)
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
                planId: plan.id.uuidString, listId: listId,
                skipStaples: skipStaples, skipPantry: skipPantry,
                token: token
            )
            dismiss()
            onNavigate?(result)
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

// MARK: - Add Text Side Sheet

struct AddTextSideSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    let entry: MealPlanEntry
    @ObservedObject var vm: RecipesViewModel
    @State private var sideName = ""
    @State private var isAdding = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Side dish name") {
                    TextField("e.g. Rice, Garden Salad, Garlic Bread", text: $sideName)
                        .autocorrectionDisabled()
                }
                if let error = errorMessage {
                    Section { Text(error).foregroundStyle(.red).font(.caption) }
                }
            }
            .navigationTitle("Add Text Side")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isAdding { ProgressView() }
                    else {
                        Button("Add") { Task { await addSide() } }
                            .disabled(sideName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func addSide() async {
        guard let token = auth.accessToken else { return }
        isAdding = true
        do {
            try await vm.addTextSideToEntry(
                entryId: entry.id.uuidString,
                name: sideName.trimmingCharacters(in: .whitespaces),
                token: token
            )
            dismiss()
        } catch { errorMessage = error.localizedDescription }
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

                NavigationLink(destination: AllPlansView(vm: vm).environmentObject(auth)) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("All Plans").font(.headline)
                            Text("Browse and create meal plans")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "calendar.badge.clock")
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
    @State private var navigateToShoppingList: ShoppingList? = nil

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
            GenerateShoppingListSheet(plan: plan, vm: vm) { list in
                navigateToShoppingList = list
            }
            .environmentObject(auth)
        }
        .navigationDestination(item: $navigateToShoppingList) { list in
            ShoppingListDetailView(list: list)
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
            Calendar.current.startOfDay(for: entry.date ?? Date())
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
    @State private var showAddTextSide = false

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

                if let recipe = entry.recipe {
                    Button {
                        withAnimation { cooked.toggle() }
                        if cooked {
                            Task { await vm.markCooked(recipe: recipe, token: auth.accessToken ?? "") }
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
            if let sides = entry.sides, !sides.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("with:")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 4)
                    ForEach(sides) { side in
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

            // "+ side" menu
            Menu {
                Button { showAddSide = true } label: {
                    Label("Recipe Side", systemImage: "book")
                }
                Button { showAddTextSide = true } label: {
                    Label("Text Side", systemImage: "text.cursor")
                }
            } label: {
                Text("＋ side")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.accentColor)
            }
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
        .sheet(isPresented: $showAddTextSide) {
            AddTextSideSheet(entry: entry, vm: vm)
                .environmentObject(auth)
        }
    }
}

// MARK: - All Plans

struct AllPlansView: View {
    @EnvironmentObject var auth: AuthManager
    @ObservedObject var vm: RecipesViewModel
    @State private var showCreateSheet = false

    var body: some View {
        Group {
            if vm.isLoadingAllPlans && vm.allPlans.isEmpty {
                ProgressView("Loading plans…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.allPlans.isEmpty {
                ContentUnavailableView("No Meal Plans", systemImage: "calendar.badge.exclamationmark",
                                       description: Text("Tap + to create your first plan."))
            } else {
                List {
                    ForEach(vm.allPlans) { plan in
                        NavigationLink(destination: MealPlanDetailDestination(plan: plan, vm: vm).environmentObject(auth)) {
                            PlanSummaryRow(plan: plan)
                        }
                    }
                }
            }
        }
        .navigationTitle("All Plans")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showCreateSheet = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateMealPlanSheet(vm: vm).environmentObject(auth)
        }
        .task { await vm.loadAllPlans(token: auth.accessToken ?? "") }
        .refreshable { await vm.loadAllPlans(token: auth.accessToken ?? "") }
    }
}

struct PlanSummaryRow: View {
    let plan: MealPlan
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(plan.displayName).font(.body.weight(.medium))
                if plan.isActive {
                    Text("ACTIVE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor, in: Capsule())
                }
            }
            if let start = plan.startDate, let end = plan.endDate {
                Text("\(start, style: .date) – \(end, style: .date)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let count = plan.entryCount {
                Text("\(count) meal\(count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct MealPlanDetailDestination: View {
    @EnvironmentObject var auth: AuthManager
    let plan: MealPlan
    @ObservedObject var vm: RecipesViewModel
    @State private var fullPlan: MealPlan?
    @State private var isLoading = false

    var displayed: MealPlan { fullPlan ?? plan }

    var body: some View {
        MealPlanContent(plan: displayed, vm: vm)
            .navigationTitle(displayed.displayName)
            .task { await reload() }
            .onReceive(vm.$activeMealPlan) { _ in
                // Re-fetch whenever the active plan refreshes (e.g. after adding a side)
                Task { await reload(force: true) }
            }
    }

    private func reload(force: Bool = false) async {
        guard let token = auth.accessToken else { return }
        guard force || fullPlan == nil else { return }
        isLoading = true
        fullPlan = try? await vm.fetchPlanDetail(planId: plan.id, token: token)
        isLoading = false
    }
}

// MARK: - Create Meal Plan Sheet

struct CreateMealPlanSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: RecipesViewModel
    @State private var name = ""
    @State private var useDates = false
    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 6, to: Date()) ?? Date()
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Plan Name") {
                    TextField("e.g. Week of May 19", text: $name)
                        .autocorrectionDisabled()
                }
                Section {
                    Toggle("Set date range", isOn: $useDates)
                    if useDates {
                        DatePicker("Start", selection: $startDate, displayedComponents: .date)
                        DatePicker("End",   selection: $endDate,   displayedComponents: .date)
                    }
                }
                if let error = errorMessage {
                    Section { Text(error).foregroundStyle(.red).font(.caption) }
                }
            }
            .navigationTitle("New Meal Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isCreating { ProgressView() }
                    else {
                        Button("Create") { Task { await create() } }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func create() async {
        guard let token = auth.accessToken else { return }
        isCreating = true
        errorMessage = nil
        do {
            _ = try await vm.createMealPlan(
                name: name.trimmingCharacters(in: .whitespaces),
                startDate: useDates ? startDate : nil,
                endDate: useDates ? endDate : nil,
                token: token
            )
            dismiss()
        } catch { errorMessage = error.localizedDescription }
        isCreating = false
    }
}
