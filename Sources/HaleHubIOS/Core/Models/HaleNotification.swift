import Foundation

struct HaleNotification: Identifiable, Codable, Sendable {
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
        case "gas_logged": return "fuelpump.fill"
        case "outing_logged": return "safari.fill"
        case "maintenance_logged": return "wrench.fill"
        case "new_content": return "doc.text.fill"
        case "paycheck_reminder": return "dollarsign.circle.fill"
        default: return "bell.fill"
        }
    }
}

struct UnreadCountResponse: Decodable, Sendable {
    let unreadCount: Int
}
