import Charts
import SwiftUI

enum EventTypeFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case gas = "Gas"
    case maintenance = "Service"
    case outing = "Outings"
    var id: String { rawValue }
    var queryValue: String? {
        switch self {
        case .all: return nil
        case .gas: return "gas"
        case .maintenance: return "maintenance"
        case .outing: return "outing"
        }
    }
}

struct VehicleDetailView: View {
    @EnvironmentObject var auth: AuthManager
    let vehicle: Vehicle

    @State private var events: [VehicleEvent] = []
    @State private var schedules: [MaintenanceSchedule] = []
    @State private var eventFilter: EventTypeFilter = .all
    @State private var showLogSheet = false
    @State private var isLoading = false
    @State private var stats: VehicleStats?

    var dueSchedules: [MaintenanceSchedule] { schedules.filter { $0.isDue } }
    var filteredEvents: [VehicleEvent] {
        guard let type = eventFilter.queryValue else { return events }
        return events.filter { $0.eventType == type }
    }
    var groupedEvents: [(String, [VehicleEvent])] {
        let grouped = Dictionary(grouping: filteredEvents) { event -> String in
            let comps = Calendar.current.dateComponents([.year, .month], from: event.date)
            let date = Calendar.current.date(from: comps) ?? event.date
            return date.formatted(.dateTime.month(.wide).year())
        }
        return grouped.sorted {
            guard let a = $0.value.first?.date, let b = $1.value.first?.date else { return false }
            return a > b
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Hero image
                VehicleHeroImage(url: vehicle.photoUrl, icon: vehicle.typeIcon)

                VStack(alignment: .leading, spacing: 20) {
                    // Title
                    VStack(alignment: .leading, spacing: 4) {
                        if !vehicle.subtitle.isEmpty {
                            Text(vehicle.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Stats cards
                    if let s = stats {
                        StatsRow(vehicle: vehicle, stats: s)
                    }

                    // Price per gallon chart
                    let priceEvents = events.filter { $0.eventType == "gas" && $0.pricePerGallon != nil }
                    if priceEvents.count >= 2 {
                        PriceHistoryChart(events: priceEvents)
                    }

                    // Maintenance due
                    if !dueSchedules.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Due Now", systemImage: "exclamationmark.triangle.fill")
                                .font(.headline)
                                .foregroundStyle(.orange)
                            ForEach(dueSchedules) { s in
                                MaintenanceRow(schedule: s)
                            }
                        }
                        .padding(14)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }

                    // Maintenance schedule
                    let okSchedules = schedules.filter { !$0.isDue }
                    if !okSchedules.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Maintenance Schedule")
                                .font(.headline)
                            ForEach(okSchedules) { s in
                                MaintenanceRow(schedule: s)
                            }
                        }
                    }

                    Divider()

                    // Event history
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("History")
                                .font(.headline)
                            Spacer()
                            Text("\(filteredEvents.count) events")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        // Event type filter chips
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(EventTypeFilter.allCases) { filter in
                                    FilterChip(
                                        label: filter.rawValue,
                                        isSelected: eventFilter == filter
                                    ) { eventFilter = filter }
                                }
                            }
                        }

                        if filteredEvents.isEmpty && !isLoading {
                            Text("No events yet.")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 20)
                        } else {
                            ForEach(groupedEvents, id: \.0) { month, monthEvents in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(month)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 4)
                                    ForEach(monthEvents) { event in
                                        EventCard(event: event, vehicle: vehicle)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle(vehicle.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showLogSheet = true } label: {
                    Label("Log Event", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showLogSheet) {
            LogEventSheet(vehicle: vehicle) {
                Task { await loadData() }
            }
        }
        .task { await loadData() }
    }

    private func loadData() async {
        guard let token = auth.accessToken else { return }
        isLoading = true
        async let eventsTask: PaginatedResponse<VehicleEvent> = APIClient.shared.get(
            "/vehicles/\(vehicle.id)/events/?page_size=200", token: token
        )
        async let schedulesTask: PaginatedResponse<MaintenanceSchedule> = APIClient.shared.get(
            "/vehicles/\(vehicle.id)/maintenance/", token: token
        )
        if let e = try? await eventsTask {
            events = e.results
            stats = VehicleStats.compute(from: e.results, vehicle: vehicle)
        }
        if let s = try? await schedulesTask { schedules = s.results }
        isLoading = false
    }
}

// MARK: - Hero Image

struct VehicleHeroImage: View {
    let url: String?
    let icon: String
    var body: some View {
        Group {
            if let urlString = url, let imageURL = URL(string: urlString) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: placeholderView
                    }
                }
            } else {
                placeholderView
            }
        }
        .frame(maxWidth: .infinity).frame(height: 220).clipped()
    }
    var placeholderView: some View {
        Color(.systemGray5).overlay(
            Image(systemName: icon).font(.system(size: 52)).foregroundStyle(.tertiary)
        )
    }
}

// MARK: - Price History Chart

struct PriceHistoryChart: View {
    let events: [VehicleEvent]

