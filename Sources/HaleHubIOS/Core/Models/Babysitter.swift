import Foundation

// MARK: - Babysitter (GET /api/babysitters/ — paginated)

struct Babysitter: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let email: String
    let phoneNumber: String
    let hourlyRate: Double
    let isActive: Bool?
    let notes: String
    let unpaidTotal: Double?
    let createdAt: Date?

    var hasEmail: Bool { !email.isEmpty }
    var rateDisplay: String { String(format: "$%.2f/hr", hourlyRate) }
    var unpaidDisplay: String { BabysitterFormat.money(unpaidTotal) }
}

// MARK: - Session (GET /api/babysitters/sessions/ — paginated)

struct BabysittingSession: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let babysitter: String          // babysitter id
    let babysitterName: String?
    let date: String                // "YYYY-MM-DD"
    let startTime: String           // "HH:MM:SS"
    let endTime: String
    let hoursWorked: Double?
    let amountOwed: Double?
    let rateSnapshot: Double?
    let durationDisplay: String?
    let isPaid: Bool
    let paidAt: Date?
    let payment: String?            // payment id this session was paid with, if any
    let source: String?
    let externalUid: String?
    let notes: String
    let createdAt: Date?

    var dateDisplay: String { BabysitterFormat.dateShort(date) }
    var startDisplay: String { BabysitterFormat.time(startTime) }
    var endDisplay: String { BabysitterFormat.time(endTime) }
    var amountDisplay: String { BabysitterFormat.money(amountOwed) }
    var isImported: Bool { (source ?? "manual") != "manual" }
}

// MARK: - Calendar feed

struct CalendarFeed: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let babysitter: String
    let feedType: String
    let name: String
    let url: String
    let matchKeyword: String
    let isActive: Bool
    let lastSyncedAt: Date?
    let lastSyncStatus: String
}

// MARK: - Reports

/// One sitter's weekly slice. `reportText` is present only on the single-sitter
/// endpoint (GET /api/babysitters/<id>/report/); it's nil inside the family-wide
/// weekly report's per_sitter list.
struct SitterReport: Codable, Sendable, Identifiable {
    let babysitterId: String
    let babysitterName: String
    let weekStart: String
    let weekEnd: String
    let totalHours: Double
    let totalOwed: Double
    let unpaidOwed: Double
    let paidOwed: Double
    let sessionCount: Int
    let sessions: [ReportSession]
    let reportText: String?

    var id: String { babysitterId }
    var weekLabel: String { BabysitterFormat.weekRange(weekStart, weekEnd) }
}

struct ReportSession: Identifiable, Codable, Sendable, Hashable {
    let id: String
    let date: String
    let startTime: String
    let endTime: String
    let hoursWorked: Double
    let amountOwed: Double
    let isPaid: Bool
    let durationDisplay: String

    var dateDisplay: String { BabysitterFormat.dateShort(date) }
    var timeRange: String { "\(BabysitterFormat.time(startTime))–\(BabysitterFormat.time(endTime))" }
    var amountDisplay: String { BabysitterFormat.money(amountOwed) }
}

struct WeeklyReport: Codable, Sendable {
    let weekStart: String
    let weekEnd: String
    let grandTotalOwed: Double
    let grandUnpaidOwed: Double
    let perSitter: [SitterReport]

    var weekLabel: String { BabysitterFormat.weekRange(weekStart, weekEnd) }
}

// MARK: - Payments

/// A recorded payment (check/cash/etc) covering one or more sessions.
/// GET /api/babysitters/payments/ (paginated) and /<id>/; POST to record one.
struct Payment: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let babysitter: String
    let babysitterName: String?
    let amount: Double
    let datePaid: String       // "YYYY-MM-DD"
    let method: String         // check | cash | venmo | zelle | other
    let checkNumber: String
    let notes: String
    let sessionCount: Int
    let sessions: [ReportSession]
    let createdAt: Date?

    var amountDisplay: String { BabysitterFormat.money(amount) }
    var dateDisplay: String { BabysitterFormat.dateShort(datePaid) }
    var methodDisplay: String { Payment.methodLabels[method] ?? method.capitalized }

    static let methodLabels: [String: String] = [
        "check": "Check", "cash": "Cash", "venmo": "Venmo", "zelle": "Zelle", "other": "Other",
    ]
    static let methods = ["check", "cash", "venmo", "zelle", "other"]
}

struct RecordPaymentRequest: Encodable, Sendable {
    let babysitter: String
    let sessionIds: [String]
    let amount: Double
    let datePaid: String
    let method: String
    let checkNumber: String
    let notes: String
}

/// PATCH /api/babysitters/payments/<id>/ — correct amount/date/method/check#/notes.
/// Which sessions it covers isn't editable here — void and re-record instead.
struct UpdatePaymentRequest: Encodable, Sendable {
    let amount: Double
    let datePaid: String
    let method: String
    let checkNumber: String
    let notes: String
}

// MARK: - Request bodies (snake_cased by APIClient's encoder)

struct BabysitterRequest: Encodable, Sendable {
    let name: String
    let email: String
    let phoneNumber: String
    let hourlyRate: Double
    let notes: String
    let isActive: Bool
}

struct SessionRequest: Encodable, Sendable {
    let babysitter: String   // babysitter id
    let date: String         // "YYYY-MM-DD"
    let startTime: String    // "HH:MM"
    let endTime: String      // "HH:MM"
    let notes: String
}

struct SendReportResponse: Decodable, Sendable {
    let detail: String
    let to: String?
}

struct RecalculateResponse: Decodable, Sendable {
    let updated: Int
    let newRate: Double
}

// MARK: - Formatting helpers

enum BabysitterFormat {
    private static let posix = Locale(identifier: "en_US_POSIX")

    static func money(_ v: Double?) -> String {
        String(format: "$%.2f", v ?? 0)
    }

    /// "18:00:00" or "18:00" → "6:00 PM"
    static func time(_ value: String) -> String {
        let parts = value.split(separator: ":")
        guard parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return value }
        var comps = DateComponents()
        comps.hour = h
        comps.minute = m
        guard let date = Calendar.current.date(from: comps) else { return value }
        let f = DateFormatter()
        f.locale = posix
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    /// "2026-06-01" → "Mon Jun 1"
    static func dateShort(_ ymd: String) -> String {
        guard let date = ymdDate(ymd) else { return ymd }
        let f = DateFormatter()
        f.locale = posix
        f.dateFormat = "EEE MMM d"
        return f.string(from: date)
    }

    /// "2026-06-01", "2026-06-07" → "Jun 1 – Jun 7, 2026"
    static func weekRange(_ start: String, _ end: String) -> String {
        guard let s = ymdDate(start), let e = ymdDate(end) else { return "\(start) – \(end)" }
        let a = DateFormatter(); a.locale = posix; a.dateFormat = "MMM d"
        let b = DateFormatter(); b.locale = posix; b.dateFormat = "MMM d, yyyy"
        return "\(a.string(from: s)) – \(b.string(from: e))"
    }

    static func ymdDate(_ ymd: String) -> Date? {
        let f = DateFormatter()
        f.locale = posix
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: ymd)
    }

    static func ymdString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = posix
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func hmString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = posix
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
