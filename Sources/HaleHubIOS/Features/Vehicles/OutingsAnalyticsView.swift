import Charts
import SwiftUI

struct OutingsAnalyticsView: View {
    @EnvironmentObject var auth: AuthManager

    var vehicle: Vehicle? = nil

    @State private var analytics: OutingsAnalyticsResponse? = nil
    @State private var vehicles: [Vehicle] = []
    @State private var selectedVehicleId: Int? = nil
    @State private var selectedYear: Int? = nil
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var availableYears: [Int] {
        guard let data = analytics else { return [] }
        let years = Set(data.byMonth.compactMap { Int($0.month.prefix(4)) })
        return years.sorted(by: >)
    }

    private var filteredByMonth: [OutingsByMonth] {
        guard let data = analytics else { return [] }
        guard let year = selectedYear else { return data.byMonth }
        return data.byMonth.filter { $0.month.hasPrefix("\(year)") }
    }

    private var totalOutings: Int {
        filteredByMonth.reduce(0) { $0 + $1.count }
    }

    private var bestMonth: OutingsByMonth? {
        filteredByMonth.max(by: { $0.count < $1.count })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Filters row
                HStack(spacing: 4) {
                    if !vehicles.isEmpty {
                        Picker("Vehicle", selection: $selectedVehicleId) {
                            Text("All Vehicles").tag(nil as Int?)
                            ForEach(vehicles) { v in
                                Text(v.name).tag(v.id as Int?)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: selectedVehicleId) { _, _ in
                            Task { await loadAnalytics() }
                        }
                    }

                    if availableYears.count > 1 {
                        Picker("Year", selection: $selectedYear) {
                            Text("All Years").tag(nil as Int?)
                            ForEach(availableYears, id: \.self) { year in
                                Text(String(year)).tag(year as Int?)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)

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
                } else if analytics != nil {
                    // Summary card
                    HStack(spacing: 0) {
                        VStack(spacing: 4) {
                            Text("\(totalOutings)")
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.accentColor)
                            Text(selectedYear != nil ? "Outings in \(selectedYear!)" : "Total Outings")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)

                        if let best = bestMonth, best.count > 0 {
                            Divider().frame(height: 60)
                            VStack(spacing: 4) {
                                Text("\(best.count)")
                                    .font(.system(size: 44, weight: .bold, design: .rounded))
                                    .foregroundStyle(.green)
                                Text("Best Month")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(16)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)

                    // Monthly bar chart
                    if !filteredByMonth.isEmpty {
                        OutingsByMonthChart(byMonth: filteredByMonth)
                            .padding(.horizontal, 16)
                    }

                    if let data = analytics {
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

                        if filteredByMonth.isEmpty && data.byVehicle.isEmpty && data.topLocations.isEmpty {
                            ContentUnavailableView(
                                "No Outings Data",
                                systemImage: "map",
                                description: Text("Log some outings to see analytics here.")
                            )
                            .padding(.top, 40)
                        }
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .navigationTitle("Outings Summary")
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
            let result: OutingsAnalyticsResponse = try await APIClient.shared.get(path, token: token)
            analytics = result
            if selectedYear == nil {
                let currentYear = Calendar.current.component(.year, from: Date())
                let years = Set(result.byMonth.compactMap { Int($0.month.prefix(4)) }).sorted(by: >)
                selectedYear = years.contains(currentYear) ? currentYear : years.first
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Monthly Bar Chart

struct OutingsByMonthChart: View {
    let byMonth: [OutingsByMonth]

    private var chartData: [OutingsByMonth] {
        byMonth.sorted { $0.month < $1.month }
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
                            Text(monthLabel(from: s))
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

    private func monthLabel(from raw: String) -> String {
        let parts = raw.split(separator: "-")
        guard parts.count == 2, let month = Int(parts[1]) else { return raw }
        let symbols = Calendar.current.shortMonthSymbols
        guard month >= 1 && month <= 12 else { return raw }
        return symbols[month - 1]
    }
}
