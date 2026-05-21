import SwiftUI

// MARK: - Shopping Session Sheet

struct ShoppingSessionSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    let plan: MealPlan
    @ObservedObject var vm: RecipesViewModel

    enum Stage { case configure, loading, active, complete }
    @State private var stage: Stage = .configure

    // Config (used only at session creation)
    @State private var skipStaples = true
    @State private var skipPantry = false

    // Session state
    @State private var session: ShoppingSession?
    @State private var selectedItemIds: Set<String> = []
    @State private var signatureChanged = false

    // Lists
    @State private var shoppingLists: [ShoppingList] = []
    @State private var selectedListId = ""
    @State private var isLoadingLists = false
    @State private var isCreatingNew = false
    @State private var newListName = ""

    // Actions
    @State private var isDispatching = false
    @State private var errorMessage: String?

    var pendingItems: [ShoppingSessionItem] { session?.pendingItems ?? [] }
    var sentItems: [ShoppingSessionItem] { session?.sentItems ?? [] }
    var selectedCount: Int { selectedItemIds.count }

    var dispatchDisabled: Bool {
        selectedCount == 0 || isDispatching || isLoadingLists ||
        (isCreatingNew ? newListName.trimmingCharacters(in: .whitespaces).isEmpty : selectedListId.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .configure: configureView
                case .loading: loadingView
                case .active: activeView
                case .complete: completeView
                }
            }
        }
        .task { await autoResume() }
    }

    // MARK: Configure View (first time / after reset)

    var configureView: some View {
        Form {
            Section("Filters") {
                Toggle("Skip staples (tsp, tbsp, pinch…)", isOn: $skipStaples)
                Toggle("Skip items I already have", isOn: $skipPantry)
            }
            Section {
                Text("Items will be loaded from all recipes and sides in the meal plan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = errorMessage {
                Section { Text(error).foregroundStyle(.red).font(.callout) }
            }
        }
        .navigationTitle("Shopping List")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Start") { Task { await startSession() } }
            }
        }
    }

    var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading items…").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Shopping List")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
    }

    // MARK: Active View

    var activeView: some View {
        List {
            // Changed plan warning
            if signatureChanged {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Meal plan changed", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.subheadline.bold())
                        Text("Items may not match the current plan. Reset to regenerate.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Reset & Restart") { Task { await resetAndRestart() } }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .tint(.orange)
                    }
                    .padding(.vertical, 4)
                }
            }

            // Summary header
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(pendingItems.count) items remaining")
                            .font(.subheadline.bold())
                        if session?.sentCount ?? 0 > 0 {
                            Text("\(session!.sentCount) already sent")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button(selectedCount == pendingItems.count ? "Deselect All" : "Select All") {
                        if selectedCount == pendingItems.count {
                            selectedItemIds.removeAll()
                        } else {
                            selectedItemIds = Set(pendingItems.map { $0.id.uuidString })
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }

            // Pending items grouped by recipe
            let grouped = groupedPendingItems()
            ForEach(grouped, id: \.0) { source, items in
                Section(source) {
                    ForEach(items) { item in
                        let itemId = item.id.uuidString
                        Button {
                            if selectedItemIds.contains(itemId) {
                                selectedItemIds.remove(itemId)
                            } else {
                                selectedItemIds.insert(itemId)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedItemIds.contains(itemId)
                                    ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedItemIds.contains(itemId)
                                        ? Color.accentColor : Color.secondary)
                                    .font(.title3)
                                Text(item.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if item.isPantryStaple {
                                    Text("staple").font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Already-sent items (collapsed disclosure)
            if !sentItems.isEmpty {
                Section {
                    DisclosureGroup("Already sent (\(sentItems.count))") {
                        ForEach(sentItems) { item in
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.subheadline)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.name).foregroundStyle(.secondary)
                                    if let listName = item.sentToListName {
                                        Text("→ \(listName)")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Destination picker
            if !isLoadingLists {
                Section("Add selected to…") {
                    if !shoppingLists.isEmpty {
                        ForEach(shoppingLists) { list in
                            Button {
                                selectedListId = list.id.uuidString
                                isCreatingNew = false
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(list.name).foregroundStyle(.primary)
                                        Text("\(list.itemCount) items")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedListId == list.id.uuidString && !isCreatingNew {
                                        Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button {
                        isCreatingNew = true; selectedListId = ""
                    } label: {
                        HStack {
                            Label("Create New List", systemImage: "plus.circle")
                            Spacer()
                            if isCreatingNew { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                        }
                    }
                    .buttonStyle(.plain)

                    if isCreatingNew {
                        TextField("List name (e.g. Costco Run)", text: $newListName)
                            .autocorrectionDisabled()
                    }
                }
            }

            if let error = errorMessage {
                Section { Text(error).foregroundStyle(.red).font(.callout) }
            }

            // Mark complete button (when nothing left to select)
            if pendingItems.isEmpty {
                Section {
                    Button("Mark Shopping Complete") { Task { await markComplete() } }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .foregroundStyle(.green)
                }
            }
        }
        .navigationTitle("\(selectedCount) selected")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            ToolbarItem(placement: .primaryAction) {
                if isDispatching { ProgressView() }
                else {
                    Button("Add \(selectedCount)") { Task { await dispatch() } }
                        .disabled(dispatchDisabled)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: Complete View

    var completeView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Shopping list complete!")
                .font(.title2.bold())
            if let s = session {
                Text("\(s.sentCount) items sent across your lists.")
                    .foregroundStyle(.secondary)
            }
            Button("Start Over") { Task { await resetAndRestart() } }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Done")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
        }
    }

    // MARK: Helpers

    func groupedPendingItems() -> [(String, [ShoppingSessionItem])] {
        var order: [String] = []
        var groups: [String: [ShoppingSessionItem]] = [:]
        for item in pendingItems {
            let key = item.recipeSource ?? "Sides & extras"
            if groups[key] == nil { order.append(key); groups[key] = [] }
            groups[key]!.append(item)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    // MARK: Actions

    private func autoResume() async {
        // If a session is already in progress for this plan, skip the configure
        // screen and jump straight to the active items view.
        guard let token = auth.accessToken else { return }
        stage = .loading
        do {
            // Use a GET-style probe: POST with default filters — if session exists,
            // the server returns it unchanged regardless of filter params.
            let s = try await vm.createOrResumeSession(
                planId: plan.id.uuidString,
                skipStaples: skipStaples,
                skipPantry: skipPantry,
                token: token
            )
            // Only auto-jump if the session was already in progress (has items).
            // A brand-new session (created just now) goes to configure so the
            // user can set filters before committing.
            if !s.items.isEmpty {
                session = s
                signatureChanged = s.signatureChanged ?? false
                selectedItemIds = []
                stage = s.isComplete ? .complete : .active
                await loadLists(token: token)
            } else {
                stage = .configure
            }
        } catch {
            // No existing session or network error — show configure
            stage = .configure
        }
    }

    private func startSession() async {
        guard let token = auth.accessToken else { return }
        stage = .loading
        errorMessage = nil
        do {
            let s = try await vm.createOrResumeSession(
                planId: plan.id.uuidString,
                skipStaples: skipStaples,
                skipPantry: skipPantry,
                token: token
            )
            session = s
            signatureChanged = s.signatureChanged ?? false
            selectedItemIds = []   // start unchecked so each store gets only what user picks
            stage = s.isComplete ? .complete : .active
            await loadLists(token: token)
        } catch {
            errorMessage = error.localizedDescription
            stage = .configure
        }
    }

    private func loadLists(token: String) async {
        isLoadingLists = true
        do {
            let response: PaginatedResponse<ShoppingList> = try await APIClient.shared.get("/shopping/", token: token)
            shoppingLists = response.results
            if let first = shoppingLists.first { selectedListId = first.id.uuidString }
            else { isCreatingNew = true }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingLists = false
    }

    private func dispatch() async {
        guard let token = auth.accessToken, !selectedItemIds.isEmpty else { return }
        errorMessage = nil
        isDispatching = true

        do {
            var listId = selectedListId
            if isCreatingNew {
                let trimmed = newListName.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { isDispatching = false; return }
                let body = CreateShoppingListRequest(name: trimmed, store: nil)
                let created: ShoppingList = try await APIClient.shared.post("/shopping/", body: body, token: token)
                listId = created.id.uuidString
                newListName = ""
                isCreatingNew = false
                await loadLists(token: token)
                selectedListId = listId
            }

            let updatedSession = try await vm.dispatchSessionItems(
                planId: plan.id.uuidString,
                itemIds: Array(selectedItemIds),
                listId: listId,
                token: token
            )
            session = updatedSession
            selectedItemIds = []   // clear so next store starts fresh
        } catch {
            errorMessage = error.localizedDescription
        }
        isDispatching = false
    }

    private func markComplete() async {
        guard let token = auth.accessToken else { return }
        do {
            let s = try await vm.completeSession(planId: plan.id.uuidString, token: token)
            session = s
            stage = .complete
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetAndRestart() async {
        guard let token = auth.accessToken else { return }
        do {
            try await vm.resetSession(planId: plan.id.uuidString, token: token)
            session = nil
            selectedItemIds = []
            signatureChanged = false
            stage = .configure
        } catch {
            errorMessage = error.localizedDescription
        }
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
            ShoppingSessionSheet(plan: plan, vm: vm)
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
