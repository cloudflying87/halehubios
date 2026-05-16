import Foundation

struct ShoppingList: Identifiable, Codable, Sendable {
    let id: UUID
    let name: String
    let store: String?
    let visibility: String
    let createdAt: Date?
    let updatedAt: Date?
    let itemCount: Int
    let checkedCount: Int
    let items: [ShoppingItem]?

    var uncheckedCount: Int { itemCount - checkedCount }
    var isFullyChecked: Bool { itemCount > 0 && checkedCount == itemCount }
}

struct ShoppingItem: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var quantity: String?
    var notes: String?
    var isChecked: Bool
    let checkedAt: Date?
    let order: Int
    let addedByName: String?
    let checkedByName: String?
}

struct AddItemRequest: Encodable, Sendable {
    let name: String
    let quantity: String
    let notes: String
}

struct ToggleResponse: Decodable, Sendable {
    let id: UUID
    let isChecked: Bool
    let checkedAt: Date?
}

struct CreateShoppingListRequest: Encodable, Sendable {
    let name: String
    let store: String?
}
