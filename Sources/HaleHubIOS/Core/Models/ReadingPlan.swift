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
    let id: String         // UUID — BibleBook uses a UUID primary key
    let name: String
    let abbreviation: String
    let testament: String  // "OT" or "NT"
    let totalChapters: Int
    let chapters: [BibleChapterData]

    // custom decode so old API responses (without chapters) still work
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        abbreviation = try c.decode(String.self, forKey: .abbreviation)
        testament = try c.decode(String.self, forKey: .testament)
        totalChapters = (try? c.decode(Int.self, forKey: .totalChapters)) ?? 0
        chapters = (try? c.decode([BibleChapterData].self, forKey: .chapters)) ?? []
    }

    static func == (lhs: BibleBook, rhs: BibleBook) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    func totalVerses(forChapter ch: Int) -> Int {
        chapters.first(where: { $0.chapterNumber == ch })?.totalVerses ?? 0
    }
}

struct ChunkedDaysResponse: Codable, Sendable {
    let chunk: Int
    let totalChunks: Int
    let totalDays: Int
    let daysPerChunk: Int
    let days: [ReadingDay]
}

struct AddReadingEntryRequest: Encodable, Sendable {
    let bookId: String      // UUID of the BibleBook
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

/// POST /api/reading/entries/<id>/move/ body.
struct MoveReadingEntryRequest: Encodable, Sendable {
    let dayNumber: Int
}

struct BibleBookProgress: Codable, Sendable {
    let bookId: String      // UUID of the BibleBook
    let bookName: String
    let abbreviation: String
    let testament: String   // "OT" or "NT"
    let totalChapters: Int
    let chaptersRead: Int
    let isStarted: Bool
    let isComplete: Bool
}

struct BibleChapterData: Codable, Sendable {
    let chapterNumber: Int
    let totalVerses: Int
}

struct BulkAddRequest: Encodable, Sendable {
    let references: String
}

struct BulkEntryError: Codable, Sendable {
    let input: String
    let error: String
}

struct BulkAddResponse: Codable, Sendable {
    let saved: [ReadingEntry]
    let savedCount: Int
    let errors: [BulkEntryError]
    let errorCount: Int
}

struct CreatePlanRequest: Encodable, Sendable {
    let name: String
    let startDate: String    // "YYYY-MM-DD"
    let totalDays: Int
    let description: String
    let isPrimary: Bool
}

struct BulkPreviewItem: Codable, Sendable {
    let input: String
    let reference: String
    let valid: Bool
}

struct BulkPreviewResponse: Codable, Sendable {
    let dryRun: Bool
    let validCount: Int
    let errorCount: Int
    let valid: [BulkPreviewItem]
    let errors: [BulkEntryError]
}