    private var sorted: [VehicleEvent] { events.sorted { $0.date < $1.date } }
    private var prices: [Double] { sorted.compactMap { $0.pricePerGallon } }
    private var minPrice: Double { prices.min() ?? 0 }
    private var maxPrice: Double { prices.max() ?? 0 }
    private var avgPrice: Double { prices.isEmpty ? 0 : prices.reduce(0, +) / Double(prices.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Price per Gallon")
                .font(.headline)

            Chart(sorted) { event in
                if let price = event.pricePerGallon {
                    LineMark(
                        x: .value("Date", event.date),
                        y: .value("Price", price)
                    )
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", event.date),
                        y: .value("Price", price)
                    )
                    .foregroundStyle(Color.accentColor)
                    .symbolSize(30)
                }
            }
            .chartYScale(domain: (minPrice * 0.95)...(maxPrice * 1.05))
            .chartYAxis {
                AxisMarks(format: .currency(code: "USD").precision(.fractionLength(2)))
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                }
            }
            .frame(height: 160)

            HStack(spacing: 0) {
                statLabel("Low", value: minPrice)
                Spacer()
                statLabel("Avg", value: avgPrice)
                Spacer()
                statLabel("High", value: maxPrice)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
    }

    private func statLabel(_ title: String, value: Double) -> some View {
        VStack(spacing: 2) {
            Text(title)
            Text(String(format: "$%.3f", value)).fontWeight(.semibold).foregroundStyle(.primary)
        }
    }
}

// MARK: - Stats Row

struct StatsRow: View {
    let vehicle: Vehicle
    let stats: VehicleStats

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if let mileage = vehicle.currentMileage {
                    VehicleStatPill(
                        label: vehicle.isBoat ? "Hours" : "Mileage",
                        value: "\(mileage.formatted()) \(vehicle.unitAbbrev)",
                        icon: "gauge.with.dots.needle.67percent"
                    )
                }
                if let mpg = stats.avgMPG {
                    VehicleStatPill(label: "Avg MPG", value: String(format: "%.1f", mpg), icon: "fuelpump")
                }
                if let gph = stats.avgGPH {
                    VehicleStatPill(label: "Avg GPH", value: String(format: "%.2f", gph), icon: "fuelpump")
                }
                if let fuel = vehicle.fuelCostDouble, fuel > 0 {
                    VehicleStatPill(label: "Total Fuel", value: "$\(Int(fuel))", icon: "creditcard")
                }
                if let maint = vehicle.maintenanceCostDouble, maint > 0 {
                    VehicleStatPill(label: "Total Service", value: "$\(Int(maint))", icon: "wrench")
                }
                VehicleStatPill(label: "Gas Logs", value: "\(stats.gasEventCount)", icon: "fuelpump.fill")
                VehicleStatPill(label: "Service Logs", value: "\(stats.maintenanceEventCount)", icon: "wrench.fill")
            }
        }
    }
}

struct VehicleStatPill: View {
    let label: String
    let value: String
    let icon: String
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(minWidth: 72)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Maintenance Row

struct MaintenanceRow: View {
    let schedule: MaintenanceSchedule
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(schedule.categoryName ?? "Unknown").font(.subheadline)
                if let reason = schedule.isDueReason, !reason.isEmpty {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                } else if let last = schedule.lastPerformed {
                    Text("Last: \(last, style: .date)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if schedule.isDue {
                Text("DUE")
                    .font(.caption.bold()).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.orange, in: Capsule())
            } else {
                Text("OK").font(.caption.bold()).foregroundStyle(.green)
            }
        }
    }
}

// MARK: - Event Card

struct EventCard: View {
    let event: VehicleEvent
    let vehicle: Vehicle

    var accentColor: Color {
        switch event.eventType {
        case "gas": return .blue
        case "maintenance": return .orange
        case "outing": return .green
        default: return .secondary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.eventIcon)
                .font(.subheadline)
                .foregroundStyle(accentColor)
                .frame(width: 28, height: 28)
                .background(accentColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(eventTitle).font(.subheadline.weight(.medium))
                    Spacer()
                    Text(event.date, style: .date).font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    if let mpg = event.milespergallon {
                        Text(String(format: "%.1f MPG", mpg)).font(.caption).foregroundStyle(.secondary)
                    }
                    if let gph = event.gallonsperhour {
                        Text(String(format: "%.2f GPH", gph)).font(.caption).foregroundStyle(.secondary)
                    }
                    if let cost = event.totalCost {
                        Text(String(format: "$%.2f", cost)).font(.caption).foregroundStyle(.secondary)
                    }
                    if let miles = event.miles {
                        Text("\(miles.formatted()) \(vehicle.unitAbbrev)").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                if let notes = event.notes, !notes.isEmpty {
                    Text(notes).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
    }

    var eventTitle: String {
        switch event.eventType {
        case "gas": return "Gas Fill-up"
        case "maintenance": return event.maintenanceCategoryName ?? "Service"
        case "outing": return event.locationName ?? "Outing"
        default: return event.eventType.capitalized
        }
    }
}
