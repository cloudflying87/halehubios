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

struct BibleBook: Identifiable, Codable, Sendable, Hashable {
    let id: Int
    let name: String
    let abbreviation: String
    let testament: String  // "OT" or "NT"

    static func == (lhs: BibleBook, rhs: BibleBook) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct ChunkedDaysResponse: Codable, Sendable {
    let chunk: Int
    let totalChunks: Int
    let totalDays: Int
    let daysPerChunk: Int
    let days: [ReadingDay]
}

struct AddReadingEntryRequest: Encodable, Sendable {
    let bookId: Int
    let chapterStart: Int
    let verseStart: Int
    let chapterEnd: Int
    let verseEnd: Int
    let notes: String
}

struct MonthDaysResponse: Codable, Sendable {
    let year: Int
    let month: Int
    let days: [ReadingDay]
}

struct UpdateDayNotesRequest: Encodable, Sendable {
    let notes: String
}

struct BibleBookProgress: Codable, Sendable {
    let bookId: Int
    let bookName: String
    let abbreviation: String
    let testament: String   // "OT" or "NT"
    let totalChapters: Int
    let chaptersRead: Int
    let isStarted: Bool
    let isComplete: Bool
}
