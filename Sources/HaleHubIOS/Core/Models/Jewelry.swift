import Foundation

struct JewelryPiece: Identifiable, Codable, Sendable, Hashable {
    let id: String
    let title: String
    let description: String
    let categoryId: String?
    let categoryName: String
    let estimatedValue: Double?
    let storageLocation: String
    let acquiredDate: String?   // "YYYY-MM-DD"
    let acquiredNotes: String
    let photo1Url: String?
    let photo2Url: String?
    let photo3Url: String?
    let isArchived: Bool
    let createdAt: String?

    var photoUrls: [String] { [photo1Url, photo2Url, photo3Url].compactMap { $0 } }
}

struct JewelryCategory: Identifiable, Codable, Sendable, Hashable {
    let id: String
    let name: String
    let order: Int?
}

struct JewelryReport: Codable, Sendable {
    let categories: [JewelryReportCategory]
    let totalCount: Int
    let totalValue: Double
}

struct JewelryReportCategory: Codable, Sendable, Identifiable {
    var id: String { category }
    let category: String
    let count: Int
    let value: Double
}

/// Create/update payload — APIClient converts camelCase → snake_case.
struct JewelryPieceRequest: Encodable, Sendable {
    let title: String
    let categoryId: String?
    let description: String
    let estimatedValue: Double?
    let storageLocation: String
    let acquiredDate: String?
    let acquiredNotes: String
}

struct JewelryCategoryRequest: Encodable, Sendable {
    let name: String
}
