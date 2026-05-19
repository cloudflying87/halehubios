import Foundation

@MainActor
class ShoppingViewModel: ObservableObject {
    @Published var lists: [ShoppingList] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var cacheDate: Date?

    private let cacheKey = "shopping_lists"

    func load(token: String, isConnected: Bool) async {
        // Load from cache immediately for instant display
        if lists.isEmpty, let cached: [ShoppingList] = await CacheManager.shared.load(key: cacheKey) {
            lists = cached
            cacheDate = await CacheManager.shared.cacheDate(key: cacheKey)
        }
        guard isConnected else { return }

        isLoading = true
        error = nil
        do {
            let response: PaginatedResponse<ShoppingList> = try await APIClient.shared.get("/shopping/", token: token)
            lists = response.results
            cacheDate = Date()
            await CacheManager.shared.save(response.results, key: cacheKey)
        } catch {
            if lists.isEmpty { self.error = error.localizedDescription }
        }
        isLoading = false
    }

    func createList(name: String, store: String, token: String) async {
        let body = CreateShoppingListRequest(name: name, store: store.isEmpty ? nil : store)
        do {
            let newList: ShoppingList = try await APIClient.shared.post("/shopping/", body: body, token: token)
            lists.insert(newList, at: 0)
            await CacheManager.shared.save(lists, key: cacheKey)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

@MainActor
class ShoppingDetailViewModel: ObservableObject {
    @Published var list: ShoppingList?
    @Published var isLoading = false
    @Published var error: String?
    @Published var newItemName = ""
    @Published var newItemQty = ""

    private let listId: UUID

    init(listId: UUID) { self.listId = listId }

    var cacheKey: String { "shopping_\(listId)" }

    @Published var showBulkAdd = false
    @Published var bulkText = ""

    private func parseBulkText(_ text: String) -> [(name: String, qty: String)] {
        text
            .components(separatedBy: .newlines)
            .flatMap { $0.components(separatedBy: ",") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { line in
                // Strip common list markers (•, -, *, etc.)
                let stripped = line.trimmingCharacters(in: CharacterSet(charactersIn: "•-*·›▸▹▪▫").union(.whitespaces))
                // Match "item x2" or "item x 2 lbs" (case-insensitive)
                if let xRange = stripped.range(of: #"\s+[xX×]"#, options: .regularExpression) {
                    let name = String(stripped[stripped.startIndex..<xRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let qty  = String(stripped[xRange.upperBound...])
                                .trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { return (name, qty) }
                }
                return (stripped, "")
            }
    }

    func addBulkItems(token: String) async {
        let items = parseBulkText(bulkText)
        guard !items.isEmpty else { return }
        bulkText = ""
        showBulkAdd = false
        for item in items {
            let body = AddItemRequest(name: item.name, quantity: item.qty, notes: "")
            let _: ShoppingItem? = try? await APIClient.shared.post("/shopping/\(listId)/items/", body: body, token: token)
        }
        await load(token: token, isConnected: true)
    }

    func load(token: String, isConnected: Bool) async {
        if list == nil, let cached: ShoppingList = await CacheManager.shared.load(key: cacheKey) {
            list = cached
        }
        guard isConnected else { return }

        isLoading = true
        do {
            let detail: ShoppingList = try await APIClient.shared.get("/shopping/\(listId)/", token: token)
            list = detail
            await CacheManager.shared.save(detail, key: cacheKey)
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
                updatedAt: current.updatedAt,
                itemCount: current.itemCount,
                checkedCount: current.checkedCount + (items[idx].isChecked ? 1 : -1),
                items: items
            )
        }
        do {
            let _: ShoppingItem = try await APIClient.shared.postEmpty(
                "/shopping/\(listId)/items/\(item.id)/toggle/", token: token
            )
            await load(token: token, isConnected: true)
        } catch {
            await load(token: token, isConnected: true) // revert on failure
        }
    }

    func addItem(token: String) async {
        guard !newItemName.isEmpty else { return }
        let body = AddItemRequest(name: newItemName, quantity: newItemQty, notes: "")
        newItemName = ""
        newItemQty = ""
        do {
            let _: ShoppingItem = try await APIClient.shared.post("/shopping/\(listId)/items/", body: body, token: token)
            await load(token: token, isConnected: true)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteItem(_ item: ShoppingItem, token: String) async {
        try? await APIClient.shared.delete("/shopping/\(listId)/items/\(item.id)/", token: token)
        await load(token: token, isConnected: true)
    }
}
