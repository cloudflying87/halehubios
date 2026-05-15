import Foundation

@MainActor
class NotificationsViewModel: ObservableObject {
    @Published var notifications: [HaleNotification] = []
    @Published var unreadCount = 0
    @Published var isLoading = false
    @Published var error: String?

    func load(token: String) async {
        isLoading = true
        do {
            let response: PaginatedResponse<HaleNotification> = try await APIClient.shared.get(
                "/notifications/", token: token
            )
            notifications = response.results
            unreadCount = response.results.filter { !$0.isRead }.count
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func fetchUnreadCount(token: String) async {
        if let response: UnreadCountResponse = try? await APIClient.shared.get(
            "/notifications/unread-count/", token: token
        ) {
            unreadCount = response.unreadCount
        }
    }

    func markRead(_ notification: HaleNotification, token: String) async {
        guard !notification.isRead else { return }
        if let idx = notifications.firstIndex(where: { $0.id == notification.id }) {
            notifications[idx].isRead = true
            unreadCount = max(0, unreadCount - 1)
        }
        struct MarkReadResponse: Decodable { let isRead: Bool }
        _ = try? await APIClient.shared.postEmpty(
            "/notifications/\(notification.id)/read/", token: token
        ) as MarkReadResponse
    }

    func markAllRead(token: String) async {
        for i in notifications.indices { notifications[i].isRead = true }
        unreadCount = 0
        struct MarkAllResponse: Decodable { let markedRead: Int }
        _ = try? await APIClient.shared.postEmpty("/notifications/read-all/", token: token) as MarkAllResponse
    }
}
