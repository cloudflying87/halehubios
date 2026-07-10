import Foundation

// MARK: - Resource

struct Resource: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let slug: String
    let description: String
    let contentType: String   // "markdown" | "react"
    let isPublic: Bool
    let isActive: Bool
    let canEdit: Bool
    let createdAt: Date

    var isReact: Bool { contentType == "react" }

    enum CodingKeys: String, CodingKey {
        case id, title, slug, description, contentType, isPublic, isActive, canEdit, createdAt
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
        description = (try? c.decode(String.self, forKey: .description)) ?? ""
        contentType = (try? c.decode(String.self, forKey: .contentType)) ?? "markdown"
        isPublic = (try? c.decode(Bool.self, forKey: .isPublic)) ?? true
        isActive = (try? c.decode(Bool.self, forKey: .isActive)) ?? true
        canEdit = (try? c.decode(Bool.self, forKey: .canEdit)) ?? false
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
    }
}

struct ResourceDetail: Codable, Sendable {
    let id: String
    let title: String
    let slug: String
    let description: String
    let contentType: String   // "markdown" | "react"
    let content: String       // raw source
    let contentHtml: String?  // server-rendered HTML (markdown only)
    let isPublic: Bool
    let isActive: Bool
    let order: Int
    let canEdit: Bool
    let createdAt: Date
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, slug, description
        case contentType, content, contentHtml
        case isPublic, isActive, order, canEdit
        case createdAt, updatedAt
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
        description = (try? c.decode(String.self, forKey: .description)) ?? ""
        contentType = (try? c.decode(String.self, forKey: .contentType)) ?? "markdown"
        content = (try? c.decode(String.self, forKey: .content)) ?? ""
        contentHtml = try? c.decode(String.self, forKey: .contentHtml)
        isPublic = (try? c.decode(Bool.self, forKey: .isPublic)) ?? true
        isActive = (try? c.decode(Bool.self, forKey: .isActive)) ?? true
        order = (try? c.decode(Int.self, forKey: .order)) ?? 0
        canEdit = (try? c.decode(Bool.self, forKey: .canEdit)) ?? false
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        updatedAt = try? c.decode(Date.self, forKey: .updatedAt)
    }
}

// MARK: - Resource request bodies

struct ResourceDraft: Encodable, Sendable {
    let title: String
    let description: String
    let content: String
    let contentType: String
    let isPublic: Bool
    let isActive: Bool
    let order: Int
}

struct ResourcePatch: Encodable, Sendable {
    let title: String
    let description: String
    let content: String
    let isPublic: Bool
    let isActive: Bool
    let order: Int
}

struct ResourceArchiveRequest: Encodable, Sendable {
    let archived: Bool
}

// MARK: - Letter request bodies

struct LetterDraft: Encodable, Sendable {
    let title: String
    let year: Int
    let greetingMessage: String
    let hasRsvp: Bool
    let eventDate: String?
    let eventTime: String
    let eventLocation: String
    let isActive: Bool
}

struct LetterPatch: Encodable, Sendable {
    let title: String
    let greetingMessage: String
    let year: Int
    let hasRsvp: Bool
    let eventDate: String?
    let eventTime: String
    let eventLocation: String
}

// MARK: - Letter

struct Letter: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let slug: String
    let year: Int
    let hasRsvp: Bool
    let eventDate: String?
    let photoCount: Int
    let canEdit: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, slug, year, hasRsvp, eventDate, photoCount, canEdit
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
        hasRsvp = (try? c.decode(Bool.self, forKey: .hasRsvp)) ?? false
        eventDate = try? c.decode(String.self, forKey: .eventDate)
        photoCount = (try? c.decode(Int.self, forKey: .photoCount)) ?? 0
        canEdit = (try? c.decode(Bool.self, forKey: .canEdit)) ?? false
    }
}

struct LetterDetail: Codable, Sendable {
    let id: String
    let title: String
    let slug: String
    let year: Int
    let greetingMessage: String
    let greetingMessageHtml: String   // server-rendered HTML
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
    let canEdit: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, slug, year
        case greetingMessage, greetingMessageHtml
        case hasRsvp, eventDate, eventTime, eventLocation
        case rsvpTitle, rsvpSubtitle
        case rsvpShowEmail, rsvpShowPhone, rsvpShowGuestCount, rsvpShowNotes
        case photos, canEdit
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
        greetingMessageHtml = (try? c.decode(String.self, forKey: .greetingMessageHtml)) ?? ""
        hasRsvp = (try? c.decode(Bool.self, forKey: .hasRsvp)) ?? false
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
        canEdit = (try? c.decode(Bool.self, forKey: .canEdit)) ?? false
    }
}

struct LetterPhoto: Codable, Sendable {
    let url: String
    let caption: String
    let order: Int
}

extension LetterPhoto: Identifiable {
    var id: String { url }
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
