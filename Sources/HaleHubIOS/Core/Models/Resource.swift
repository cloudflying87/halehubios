import Foundation

// MARK: - Resource

struct Resource: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let slug: String
    let description: String
    let isPublic: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, slug, description, isPublic, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let intId = try? c.decode(Int.self, forKey: .id) {
            id = String(intId)
        } else {
            id = try c.decode(String.self, forKey: .id)
        }
        title = try c.decode(String.self, forKey: .title)
        slug = try c.decode(String.self, forKey: .slug)
        description = try c.decode(String.self, forKey: .description)
        isPublic = try c.decode(Bool.self, forKey: .isPublic)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }
}

struct ResourceDetail: Codable, Sendable {
    let id: String
    let title: String
    let slug: String
    let description: String
    let contentType: String  // "markdown" | "react"
    let content: String      // raw markdown text
    let isPublic: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, slug, description, contentType, content, isPublic, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let intId = try? c.decode(Int.self, forKey: .id) {
            id = String(intId)
        } else {
            id = try c.decode(String.self, forKey: .id)
        }
        title = try c.decode(String.self, forKey: .title)
        slug = try c.decode(String.self, forKey: .slug)
        description = try c.decode(String.self, forKey: .description)
        contentType = try c.decode(String.self, forKey: .contentType)
        content = try c.decode(String.self, forKey: .content)
        isPublic = try c.decode(Bool.self, forKey: .isPublic)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }
}

// MARK: - Letter

struct Letter: Identifiable, Codable, Sendable {
    let id: String       // UUID string
    let title: String
    let slug: String
    let year: Int
    let hasRsvp: Bool
    let eventDate: String?   // "YYYY-MM-DD" or null
    let photoCount: Int

    enum CodingKeys: String, CodingKey {
        case id, title, slug, year, hasRsvp, eventDate, photoCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Letters use UUID PKs — always String; guard against Int just in case
        if let intId = try? c.decode(Int.self, forKey: .id) {
            id = String(intId)
        } else {
            id = try c.decode(String.self, forKey: .id)
        }
        title = try c.decode(String.self, forKey: .title)
        slug = try c.decode(String.self, forKey: .slug)
        year = try c.decode(Int.self, forKey: .year)
        hasRsvp = try c.decode(Bool.self, forKey: .hasRsvp)
        eventDate = try? c.decode(String.self, forKey: .eventDate)
        photoCount = (try? c.decode(Int.self, forKey: .photoCount)) ?? 0
    }
}

struct LetterDetail: Codable, Sendable {
    let id: String
    let title: String
    let slug: String
    let year: Int
    let greetingMessage: String  // raw markdown
    let hasRsvp: Bool
    let eventDate: String?
    let eventTime: String
    let eventLocation: String
    let rsvpTitle: String
    let rsvpSubtitle: String
    let rsvpShowEmail: Bool
    let rsvpShowPhone: Bool
    let rsvpShowGuestCount: Bool
    let rsvpShowNotes: Bool
    let photos: [LetterPhoto]

    enum CodingKeys: String, CodingKey {
        case id, title, slug, year, greetingMessage, hasRsvp, eventDate
        case eventTime, eventLocation
        case rsvpTitle, rsvpSubtitle
        case rsvpShowEmail, rsvpShowPhone, rsvpShowGuestCount, rsvpShowNotes
        case photos
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let intId = try? c.decode(Int.self, forKey: .id) {
            id = String(intId)
        } else {
            id = try c.decode(String.self, forKey: .id)
        }
        title = try c.decode(String.self, forKey: .title)
        slug = try c.decode(String.self, forKey: .slug)
        year = try c.decode(Int.self, forKey: .year)
        greetingMessage = (try? c.decode(String.self, forKey: .greetingMessage)) ?? ""
        hasRsvp = try c.decode(Bool.self, forKey: .hasRsvp)
        eventDate = try? c.decode(String.self, forKey: .eventDate)
        eventTime = (try? c.decode(String.self, forKey: .eventTime)) ?? ""
        eventLocation = (try? c.decode(String.self, forKey: .eventLocation)) ?? ""
        rsvpTitle = (try? c.decode(String.self, forKey: .rsvpTitle)) ?? "RSVP"
        rsvpSubtitle = (try? c.decode(String.self, forKey: .rsvpSubtitle)) ?? ""
        rsvpShowEmail = (try? c.decode(Bool.self, forKey: .rsvpShowEmail)) ?? true
        rsvpShowPhone = (try? c.decode(Bool.self, forKey: .rsvpShowPhone)) ?? false
        rsvpShowGuestCount = (try? c.decode(Bool.self, forKey: .rsvpShowGuestCount)) ?? true
        rsvpShowNotes = (try? c.decode(Bool.self, forKey: .rsvpShowNotes)) ?? false
        photos = (try? c.decode([LetterPhoto].self, forKey: .photos)) ?? []
    }
}

struct LetterPhoto: Codable, Sendable {
    let url: String
    let caption: String
    let order: Int
}

// MARK: - RSVP

struct RSVPRequest: Encodable, Sendable {
    let name: String
    let email: String
    let phone: String
    let guestCount: Int
    let notes: String
}

struct RSVPResponse: Decodable, Sendable {
    let success: Bool
    let message: String
}
