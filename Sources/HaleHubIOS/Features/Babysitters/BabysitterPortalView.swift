import SwiftUI

// MARK: - Portal response model

private struct PortalResponse: Decodable, Sendable {
    let babysitter: Babysitter
    let sessions: [BabysittingSession]
    let unpaidTotal: Double
    let totalSessions: Int
}

// MARK: - View

struct BabysitterPortalView: View {
    @EnvironmentObject var auth: AuthManager

    @State private var sitter: Babysitter?
    @State private var sessions: [BabysittingSession] = []
    @State private var unpaidTotal: Double = 0
    @State private var totalSessions: Int = 0
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading && sitter == nil {
                ProgressView("Loading your hours…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                ContentUnavailableView("Error", systemImage: "exclamationmark.circle", description: Text(error))
            } else if let sitter {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Summary cards
                        HStack(spacing: 12) {
                            PortalStatCard(label: "Sessions", value: "\(totalSessions)", color: .accentColor)
                            PortalStatCard(
                                label: "Amount Owed",
                                value: BabysitterFormat.money(unpaidTotal),
                                color: unpaidTotal > 0 ? .orange : .green
                            )
                            PortalStatCard(label: "Rate", value: sitter.rateDisplay, color: .secondary)
                        }
                        .padding(.horizontal, 16)

                        if unpaidTotal > 0 {
                            HStack {
                                Image(systemName: "clock.badge.exclamationmark")
                                Text("You have unpaid sessions totaling \(BabysitterFormat.money(unpaidTotal))")
                                    .font(.subheadline)
                            }
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 16)
                        } else if totalSessions > 0 {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("All sessions are paid up!")
                                    .font(.subheadline)
                            }
                            .foregroundStyle(.green)
                            .padding(.horizontal, 16)
                        }

                        // Session list
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Session History")
                                .font(.headline)
                                .padding(.horizontal, 16)

                            if sessions.isEmpty {
                                Text("No sessions logged yet.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 16)
                            } else {
                                ForEach(sessions) { session in
                                    PortalSessionRow(session: session)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 16)
                }
                .refreshable { await load() }
            }
        }
        .navigationTitle("My Hours")
        .task { await load() }
    }

    private func load() async {
        guard let token = auth.accessToken else { return }
        isLoading = true
        error = nil
        do {
            let response: PortalResponse = try await APIClient.shared.get("/babysitters/portal/", token: token)
            sitter = response.babysitter
            sessions = response.sessions
            unpaidTotal = response.unpaidTotal
            totalSessions = response.totalSessions
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Sub-views

private struct PortalStatCard: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct PortalSessionRow: View {
    let session: BabysittingSession

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.dateDisplay)
                    .font(.subheadline.weight(.medium))
                Text("\(session.startDisplay) – \(session.endDisplay)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !session.notes.isEmpty {
                    Text(session.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(session.amountDisplay)
                    .font(.subheadline.weight(.semibold))
                Text(session.isPaid ? "Paid" : "Unpaid")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(session.isPaid ? .green : .orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((session.isPaid ? Color.green : Color.orange).opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
