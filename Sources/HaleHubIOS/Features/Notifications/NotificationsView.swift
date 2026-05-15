import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = NotificationsViewModel()

    var body: some View {
        List {
            if !vm.notifications.isEmpty {
                Section {
                    Button("Mark all as read") {
                        Task { await vm.markAllRead(token: auth.accessToken ?? "") }
                    }
                    .foregroundStyle(.accentColor)
                    .disabled(vm.unreadCount == 0)
                }
            }

            if vm.isLoading && vm.notifications.isEmpty {
                Section {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            } else if vm.notifications.isEmpty {
                Section {
                    ContentUnavailableView("No Notifications", systemImage: "bell.slash")
                }
            } else {
                ForEach(vm.notifications) { notif in
                    NotificationRow(notification: notif)
                        .listRowBackground(notif.isRead ? Color.clear : Color.accentColor.opacity(0.05))
                        .onTapGesture {
                            Task { await vm.markRead(notif, token: auth.accessToken ?? "") }
                        }
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.large)
        .task { await vm.load(token: auth.accessToken ?? "") }
        .refreshable { await vm.load(token: auth.accessToken ?? "") }
    }
}

struct NotificationRow: View {
    let notification: HaleNotification

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(notification.isRead ? Color(.systemGray5) : Color.accentColor.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: notification.typeIcon)
                    .font(.subheadline)
                    .foregroundStyle(notification.isRead ? .secondary : .accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(notification.title)
                        .font(notification.isRead ? .subheadline : .subheadline.bold())
                    Spacer()
                    Text(notification.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(notification.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let actor = notification.actorName {
                    Text("From \(actor)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if !notification.isRead {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
}
