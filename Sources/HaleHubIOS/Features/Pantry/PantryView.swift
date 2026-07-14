import SwiftUI

/// How the pantry list is sectioned.
enum PantryGroupMode: String, CaseIterable, Identifiable, Sendable {
    case location
    case category

    var id: String { rawValue }
    var label: String { self == .location ? "By Location" : "By Category" }
}

// MARK: - ViewModel

@MainActor
class PantryViewModel: ObservableObject {
    @Published var items: [PantryItem] = []
    @Published var locations: [PantryLocation] = []
    @Published var categories: [PantryCategory] = []
    @Published var isLoading = false
    @Published var error: String?

    var lowCount: Int { items.filter(\.isLow).count }
    var expiringCount: Int { items.filter { $0.isExpired || $0.expiresSoon }.count }

    func load(token: String) async {
        isLoading = true
        error = nil
        do {
            // Follow pagination — a real pantry can exceed one 100-item page.
            async let itemsTask: [PantryItem] = Self.fetchAll("/pantry/items/", token: token)
            async let locTask: [PantryLocation] = Self.fetchAll("/pantry/locations/", token: token)
            async let catTask: [PantryCategory] = Self.fetchAll("/pantry/categories/", token: token)
            let (allItems, allLoc, allCat) = try await (itemsTask, locTask, catTask)
            items = allItems
            locations = allLoc
            categories = allCat
        } catch is CancellationError {
            // View disappeared — keep existing data, no error
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    /// Fetch every page of a paginated list endpoint.
    static func fetchAll<T: Decodable & Sendable>(_ path: String, token: String) async throws -> [T] {
        var all: [T] = []
        var page = 1
        while true {
            let sep = path.contains("?") ? "&" : "?"
            let resp: PaginatedResponse<T> =
                try await APIClient.shared.get("\(path)\(sep)page=\(page)", token: token)
            all.append(contentsOf: resp.results)
            if resp.next == nil { break }
            page += 1
        }
        return all
    }

    // MARK: Managed taxonomies (categories + locations)

    /// Refresh just the category/location lists (e.g. after managing them).
    func loadTaxa(token: String) async {
        do {
            async let locTask: [PantryLocation] = Self.fetchAll("/pantry/locations/", token: token)
            async let catTask: [PantryCategory] = Self.fetchAll("/pantry/categories/", token: token)
            let (allLoc, allCat) = try await (locTask, catTask)
            locations = allLoc
            categories = allCat
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func store(_ kind: PantryTaxonKind, _ taxa: [PantryTaxon]) {
        let sorted = taxa.sorted {
            $0.order != $1.order ? $0.order < $1.order
                : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        if kind == .category { categories = sorted } else { locations = sorted }
    }

    private func current(_ kind: PantryTaxonKind) -> [PantryTaxon] {
        kind == .category ? categories : locations
    }

    @discardableResult
    func createTaxon(kind: PantryTaxonKind, name: String, icon: String, token: String) async -> PantryTaxon? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        do {
            let body = PantryTaxonRequest(name: trimmed, icon: icon.isEmpty ? nil : icon)
            let saved: PantryTaxon = try await APIClient.shared.post(kind.path, body: body, token: token)
            // POST is idempotent per-family name, so replace-or-insert by id.
            var list = current(kind).filter { $0.id != saved.id }
            list.append(saved)
            store(kind, list)
            return saved
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    func renameTaxon(kind: PantryTaxonKind, id: String, name: String, icon: String, token: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            let body = PantryTaxonRequest(name: trimmed, icon: icon)
            let saved: PantryTaxon = try await APIClient.shared.patch("\(kind.path)\(id)/", body: body, token: token)
            store(kind, current(kind).map { $0.id == id ? saved : $0 })
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteTaxon(kind: PantryTaxonKind, id: String, token: String) async {
        do {
            try await APIClient.shared.delete("\(kind.path)\(id)/", token: token)
            store(kind, current(kind).filter { $0.id != id })
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Insert a newly created item, or replace an existing one by id (the create
    /// endpoint returns the existing row on a duplicate name).
    func upsert(_ item: PantryItem) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = item
        } else {
            items.append(item)
        }
        items.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func delete(_ item: PantryItem, token: String) async {
        do {
            try await APIClient.shared.delete("/pantry/items/\(item.id)/", token: token)
            items.removeAll { $0.id == item.id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Toggle the running-low flag with an optimistic update.
    func toggleLow(_ item: PantryItem, token: String) async {
        do {
            let updated: PantryItem = try await APIClient.shared.patch(
                "/pantry/items/\(item.id)/",
                body: PantryItemRequest(isLow: !item.isLow),
                token: token
            )
            upsert(updated)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Add every running-low item to a shopping list (existing or new).
    @discardableResult
    func addLowToList(targetListId: String?, newListName: String?, token: String) async -> Int? {
        await post(
            "/pantry/add-low-to-list/",
            PantryAddToListRequest(targetListId: targetListId, newListName: newListName),
            token: token
        )
    }

    /// Add a single pantry item to a shopping list (existing or new).
    @discardableResult
    func addItemToList(_ item: PantryItem, targetListId: String?, newListName: String?, token: String) async -> Int? {
        await post(
            "/pantry/items/\(item.id)/add-to-list/",
            PantryAddToListRequest(targetListId: targetListId, newListName: newListName),
            token: token
        )
    }

    private func post(_ path: String, _ body: PantryAddToListRequest, token: String) async -> Int? {
        do {
            let resp: PantryAddToListResponse = try await APIClient.shared.post(path, body: body, token: token)
            return resp.added
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    /// Shopping lists the user can add pantry items into.
    func loadShoppingLists(token: String) async -> [ShoppingList] {
        (try? await Self.fetchAll("/shopping/", token: token)) ?? []
    }
}

// MARK: - Main view

struct PantryView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = PantryViewModel()

    @State private var searchText = ""
    @State private var showExpiringOnly = false
    @State private var groupMode: PantryGroupMode = .location
    @State private var categoryFilter: String?   // nil = all, "" = uncategorized, else category UUID
    @State private var editingItem: PantryItem?
    @State private var showCreate = false
    @State private var showScanner = false
    @State private var showAddLow = false
    @State private var addToListItem: PantryItem?
    @State private var managingKind: PantryTaxonKind?

    /// Section key for an item under the current grouping mode.
    private func groupKey(_ item: PantryItem) -> String {
        switch groupMode {
        case .location:
            return item.locationDisplay.isEmpty ? "Pantry" : item.locationDisplay
        case .category:
            if item.categoryName.isEmpty { return "Uncategorized" }
            return item.categoryIcon.isEmpty ? item.categoryName
                : "\(item.categoryIcon) \(item.categoryName)"
        }
    }

    private var visibleGroups: [(key: String, items: [PantryItem])] {
        let filtered = vm.items.filter { item in
            let matchesSearch = searchText.isEmpty
                || item.name.localizedCaseInsensitiveContains(searchText)
                || item.brand.localizedCaseInsensitiveContains(searchText)
            let matchesExpiring = !showExpiringOnly || item.isExpired || item.expiresSoon
            let matchesCategory: Bool = {
                guard let f = categoryFilter else { return true }
                return f.isEmpty ? (item.category ?? "").isEmpty : item.category == f
            }()
            return matchesSearch && matchesExpiring && matchesCategory
        }
        var order: [String] = []
        var seen = Set<String>()
        for item in filtered where seen.insert(groupKey(item)).inserted {
            order.append(groupKey(item))
        }
        return order.map { key in (key, filtered.filter { groupKey($0) == key }) }
    }

    var body: some View {
        content
            .navigationTitle("Pantry")
            .toolbar { toolbar }
            .searchable(text: $searchText, prompt: "Search pantry")
            .task { await vm.load(token: auth.accessToken ?? "") }
            .refreshable { await vm.load(token: auth.accessToken ?? "") }
            .alert("Error", isPresented: .constant(vm.error != nil && !vm.items.isEmpty)) {
                Button("OK") { vm.error = nil }
            } message: { Text(vm.error ?? "") }
            .sheet(isPresented: $showCreate) {
                PantryItemEditSheet(item: nil, vm: vm) { saved in
                    vm.upsert(saved)
                }
                .environmentObject(auth)
            }
            .sheet(isPresented: $showScanner) {
                PantryScannerSheet(vm: vm) { saved in
                    vm.upsert(saved)
                }
                .environmentObject(auth)
            }
            .sheet(item: $editingItem) { item in
                PantryItemEditSheet(item: item, vm: vm) { saved in
                    vm.upsert(saved)
                }
                .environmentObject(auth)
            }
            .sheet(isPresented: $showAddLow) {
                PantryAddToListSheet(
                    title: "Add Low Items",
                    subtitle: "Add the \(vm.lowCount) item\(vm.lowCount == 1 ? "" : "s") marked running low to a shopping list.",
                    loadLists: { await vm.loadShoppingLists(token: auth.accessToken ?? "") },
                    onSubmit: { target, newName in
                        await vm.addLowToList(targetListId: target, newListName: newName, token: auth.accessToken ?? "")
                    }
                )
            }
            .sheet(item: $addToListItem) { item in
                PantryAddToListSheet(
                    title: "Add to List",
                    subtitle: "Add “\(item.name)” to a shopping list.",
                    loadLists: { await vm.loadShoppingLists(token: auth.accessToken ?? "") },
                    onSubmit: { target, newName in
                        await vm.addItemToList(item, targetListId: target, newListName: newName, token: auth.accessToken ?? "")
                    }
                )
            }
            .sheet(item: $managingKind) { kind in
                NavigationStack {
                    PantryTaxonManagerView(kind: kind, vm: vm)
                        .environmentObject(auth)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { managingKind = nil }
                            }
                        }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.items.isEmpty {
            ProgressView("Loading pantry…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMsg = vm.error, vm.items.isEmpty {
            ContentUnavailableView {
                Label("Couldn't Load Pantry", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMsg)
            } actions: {
                Button("Retry") { Task { await vm.load(token: auth.accessToken ?? "") } }
                    .buttonStyle(.borderedProminent)
            }
        } else if vm.items.isEmpty {
            ContentUnavailableView {
                Label("Pantry Is Empty", systemImage: "cabinet")
            } description: {
                Text("Tap + to add the first item to your pantry.")
            } actions: {
                Button { showCreate = true } label: {
                    Label("Add Item", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            VStack(spacing: 0) {
                controlsBar
                statusBar
                List {
                    ForEach(visibleGroups, id: \.key) { group in
                        Section {
                            ForEach(group.items) { item in
                                Button { editingItem = item } label: {
                                    PantryItemRow(item: item)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        Task { await vm.delete(item, token: auth.accessToken ?? "") }
                                    } label: { Label("Delete", systemImage: "trash") }
                                    Button {
                                        addToListItem = item
                                    } label: { Label("Add to List", systemImage: "cart.badge.plus") }
                                        .tint(.blue)
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        Task { await vm.toggleLow(item, token: auth.accessToken ?? "") }
                                    } label: {
                                        Label(item.isLow ? "In Stock" : "Low",
                                              systemImage: item.isLow ? "checkmark" : "exclamationmark.triangle")
                                    }
                                    .tint(item.isLow ? .green : .orange)
                                }
                            }
                        } header: {
                            Text(group.key).textCase(nil)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    @ViewBuilder
    private var controlsBar: some View {
        VStack(spacing: 8) {
            Picker("Group by", selection: $groupMode) {
                ForEach(PantryGroupMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            // Category filter — only useful when there are categories in play.
            if !vm.categories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        PantryFilterChip(label: "All", systemImage: "line.3.horizontal.decrease",
                                         tint: .accentColor, isSelected: categoryFilter == nil) {
                            categoryFilter = nil
                        }
                        ForEach(vm.categories) { cat in
                            PantryFilterChip(label: cat.name, systemImage: nil,
                                             tint: .accentColor, isSelected: categoryFilter == cat.id) {
                                categoryFilter = (categoryFilter == cat.id) ? nil : cat.id
                            }
                        }
                        PantryFilterChip(label: "Uncategorized", systemImage: nil,
                                         tint: .secondary, isSelected: categoryFilter == "") {
                            categoryFilter = (categoryFilter == "") ? nil : ""
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .padding(.top, 8)
        Divider().padding(.top, 8)
    }

    @ViewBuilder
    private var statusBar: some View {
        if vm.lowCount > 0 || vm.expiringCount > 0 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    PantryFilterChip(
                        label: "Expiring \(vm.expiringCount)",
                        systemImage: "clock.badge.exclamationmark",
                        tint: .orange,
                        isSelected: showExpiringOnly
                    ) { showExpiringOnly.toggle() }

                    if vm.lowCount > 0 {
                        PantryFilterChip(
                            label: "Add \(vm.lowCount) low to list",
                            systemImage: "cart.badge.plus",
                            tint: .accentColor,
                            isSelected: false
                        ) { showAddLow = true }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            Divider()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button { showScanner = true } label: {
                Image(systemName: "text.viewfinder")
            }
            .accessibilityLabel("Scan item")
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button("Add Item", systemImage: "plus") { showCreate = true }
                Button("Scan Item", systemImage: "text.viewfinder") { showScanner = true }
                Divider()
                Button("Manage Categories", systemImage: "square.grid.2x2") { managingKind = .category }
                Button("Manage Locations", systemImage: "mappin.and.ellipse") { managingKind = .location }
            } label: {
                Image(systemName: "plus")
            }
        }
    }
}

// MARK: - Row

struct PantryItemRow: View {
    let item: PantryItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "cabinet.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.name).font(.headline)
                    if !item.categoryName.isEmpty {
                        Text(item.categoryIcon.isEmpty ? item.categoryName
                                : "\(item.categoryIcon) \(item.categoryName)")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray5), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 6) {
                    if !item.brand.isEmpty {
                        Text(item.brand)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !item.quantitySummary.isEmpty {
                        Text(item.quantitySummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 6) {
                    if item.isExpired {
                        PantryBadge(text: "Expired", tint: .red)
                    } else if item.expiresSoon {
                        PantryBadge(text: "Expires soon", tint: .orange)
                    }
                    if item.isLow {
                        PantryBadge(text: "Low", tint: .yellow)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct PantryBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
    }
}

struct PantryFilterChip: View {
    let label: String
    var systemImage: String? = nil
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Label(label, systemImage: systemImage)
                } else {
                    Text(label)
                }
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? tint : tint.opacity(0.15), in: Capsule())
            .foregroundStyle(isSelected ? .white : tint)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Add-to-list sheet (single item or all low items)

/// Pick an existing shopping list or create a new one, then run `onSubmit`.
/// Shared by the single-item swipe and the "add low items" flow.
struct PantryAddToListSheet: View {
    let title: String
    let subtitle: String
    let loadLists: () async -> [ShoppingList]
    let onSubmit: (_ targetListId: String?, _ newListName: String?) async -> Int?

    @Environment(\.dismiss) private var dismiss
    @State private var lists: [ShoppingList] = []
    @State private var newListName = ""
    @State private var isWorking = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            List {
                Section { Text(subtitle).font(.callout).foregroundStyle(.secondary) }

                if !lists.isEmpty {
                    Section("Add to existing list") {
                        ForEach(lists) { list in
                            Button {
                                Task { await submit(targetListId: list.id.uuidString, newListName: nil) }
                            } label: {
                                HStack {
                                    Text(list.name).foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(list.uncheckedCount)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .disabled(isWorking)
                        }
                    }
                }

                Section("Or start a new list") {
                    HStack {
                        TextField("New list name", text: $newListName)
                            .submitLabel(.done)
                            .onSubmit { Task { await submitNew() } }
                        Button("Create") { Task { await submitNew() } }
                            .disabled(newListName.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isWorking)
                }
            }
            .overlay {
                if isWorking {
                    ProgressView().padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .task {
                if !loaded { lists = await loadLists(); loaded = true }
            }
        }
    }

    private func submitNew() async {
        let name = newListName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        await submit(targetListId: nil, newListName: name)
    }

    private func submit(targetListId: String?, newListName: String?) async {
        guard !isWorking else { return }
        isWorking = true
        _ = await onSubmit(targetListId, newListName)
        isWorking = false
        dismiss()
    }
}
