import SwiftUI

// To-do lists reuse the exact same backend models as shopping lists
// (List(list_type="todo") + ListItem), so we reuse the `ShoppingList` /
// `ShoppingItem` Swift models and the shared `ItemRow` / `BulkAddSheet` views.
// Endpoints live under /todos/ and omit the store + move features.

// MARK: - List ViewModel

@MainActor
class TodosViewModel: ObservableObject {
    @Published var lists: [ShoppingList] = []
    @Published var isLoading = false
    @Published var error: String?

    func load(token: String) async {
        isLoading = true
        error = nil
        do {
            let response: PaginatedResponse<ShoppingList> =
                try await APIClient.shared.get("/todos/", token: token)
            lists = response.results
        } catch is CancellationError {
            // View disappeared — keep existing data
        } catch {
            if lists.isEmpty { self.error = error.localizedDescription }
        }
        isLoading = false
    }

    func createList(name: String, token: String) async -> ShoppingList? {
        do {
            let body = CreateShoppingListRequest(name: name, store: nil)
            let newList: ShoppingList =
                try await APIClient.shared.post("/todos/", body: body, token: token)
            lists.insert(newList, at: 0)
            return newList
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    func deleteList(id: UUID, token: String) async {
        do {
            try await APIClient.shared.delete("/todos/\(id)/delete/", token: token)
            lists.removeAll { $0.id == id }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Detail ViewModel

@MainActor
class TodoDetailViewModel: ObservableObject {
    @Published var list: ShoppingList?
    @Published var isLoading = false
    @Published var error: String?
    @Published var newItemName = ""
    @Published var newItemQty = ""
    @Published var showDeleteListConfirm = false
    @Published var listDeleted = false
    @Published var showBulkAdd = false
    @Published var bulkText = ""

    private let listId: UUID
    init(listId: UUID) { self.listId = listId }

    func load(token: String) async {
        isLoading = true
        do {
            let detail: ShoppingList = try await APIClient.shared.get("/todos/\(listId)/", token: token)
            list = detail
        } catch {
            if list == nil { self.error = error.localizedDescription }
        }
        isLoading = false
    }

    func toggle(item: ShoppingItem, token: String) async {
        guard let current = list else { return }
        // Optimistic update
        if var items = current.items, let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].isChecked.toggle()
            list = ShoppingList(
                id: current.id, name: current.name, store: current.store,
                visibility: current.visibility, createdAt: current.createdAt,
                updatedAt: current.updatedAt, itemCount: current.itemCount,
                checkedCount: current.checkedCount + (items[idx].isChecked ? 1 : -1),
                items: items
            )
        }
        do {
            let _: ShoppingItem = try await APIClient.shared.postEmpty(
                "/todos/\(listId)/items/\(item.id)/toggle/", token: token)
            await load(token: token)
        } catch {
            await load(token: token) // revert on failure
        }
    }

    func addItem(token: String) async {
        let name = newItemName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let body = AddItemRequest(name: name, quantity: newItemQty, notes: "")
        newItemName = ""
        newItemQty = ""
        do {
            let _: ShoppingItem = try await APIClient.shared.post(
                "/todos/\(listId)/items/", body: body, token: token)
            await load(token: token)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteItem(_ item: ShoppingItem, token: String) async {
        try? await APIClient.shared.delete("/todos/\(listId)/items/\(item.id)/", token: token)
        await load(token: token)
    }

    func addBulkItems(token: String) async {
        let names = bulkText
            .components(separatedBy: .newlines)
            .flatMap { $0.components(separatedBy: ",") }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "•-*·›▸▹▪▫").union(.whitespaces)) }
            .filter { !$0.isEmpty }
        guard !names.isEmpty else { return }
        bulkText = ""
        showBulkAdd = false
        for name in names {
            let body = AddItemRequest(name: name, quantity: "", notes: "")
            let _: ShoppingItem? = try? await APIClient.shared.post(
                "/todos/\(listId)/items/", body: body, token: token)
        }
        await load(token: token)
    }

    func deleteList(token: String) async {
        do {
            try await APIClient.shared.delete("/todos/\(listId)/delete/", token: token)
            listDeleted = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Lists view

struct TodosListView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = TodosViewModel()
    @State private var showCreateSheet = false
    @State private var navigateToNewList: ShoppingList?

    var body: some View {
        Group {
            if vm.isLoading && vm.lists.isEmpty {
                ProgressView("Loading to-dos…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.lists.isEmpty, let error = vm.error {
                ContentUnavailableView("Couldn't Load To-Dos",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(error))
            } else if vm.lists.isEmpty {
                ContentUnavailableView("No To-Do Lists",
                                       systemImage: "checklist",
                                       description: Text("Tap + to create a to-do list."))
            } else {
                List(vm.lists) { list in
                    NavigationLink(destination: TodoDetailView(list: list)) {
                        TodoListRow(list: list)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await vm.deleteList(id: list.id, token: auth.accessToken ?? "") }
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                }
                .refreshable { await vm.load(token: auth.accessToken ?? "") }
            }
        }
        .navigationTitle("To-Do Lists")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showCreateSheet = true } label: { Image(systemName: "plus") }
            }
        }
        .navigationDestination(item: $navigateToNewList) { list in
            TodoDetailView(list: list)
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateTodoListSheet(vm: vm) { newList in navigateToNewList = newList }
                .environmentObject(auth)
        }
        .alert("Error", isPresented: .init(get: { vm.error != nil && !vm.lists.isEmpty },
                                           set: { if !$0 { vm.error = nil } })) {
            Button("OK") { vm.error = nil }
        } message: { Text(vm.error ?? "") }
        .task { await vm.load(token: auth.accessToken ?? "") }
    }
}

struct TodoListRow: View {
    let list: ShoppingList

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(list.name).font(.headline)
                Spacer()
                if list.isFullyChecked && list.itemCount > 0 {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
            Text("\(list.uncheckedCount) of \(list.itemCount) remaining")
                .font(.caption).foregroundStyle(.secondary)
            if list.itemCount > 0 {
                ProgressView(value: Double(list.checkedCount), total: Double(list.itemCount))
                    .tint(list.isFullyChecked ? Color.green : Color.accentColor)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Detail view

struct TodoDetailView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    let list: ShoppingList
    @StateObject private var vm: TodoDetailViewModel

    init(list: ShoppingList) {
        self.list = list
        _vm = StateObject(wrappedValue: TodoDetailViewModel(listId: list.id))
    }

    private var current: ShoppingList { vm.list ?? list }
    private var unchecked: [ShoppingItem] { current.items?.filter { !$0.isChecked } ?? [] }
    private var checked: [ShoppingItem] { current.items?.filter { $0.isChecked } ?? [] }

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Add to-do…", text: $vm.newItemName)
                        .submitLabel(.done)
                        .onSubmit { Task { await vm.addItem(token: auth.accessToken ?? "") } }
                    Button {
                        Task { await vm.addItem(token: auth.accessToken ?? "") }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.accentColor)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.newItemName.isEmpty)
                }
            }

            if !unchecked.isEmpty {
                Section("\(unchecked.count) remaining") {
                    ForEach(unchecked) { item in
                        ItemRow(item: item, isConnected: true) {
                            Task { await vm.toggle(item: item, token: auth.accessToken ?? "") }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await vm.deleteItem(item, token: auth.accessToken ?? "") }
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
            }

            if !checked.isEmpty {
                Section {
                    ForEach(checked) { item in
                        ItemRow(item: item, isConnected: true) {
                            Task { await vm.toggle(item: item, token: auth.accessToken ?? "") }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await vm.deleteItem(item, token: auth.accessToken ?? "") }
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                } header: {
                    Text("\(checked.count) done").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { vm.showBulkAdd = true } label: {
                        Label("Bulk Add", systemImage: "text.badge.plus")
                    }
                    if !checked.isEmpty {
                        Divider()
                        Button(role: .destructive) {
                            Task {
                                for item in checked {
                                    await vm.deleteItem(item, token: auth.accessToken ?? "")
                                }
                            }
                        } label: { Label("Clear Done", systemImage: "trash") }
                    }
                    Divider()
                    Button(role: .destructive) {
                        vm.showDeleteListConfirm = true
                    } label: { Label("Delete List", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .confirmationDialog("Delete \"\(current.name)\"?",
                            isPresented: $vm.showDeleteListConfirm, titleVisibility: .visible) {
            Button("Delete List", role: .destructive) {
                Task { await vm.deleteList(token: auth.accessToken ?? "") }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the list and all its items.")
        }
        .sheet(isPresented: $vm.showBulkAdd) {
            BulkAddSheet(text: $vm.bulkText) {
                Task { await vm.addBulkItems(token: auth.accessToken ?? "") }
            }
        }
        .task { await vm.load(token: auth.accessToken ?? "") }
        .refreshable { await vm.load(token: auth.accessToken ?? "") }
        .onChange(of: vm.listDeleted) { _, deleted in if deleted { dismiss() } }
        .alert("Error", isPresented: .init(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK") {}
        } message: { Text(vm.error ?? "") }
    }
}

// MARK: - Create sheet

struct CreateTodoListSheet: View {
    @EnvironmentObject var auth: AuthManager
    @ObservedObject var vm: TodosViewModel
    let onCreated: (ShoppingList) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var listName = ""
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("List Name", text: $listName)
                }
            }
            .navigationTitle("New To-Do List")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isCreating)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isCreating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isCreating {
                        ProgressView()
                    } else {
                        Button("Create") { Task { await create() } }
                            .disabled(listName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func create() async {
        guard let token = auth.accessToken else { return }
        isCreating = true
        let newList = await vm.createList(
            name: listName.trimmingCharacters(in: .whitespaces), token: token)
        isCreating = false
        if let newList {
            dismiss()
            onCreated(newList)
        }
    }
}
