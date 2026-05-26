import Foundation

// MARK: - Tote list item (returned by GET /api/totes/)

struct Tote: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let locationObjId: String?
    let locationName: String?
    let locationNotes: String
    let itemCount: Int
    let dateSorted: String?         // "YYYY-MM-DD"
    let dateMoved: String?
    let qrCodeIdentifier: String?
    let notes: String
    let isArchived: Bool?
    let photo1Url: String?
    let photo2Url: String?

    var displayLocation: String { locationName ?? "" }
}

// MARK: - Tote detail with items (returned by GET /api/totes/{id}/)

struct ToteDetail: Identifiable, Codable, Sendable {
    let id: String
    let name: String
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

    var displayLocation: String { locationName ?? "" }
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
    // Present when bound == true — full tote payload
    let id: String?
    let name: String?
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
        guard bound, let id, let name,
              let locationNotes, let itemCount, let notes else { return nil }
        return Tote(
            id: id, name: name,
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
    let locationNotes: String?
    let notes: String?
    let dateSorted: String?         // "YYYY-MM-DD"
    let dateMoved: String?

    init(
        name: String? = nil,
        locationObjId: String? = nil,
        locationNotes: String? = nil,
        notes: String? = nil,
        dateSorted: String? = nil,
        dateMoved: String? = nil
    ) {
        self.name = name
        self.locationObjId = locationObjId
        self.locationNotes = locationNotes
        self.notes = notes
        self.dateSorted = dateSorted
        self.dateMoved = dateMoved
    }
}

// MARK: - Request body for POST /api/totes/

struct CreateToteRequest: Encodable, Sendable {
    let name: String
    let locationObjId: String?
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

struct CreateToteLocationRequest: Encodable, Sendable {
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

