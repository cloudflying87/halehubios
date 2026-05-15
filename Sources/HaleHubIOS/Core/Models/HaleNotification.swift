import Foundation

struct HaleNotification: Identifiable, Codable {
    let id: UUID
    let notificationType: String
    let typeLabel: String
    let title: String
    let message: String
    let linkUrl: String?
    let actorName: String?
    var isRead: Bool
    let readAt: Date?
    let createdAt: Date

    var typeIcon: String {
        switch notificationType {
        case "comment": return "bubble.left.fill"
        case "list_share": return "list.bullet"
        case "vehicle_maintenance": return "wrench.fill"
        case "new_content": return "doc.text.fill"
        case "paycheck_reminder": return "dollarsign.circle.fill"
        default: return "bell.fill"
        }
    }
}

struct UnreadCountResponse: Decodable {
    let unreadCount: Int
}
