import Foundation

// MARK: - Pantry item (GET /api/pantry/items/, paginated)
//
// Mirrors apps/api/serializers/pantry.py `PantryItemSerializer`. Date fields are
// kept as "YYYY-MM-DD" strings (not Date) because the write DTO sends them back
// verbatim — APIClient's JSON encoder has no date strategy, so a Date would
// serialize as a number and break Django's DateField parsing.

struct PantryItem: Identifiable, Codable, Sendable, Hashable {
    let id: String
    let name: String
    let brand: String
    let category: String?           // PantryCategory UUID, or nil
    let categoryName: String        // read-only display name, or ""
    let categoryIcon: String        // read-only emoji, or ""
    let quantity: Double?
    let quantityText: String
    let unit: String
    let barcode: String
    let imageUrl: String
    let location: String?           // PantryLocation UUID, or nil
    let locationName: String        // simple text fallback ("Pantry", "Fridge", …)
    let locationDisplay: String     // best label: FK name if set, else locationName
    let locationIcon: String        // emoji from the PantryLocation, or ""
    let expirationDate: String?     // "YYYY-MM-DD"
    let purchaseDate: String?       // "YYYY-MM-DD"
    let isLow: Bool
    let isExpired: Bool
    let expiresSoon: Bool
    let autoAddToList: Bool
    let minQuantity: Double?
    let createdAt: Date?
    let updatedAt: Date?

    /// A compact "3 · 16 oz" style detail line, omitting empty parts.
    var quantitySummary: String {
        var parts: [String] = []
        if !quantityText.isEmpty {
            parts.append(quantityText)
        } else if let quantity {
            // Drop a trailing ".0" so 3.0 reads as "3"
            let q = quantity.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(quantity)) : String(quantity)
            parts.append(unit.isEmpty ? q : "\(q) \(unit)")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Managed taxonomy (categories + locations share one shape)
//
// PantryCategory and PantryLocation are identical on the wire — id/name/icon/
// order/item_count — and support the same create/rename/delete lifecycle, so
// one Swift type backs both. See `PantryTaxonKind` for which endpoint each uses.

struct PantryTaxon: Identifiable, Codable, Sendable, Hashable {
    let id: String
    let name: String
    let icon: String
    let order: Int
    let itemCount: Int?

    var displayName: String { icon.isEmpty ? name : "\(icon) \(name)" }
}

typealias PantryLocation = PantryTaxon
typealias PantryCategory = PantryTaxon

/// Body for POST/PATCH on /pantry/categories/ and /pantry/locations/.
struct PantryTaxonRequest: Encodable, Sendable {
    var name: String?
    var icon: String?
    var order: Int?

    init(name: String? = nil, icon: String? = nil, order: Int? = nil) {
        self.name = name
        self.icon = icon
        self.order = order
    }
}

// MARK: - Request body for POST /api/pantry/items/ and PATCH …/<id>/
//
// All fields optional so the same struct serves create and partial-update.
// nil fields are omitted by JSONEncoder, which PATCH treats as "leave alone".

struct PantryItemRequest: Encodable, Sendable {
    var name: String?
    var brand: String?
    var category: String?           // PantryCategory UUID
    var quantity: Double?
    var quantityText: String?
    var unit: String?
    var barcode: String?
    var location: String?           // PantryLocation UUID
    var locationName: String?
    var expirationDate: String?     // "YYYY-MM-DD"
    var purchaseDate: String?       // "YYYY-MM-DD"
    var isLow: Bool?
    var autoAddToList: Bool?
    var minQuantity: Double?

    init(
        name: String? = nil,
        brand: String? = nil,
        category: String? = nil,
        quantity: Double? = nil,
        quantityText: String? = nil,
        unit: String? = nil,
        barcode: String? = nil,
        location: String? = nil,
        locationName: String? = nil,
        expirationDate: String? = nil,
        purchaseDate: String? = nil,
        isLow: Bool? = nil,
        autoAddToList: Bool? = nil,
        minQuantity: Double? = nil
    ) {
        self.name = name
        self.brand = brand
        self.category = category
        self.quantity = quantity
        self.quantityText = quantityText
        self.unit = unit
        self.barcode = barcode
        self.location = location
        self.locationName = locationName
        self.expirationDate = expirationDate
        self.purchaseDate = purchaseDate
        self.isLow = isLow
        self.autoAddToList = autoAddToList
        self.minQuantity = minQuantity
    }
}

// MARK: - Response from POST /api/pantry/items/
//
// The create endpoint returns the item fields flat, plus a `duplicate` flag:
// true (HTTP 200) means an item with that name already existed and the server
// returned it unchanged; false (201) means a fresh create. We decode both out
// of the same object so the UI can react to a duplicate instead of silently
// dropping the user's input.

struct PantryItemCreateResponse: Decodable, Sendable {
    let item: PantryItem
    let duplicate: Bool

    private enum Key: String, CodingKey { case duplicate }

    init(from decoder: Decoder) throws {
        item = try PantryItem(from: decoder)
        let container = try decoder.container(keyedBy: Key.self)
        duplicate = (try? container.decode(Bool.self, forKey: .duplicate)) ?? false
    }
}

// MARK: - Request body for POST /api/pantry/add-low-to-list/
//         and …/items/<id>/add-to-list/

struct PantryAddToListRequest: Encodable, Sendable {
    let targetListId: String?
    let newListName: String?

    init(targetListId: String? = nil, newListName: String? = nil) {
        self.targetListId = targetListId
        self.newListName = newListName
    }
}

// MARK: - Response from the add-to-list endpoints

struct PantryAddToListResponse: Decodable, Sendable {
    let added: Int
}

// MARK: - Barcode lookup (POST /api/pantry/barcode-lookup/)

struct PantryBarcodeLookupRequest: Encodable, Sendable {
    let barcode: String
}

struct PantryBarcodeLookupResponse: Decodable, Sendable {
    let found: Bool
    let barcode: String?
    let product: PantryBarcodeProduct?
}

struct PantryBarcodeProduct: Decodable, Sendable {
    let barcode: String?
    let name: String
    let brand: String
    let quantity: String        // free-text like "500g" — maps to quantityText
    let imageUrl: String
    let locationHint: String?   // "Pantry" | "Fridge" | "Freezer"
}

/// Prefilled values handed to the edit sheet after a barcode scan.
struct PantryItemPrefill: Sendable {
    var name: String = ""
    var brand: String = ""
    var quantityText: String = ""
    var barcode: String = ""
    var locationHint: String = ""

    init(from product: PantryBarcodeProduct) {
        name = product.name
        brand = product.brand
        quantityText = product.quantity
        barcode = product.barcode ?? ""
        locationHint = product.locationHint ?? ""
    }

    /// Fallback when the barcode wasn't found — start from a blank item that
    /// still remembers the scanned code.
    init(barcode: String) {
        self.barcode = barcode
    }

    /// Start from an OCR-scanned (or empty) name — used by the text scanner and
    /// the "add manually" fallback.
    init(name: String = "") {
        self.name = name
    }
}
