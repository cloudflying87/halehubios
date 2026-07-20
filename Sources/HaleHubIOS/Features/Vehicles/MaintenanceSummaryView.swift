import SwiftUI

// MARK: - Maintenance Summary

/// Schedule due-status plus the full itemized visit timeline for one vehicle,
/// in one screen — mirrors the web "Maintenance Summary" page.
struct MaintenanceSummaryView: View {
    @EnvironmentObject var auth: AuthManager
    let vehicle: Vehicle

    @State private var insights: MaintenanceInsightsResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && insights == nil {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let insights {
                List {
                    if insights.stats.totalMaintenanceEvents == 0 {
                        Section {
                            Text("No maintenance has ever been logged for \(vehicle.name). Schedules won't show as \u{201c}due\u{201d} until at least one service is logged per category.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("Schedule Status") {
                        if insights.schedules.isEmpty {
                            Text("No maintenance schedules configured yet.").foregroundStyle(.secondary)
                        } else {
                            ForEach(insights.schedules) { s in
                                ScheduleInsightRow(insight: s)
                            }
                        }
                    }

                    Section {
                        if insights.visits.isEmpty {
                            Text("No maintenance visits logged yet.").foregroundStyle(.secondary)
                        } else {
                            ForEach(insights.visits) { visit in
                                VisitRow(visit: visit)
                            }
                        }
                    } header: {
                        HStack {
                            Text("Service History")
                            Spacer()
                            Text("\(insights.stats.totalMaintenanceEvents) visit\(insights.stats.totalMaintenanceEvents == 1 ? "" : "s")")
                        }
                    } footer: {
                        if let record = insights.stats.importHistory.first {
                            Text("Imported \(record.recordsImported) records from \(record.sourceType.capitalized) on \(record.importedAt.formatted(date: .abbreviated, time: .omitted)).")
                        }
                    }
                }
                .listStyle(.insetGrouped)
            } else if let errorMessage {
                ContentUnavailableView("Error", systemImage: "exclamationmark.circle", description: Text(errorMessage))
            }
        }
        .navigationTitle("Maintenance Summary")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        guard let token = auth.accessToken else { return }
        isLoading = true
        do {
            insights = try await APIClient.shared.get(
                "/vehicles/\(vehicle.id)/maintenance-insights/", token: token
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Schedule Insight Row

private struct ScheduleInsightRow: View {
    let insight: ScheduleInsight

    private var intervalText: String {
        var parts: [String] = []
        if let m = insight.intervalMiles { parts.append("Every \(m.formatted()) \(insight.unit)") }
        if let h = insight.intervalHours { parts.append("Every \(h) hrs") }
        if let d = insight.intervalDays { parts.append("Every \(d) days") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(insight.categoryName).font(.body.weight(.medium))
                Spacer()
                if insight.isDue {
                    Text("DUE")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(.orange, in: Capsule())
                } else {
                    Text("OK").font(.caption2.bold()).foregroundStyle(.green)
                }
            }
            Text(intervalText).font(.caption).foregroundStyle(.secondary)
            if let last = insight.lastPerformed {
                Text("Last: \(last.formatted(date: .abbreviated, time: .omitted))"
                     + (insight.lastValue.map { " · \($0.formatted()) \(insight.unit)" } ?? ""))
                    .font(.caption2).foregroundStyle(.tertiary)
            } else {
                Text("Never performed").font(.caption2).foregroundStyle(.tertiary)
            }
            if insight.isDue, let reason = insight.reason, !reason.isEmpty {
                Text(reason).font(.caption2).foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Visit Row

private struct VisitRow: View {
    let visit: MaintenanceVisit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(visit.date.formatted(date: .abbreviated, time: .omitted)).font(.subheadline.weight(.semibold))
                Spacer()
                if let odo = visit.odometer {
                    Text("\(odo.formatted()) \(visit.unit)").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !visit.items.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(visit.items) { item in
                        HStack(alignment: .top, spacing: 6) {
                            Text(item.category)
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color(.systemGray5), in: Capsule())
                            Text(item.description).font(.caption)
                        }
                    }
                }
            } else if let notes = visit.notes, !notes.isEmpty {
                Text(notes).font(.caption).foregroundStyle(.secondary)
            } else {
                Text("No details recorded.").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }
}
