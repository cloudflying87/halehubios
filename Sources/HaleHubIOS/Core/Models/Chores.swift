import Foundation

struct ChoreItem: Codable, Sendable, Identifiable {
    var id: String { choreId }
    let choreId: String
    let name: String
    let done: Bool
}

struct ChoreToday: Codable, Sendable {
    let date: String
    let items: [ChoreItem]
    let required: Int
    let done: Int
    let allDone: Bool
}

struct ChoreWeekSummary: Codable, Sendable {
    let perfectDays: Int
    let daysWithChores: Int
    let totalDone: Int
    let totalRequired: Int
}

struct ChoreChild: Codable, Sendable, Identifiable {
    var id: String { childId }
    let childId: String
    let childName: String
    let today: ChoreToday
    let week: ChoreWeekSummary
}

struct ChoreDashboard: Codable, Sendable {
    let date: String
    let weekStart: String
    let children: [ChoreChild]
}

/// POST body for /chores/<id>/complete/
struct ChoreCompleteRequest: Encodable, Sendable {
    let date: String
    let done: Bool
}
