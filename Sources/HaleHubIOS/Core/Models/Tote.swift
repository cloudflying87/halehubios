import Foundation

// MARK: - Tote list item (returned by GET /api/totes/)

struct Tote: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let location: String
    let locationNotes: String
    let itemCount: Int
    let dateSorted: String?   // "YYYY-MM-DD"
    let qrCodeIdentifier: String?
    let notes: String
}

// MARK: - Tote detail with items (returned by GET /api/totes/{id}/)

struct ToteDetail: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let location: String
    let locationNotes: String
    let itemCount: Int
    let dateSorted: String?
    let qrCodeIdentifier: String?
    let notes: String
    let items: [ToteItem]
}

// MARK: - Tote item

struct ToteItem: Identifiable, Codable, Sendable {
    let id: String
    let categoryId: String
    let categoryName: String
    let itemTypeId: String
    let itemTypeName: String
    let quantity: String
    let notes: String
    let createdAt: Date
}

// MARK: - Category / item-type hierarchy (returned by GET /api/totes/categories/)

struct ToteCategory: Identifiable, Codable, Sendable, Hashable, Equatable {
    let id: String
    let name: String
    let itemTypes: [ToteItemType]

    static func == (lhs: ToteCategory, rhs: ToteCategory) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct ToteItemType: Identifiable, Codable, Sendable, Hashable, Equatable {
    let id: String
    let name: String

    static func == (lhs: ToteItemType, rhs: ToteItemType) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Request body for POST /api/totes/{id}/items/

struct AddToteItemRequest: Encodable, Sendable {
    let categoryId: String
    let itemTypeId: String
    let quantity: String
    let notes: String
}

// MARK: - Location display helpers

extension Tote {
    /// Human-readable label for the raw `location` slug.
    var locationLabel: String { Tote.locationLabel(for: location) }

    static func locationLabel(for slug: String) -> String {
        switch slug {
        case "basement":        return "Basement"
        case "attic":           return "Attic"
        case "garage":          return "Garage"
        case "storage_unit":    return "Storage Unit"
        case "bedroom_closet":  return "Bedroom Closet"
        case "guest_room":      return "Guest Room"
        case "shed":            return "Shed"
        default:                return "Other"
        }
    }

    /// SF Symbol name that represents the location.
    var locationIcon: String {
        switch location {
        case "basement":        return "stairs"
        case "attic":           return "house.lodge"
        case "garage":          return "car.garage.door"
        case "storage_unit":    return "building.2"
        case "bedroom_closet":  return "door.sliding.right.hand.closed"
        case "guest_room":      return "bed.double"
        case "shed":            return "leaf"
        default:                return "shippingbox"
        }
    }
}
