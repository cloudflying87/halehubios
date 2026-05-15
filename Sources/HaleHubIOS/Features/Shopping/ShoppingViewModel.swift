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
        guard var current = list else { return }
        // Optimistic update
        if let idx = current.items?.firstIndex(where: { $0.id == item.id }) {
            var items = current.items!
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
        do {
            // DELETE has no response body — use a raw request via postEmpty workaround
            struct Empty: Decodable {}
            guard let url = URL(string: "https://flyhomemn.com/api/shopping/\(listId)/items/\(item.id)/") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "DELETE"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: req)
            await load(token: token, isConnected: true)
        }
    }
}
