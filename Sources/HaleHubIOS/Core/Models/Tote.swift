import Foundation

// MARK: - Tote list item (returned by GET /api/totes/)

struct Tote: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let location: String
    let locationNotes: String
    let itemCount: Int
    let dateSorted: String?   // "YYYY-MM-DD"
    let qrCodeIdentifier: String?
    let notes: String
    let photo1Url: String?
    let photo2Url: String?
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
    let photo1Url: String?
    let photo2Url: String?
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
    let createdAt: Date?   // optional — some items may lack a created_at timestamp
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

// MARK: - Scan response (GET /api/totes/scan/{identifier}/)

struct ToteScanResponse: Decodable, Sendable {
    let bound: Bool
    let claimedByOtherUser: Bool?
    // Present when bound == true
    let id: String?
    let name: String?
    let location: String?
    let locationNotes: String?
    let itemCount: Int?
    let dateSorted: String?
    let qrCodeIdentifier: String?
    let notes: String?
    let photo1Url: String?
    let photo2Url: String?

    func asTote() -> Tote? {
        guard bound, let id, let name, let location,
              let locationNotes, let itemCount, let notes else { return nil }
        return Tote(id: id, name: name, location: location,
                    locationNotes: locationNotes, itemCount: itemCount,
                    dateSorted: dateSorted, qrCodeIdentifier: qrCodeIdentifier,
                    notes: notes, photo1Url: photo1Url, photo2Url: photo2Url)
    }
}

// MARK: - Request body for PATCH /api/totes/{id}/

struct EditToteRequest: Encodable, Sendable {
    let name: String
    let location: String
    let locationNotes: String
    let notes: String
}

// MARK: - Request body for POST /api/totes/

struct CreateToteRequest: Encodable, Sendable {
    let name: String
    let location: String
    let locationNotes: String
    let notes: String
    let qrCodeIdentifier: String?
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
