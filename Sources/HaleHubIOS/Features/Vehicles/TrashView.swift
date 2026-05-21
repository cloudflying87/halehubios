import SwiftUI

struct TrashView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    let vehicleId: Int
    var onRestored: () -> Void

    @State private var events: [VehicleEvent] = []
    @State private var isLoading = false
    @State private var restoringIds: Set<Int> = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    ContentUnavailableView {
                        Label("Couldn't Load", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") { Task { await load() } }.buttonStyle(.bordered)
                    }
                } else if events.isEmpty {
                    ContentUnavailableView(
                        "No Deleted Records",
                        systemImage: "trash.slash",
                        description: Text("Records you delete will appear here for 30 days.")
                    )
                } else {
                    List {
                        Section {
                            Text("Showing the 50 most recently deleted records. Restore any to bring it back.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .listRowBackground(Color.clear)

                        ForEach(events) { event in
                            HStack(spacing: 12) {
                                Image(systemName: event.eventIcon)
                                    .font(.subheadline)
                                    .foregroundStyle(iconColor(event))
                                    .frame(width: 28, height: 28)
                                    .background(iconColor(event).opacity(0.12), in: Circle())

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(eventTitle(event))
                                        .font(.body)
                                    if let deletedAt = event.deletedAt {
                                        Text("Deleted \(deletedAt.formatted(.relative(presentation: .named)))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                if restoringIds.contains(event.id) {
                                    ProgressView().scaleEffect(0.8)
                                } else {
                                    Button("Restore") {
                                        Task { await restore(event) }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .tint(.green)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Recently Deleted")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        guard let token = auth.accessToken else { return }
        isLoading = true
        error = nil
        do {
            events = try await APIClient.shared.get("/vehicles/\(vehicleId)/trash/", token: token)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func restore(_ event: VehicleEvent) async {
        guard let token = auth.accessToken else { return }
        restoringIds.insert(event.id)
        do {
            let _: VehicleEvent = try await APIClient.shared.postEmpty(
                "/vehicles/events/\(event.id)/restore/", token: token
            )
            events.removeAll { $0.id == event.id }
            onRestored()
        } catch {
            self.error = error.localizedDescription
        }
        restoringIds.remove(event.id)
    }

    private func iconColor(_ event: VehicleEvent) -> Color {
        switch event.eventType {
        case "gas": return .blue
        case "maintenance": return .orange
        case "outing": return .green
        default: return .secondary
        }
    }

    private func eventTitle(_ event: VehicleEvent) -> String {
        switch event.eventType {
        case "gas":
            if let g = event.gallons { return String(format: "%.3f gal fill-up", g) }
            return "Gas fill-up"
        case "maintenance":
            return event.maintenanceCategoryName ?? "Maintenance"
        case "outing":
            return event.locationName ?? "Outing"
        default:
            return event.eventType.capitalized
        }
    }
}
