import Foundation

// MARK: - Tote list item (returned by GET /api/totes/)

/// `location` is the legacy slug. `locationObjId` + `locationName` are the
/// new FK fields — prefer those for display and updates. Both are returned
/// in every tote response after the May 2026 backend migration.
struct Tote: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let location: String            // legacy slug — backwards compat
    let locationObjId: String?      // NEW: ToteLocation uuid
    let locationName: String?       // NEW: display name from the FK
    let locationNotes: String
    let itemCount: Int
    let dateSorted: String?         // "YYYY-MM-DD"
    let dateMoved: String?          // NEW
    let qrCodeIdentifier: String?
    let notes: String
    let isArchived: Bool?           // NEW (optional — detail-only on some payloads)
    let photo1Url: String?
    let photo2Url: String?

    /// Prefer the FK display name when present; fall back to the legacy slug label.
    var displayLocation: String {
        if let n = locationName, !n.isEmpty { return n }
        return Tote.locationLabel(for: location)
    }
}

// MARK: - Tote detail with items (returned by GET /api/totes/{id}/)

struct ToteDetail: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let location: String
    let locationObjId: String?
    let locationName: String?
    let locationNotes: String
    let itemCount: Int
    let dateSorted: String?
    let dateMoved: String?
    let qrCodeIdentifier: String?
    let notes: String
    let isArchived: Bool?
    let photo1Url: String?
    let photo2Url: String?
    let items: [ToteItem]

    var displayLocation: String {
        if let n = locationName, !n.isEmpty { return n }
        return Tote.locationLabel(for: location)
    }
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
    let order: Int?
    let isActive: Bool?
    let itemTypes: [ToteItemType]

    static func == (lhs: ToteCategory, rhs: ToteCategory) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct ToteItemType: Identifiable, Codable, Sendable, Hashable, Equatable {
    let id: String
    let name: String
    let order: Int?
    let isActive: Bool?

    static func == (lhs: ToteItemType, rhs: ToteItemType) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Location (new model — GET /api/totes/locations/)

struct ToteLocation: Identifiable, Codable, Sendable, Hashable {
    let id: String
    let name: String
    let slug: String
    let order: Int
    let isActive: Bool
    let toteCount: Int
}

// MARK: - Scan response (GET /api/totes/scan/{identifier}/)

struct ToteScanResponse: Decodable, Sendable {
    let bound: Bool
    let claimedByOtherUser: Bool?
    // Present when bound == true — full tote payload (location FK fields too)
    let id: String?
    let name: String?
    let location: String?
    let locationObjId: String?
    let locationName: String?
    let locationNotes: String?
    let itemCount: Int?
    let dateSorted: String?
    let dateMoved: String?
    let qrCodeIdentifier: String?
    let notes: String?
    let isArchived: Bool?
    let photo1Url: String?
    let photo2Url: String?

    func asTote() -> Tote? {
        guard bound, let id, let name, let location,
              let locationNotes, let itemCount, let notes else { return nil }
        return Tote(
            id: id, name: name,
            location: location,
            locationObjId: locationObjId,
            locationName: locationName,
            locationNotes: locationNotes,
            itemCount: itemCount,
            dateSorted: dateSorted,
            dateMoved: dateMoved,
            qrCodeIdentifier: qrCodeIdentifier,
            notes: notes,
            isArchived: isArchived,
            photo1Url: photo1Url,
            photo2Url: photo2Url,
        )
    }
}

// MARK: - Request body for PATCH /api/totes/{id}/
//
// Accepts any subset — set only the fields you want to change. The
// backend treats `nil` as "leave alone". Sending both `locationObjId`
// and the legacy `location` slug is fine; the FK wins.

struct EditToteRequest: Encodable, Sendable {
    let name: String?
    let locationObjId: String?
    let location: String?           // legacy slug fallback
    let locationNotes: String?
    let notes: String?
    let dateSorted: String?         // "YYYY-MM-DD"
    let dateMoved: String?

    init(
        name: String? = nil,
        locationObjId: String? = nil,
        location: String? = nil,
        locationNotes: String? = nil,
        notes: String? = nil,
        dateSorted: String? = nil,
        dateMoved: String? = nil
    ) {
        self.name = name
        self.locationObjId = locationObjId
        self.location = location
        self.locationNotes = locationNotes
        self.notes = notes
        self.dateSorted = dateSorted
        self.dateMoved = dateMoved
    }
}

// MARK: - Request body for POST /api/totes/

struct CreateToteRequest: Encodable, Sendable {
    let name: String
    let locationObjId: String?       // preferred — uuid from /api/totes/locations/
    let location: String?            // legacy slug — keep for fallback
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

// MARK: - Request body for POST /api/totes/locations/ + categories/ + item-types/

struct CreateLocationRequest: Encodable, Sendable {
    let name: String
    let order: Int?
}

struct EditLocationRequest: Encodable, Sendable {
    let name: String?
    let order: Int?
    let isActive: Bool?
}

struct CreateCategoryRequest: Encodable, Sendable {
    let name: String
    let order: Int?
}

struct EditCategoryRequest: Encodable, Sendable {
    let name: String?
    let order: Int?
    let isActive: Bool?
}

struct CreateItemTypeRequest: Encodable, Sendable {
    let name: String
    let order: Int?
}

struct EditItemTypeRequest: Encodable, Sendable {
    let name: String?
    let categoryId: String?
    let order: Int?
    let isActive: Bool?
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
