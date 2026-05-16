import Charts
import SwiftUI

struct OutingsAnalyticsView: View {
    @EnvironmentObject var auth: AuthManager

    /// When provided, pre-selects this vehicle in the filter.
    var vehicle: Vehicle? = nil

    @State private var analytics: OutingsAnalyticsResponse? = nil
    @State private var vehicles: [Vehicle] = []
    @State private var selectedVehicleId: Int? = nil
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Vehicle filter picker
                if !vehicles.isEmpty {
                    Picker("Vehicle", selection: $selectedVehicleId) {
                        Text("All Vehicles").tag(nil as Int?)
                        ForEach(vehicles) { v in
                            Text(v.name).tag(v.id as Int?)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 16)
                    .onChange(of: selectedVehicleId) { _, _ in
                        Task { await loadAnalytics() }
                    }
                }

                if isLoading && analytics == nil {
                    ProgressView("Loading analytics…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if let error = errorMessage {
                    ContentUnavailableView(
                        "Error",
                        systemImage: "exclamationmark.circle",
                        description: Text(error)
                    )
                } else if let data = analytics {
                    // Monthly bar chart
                    if !data.byMonth.isEmpty {
                        OutingsByMonthChart(byMonth: data.byMonth)
                            .padding(.horizontal, 16)
                    }

                    // By Vehicle breakdown
                    if !data.byVehicle.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("By Vehicle")
                                .font(.headline)
                                .padding(.horizontal, 16)
                            ForEach(data.byVehicle) { item in
                                HStack {
                                    Label(item.vehicleName, systemImage: "car")
                                        .font(.subheadline)
                                    Spacer()
                                    Text("\(item.count)")
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    Text(item.count == 1 ? "outing" : "outings")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
                                .padding(.horizontal, 16)
                            }
                        }
                    }

                    // Top Locations
                    if !data.topLocations.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Top Locations")
                                .font(.headline)
                                .padding(.horizontal, 16)
                            ForEach(Array(data.topLocations.enumerated()), id: \.element.id) { index, loc in
                                HStack(spacing: 12) {
                                    Text("#\(index + 1)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 28, alignment: .trailing)
                                    Text(loc.name)
                                        .font(.subheadline)
                                    Spacer()
                                    Text("\(loc.count)")
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
                                .padding(.horizontal, 16)
                            }
                        }
                    }

                    if data.byMonth.isEmpty && data.byVehicle.isEmpty && data.topLocations.isEmpty {
                        ContentUnavailableView(
                            "No Outings Data",
                            systemImage: "map",
                            description: Text("Log some outings to see analytics here.")
                        )
                        .padding(.top, 40)
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .navigationTitle("Outings Analytics")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await loadAnalytics() }
        .task {
            await loadVehicles()
            if let v = vehicle { selectedVehicleId = v.id }
            await loadAnalytics()
        }
    }

    private func loadVehicles() async {
        guard let token = auth.accessToken else { return }
        if let response: PaginatedResponse<Vehicle> = try? await APIClient.shared.get("/vehicles/", token: token) {
            vehicles = response.results
        }
    }

    private func loadAnalytics() async {
        guard let token = auth.accessToken else { return }
        isLoading = true
        errorMessage = nil

        var path = "/vehicles/outings-analytics/"
        if let vid = selectedVehicleId {
            path += "?vehicle_id=\(vid)"
        }

        do {
            analytics = try await APIClient.shared.get(path, token: token)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Monthly Bar Chart

struct OutingsByMonthChart: View {
    let byMonth: [OutingsByMonth]

    /// Show only the last 12 months, sorted ascending by month string
    private var chartData: [OutingsByMonth] {
        let sorted = byMonth.sorted { $0.month < $1.month }
        return Array(sorted.suffix(12))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Outings by Month")
                .font(.headline)

            Chart(chartData) { item in
                BarMark(
                    x: .value("Month", item.month),
                    y: .value("Outings", item.count)
                )
                .foregroundStyle(Color.accentColor)
                .cornerRadius(4)
                .annotation(position: .top, alignment: .center) {
                    if item.count > 0 {
                        Text("\(item.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 5))
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let s = value.as(String.self) {
                            // Show last 4 chars (e.g. "2025-01" → "Jan")
                            let label = monthLabel(from: s)
                            Text(label)
                                .font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 180)
        }
        .padding(14)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
    }

    /// Convert "2025-01" → "Jan", "2025-12" → "Dec"
    private func monthLabel(from raw: String) -> String {
        let parts = raw.split(separator: "-")
        guard parts.count == 2, let month = Int(parts[1]) else { return raw }
        let symbols = Calendar.current.shortMonthSymbols
        guard month >= 1 && month <= 12 else { return raw }
        return symbols[month - 1]
    }
}
