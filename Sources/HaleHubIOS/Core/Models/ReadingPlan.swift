import Foundation

struct ReadingPlanSummary: Identifiable, Codable, Sendable {
    let id: String  // UUID
    let name: String
    let startDate: String    // "YYYY-MM-DD"
    let endDate: String      // "YYYY-MM-DD"
    let totalDays: Int
    let daysCompleted: Int
    let completionPercentage: Double
    let currentDayNumber: Int?  // nil if plan hasn't started
    let daysBehind: Int?        // negative = ahead, positive = behind, nil = not started
    let isPrimary: Bool
    let isActive: Bool
}

struct ReadingPlanDetail: Codable, Sendable {
    let id: String
    let name: String
    let startDate: String
    let endDate: String
    let totalDays: Int
    let daysCompleted: Int
    let completionPercentage: Double
    let currentDayNumber: Int?
    let daysBehind: Int?
    let isPrimary: Bool
    let isActive: Bool
    let todayDay: ReadingDay?              // current day's full info (nil if not started)
    let recentDays: [ReadingDaySummary]    // 14 days around today
}

struct ReadingDay: Codable, Sendable {
    let dayNumber: Int
    let date: String        // "YYYY-MM-DD"
    let isCompleted: Bool
    let entries: [ReadingEntry]
    let notes: String?      // optional — API may omit on older server versions
}

struct ReadingDaySummary: Codable, Sendable {
    let dayNumber: Int
    let date: String        // "YYYY-MM-DD"
    let isCompleted: Bool
    let isOverdue: Bool
    let entryCount: Int
}

struct ReadingEntry: Identifiable, Codable, Sendable {
    let id: String
    let reference: String   // e.g. "Genesis 1:1-2:3"
    let bookName: String?   // optional — nil if entry has no linked book
    let bookAbbrev: String?
    let chapterStart: Int?
    let verseStart: Int?
    let chapterEnd: Int?
    let verseEnd: Int?
    let notes: String?
}

struct ReadingToggleResponse: Codable, Sendable {
    let isCompleted: Bool
    let daysCompleted: Int
    let completionPercentage: Double
    let daysBehind: Int?
    let currentDayNumber: Int?
}
