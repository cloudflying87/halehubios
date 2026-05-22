import Charts
import PhotosUI
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
    @State private var selectedChart: VehicleChartMode = .pricePerGallon
    @State private var editingEvent: VehicleEvent? = nil
    @State private var detailEvent: VehicleEvent? = nil
    @State private var selectedSchedule: MaintenanceSchedule? = nil
    @State private var peekEvent: VehicleEvent? = nil
    @State private var showTrash = false
    @State private var showPhotoActionSheet = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var photoPickerItem: PhotosPickerItem? = nil
    @State private var isUploadingPhoto = false
    @State private var vehiclePhotoUrl: String?
    @State private var isUpdatingStatus = false

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
                // Hero image — tap to change photo
                Button {
                    showPhotoActionSheet = true
                } label: {
                    VehicleHeroImage(url: vehiclePhotoUrl ?? vehicle.photoUrl, icon: vehicle.typeIcon)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 20) {
                    // Title
                    VStack(alignment: .leading, spacing: 4) {
                        if !vehicle.subtitle.isEmpty {
                            Text(vehicle.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Stats cards — tappable to switch chart
                    if let s = stats {
                        StatsRow(vehicle: vehicle, stats: s, selectedChart: $selectedChart)
                    }

                    // Guest vehicle banner
                    if vehicle.status == "guest" {
                        HStack(spacing: 10) {
                            Image(systemName: "person.fill.questionmark")
                                .foregroundStyle(.teal)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Guest Vehicle")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.teal)
                                Text("You can log outings only. Gas and maintenance are tracked by the owner.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.teal.opacity(0.2)))
                    }

                    // Dynamic chart based on selected stat pill
                    let gasEvents = events.filter { $0.eventType == "gas" }
                    if vehicle.status != "guest" {
                        VehicleChartSection(events: gasEvents, vehicle: vehicle, mode: selectedChart)
                    }

                    // Maintenance due
                    if vehicle.status != "guest" && !dueSchedules.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Due Now", systemImage: "exclamationmark.triangle.fill")
                                .font(.headline)
                                .foregroundStyle(.orange)
                            ForEach(dueSchedules) { s in
                                MaintenanceRow(schedule: s) { selectedSchedule = s }
                            }
                        }
                        .padding(14)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }

                    // Maintenance schedule (hidden for guest vehicles)
                    if vehicle.status != "guest" {
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
                                    HStack {
                                        Text(month)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(monthEvents.count)")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.top, 4)
                                    ForEach(monthEvents) { event in
                                        EventCard(event: event, vehicle: vehicle) {
                                            // tap → edit
                                            editingEvent = event
                                        } onLongPress: {
                                            // long press → peek detail (handled via pressing state below)
                                        } onPeek: { isPressing in
                                            peekEvent = isPressing ? event : nil
                                        } onDelete: {
                                            Task { await deleteEvent(event) }
                                        }
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
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    // Photo
                    Button("Change Photo", systemImage: "camera") {
                        showPhotoActionSheet = true
                    }
                    Divider()
                    // Status
                    if vehicle.status == "guest" {
                        Button("Mark as My Vehicle", systemImage: "person.fill.checkmark") {
                            Task { await updateStatus("active") }
                        }
                    } else {
                        Button("Mark as Guest Vehicle", systemImage: "person.fill.questionmark") {
                            Task { await updateStatus("guest") }
                        }
                    }
                    Divider()
                    Button("Recently Deleted", systemImage: "trash") {
                        showTrash = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showLogSheet) {
            LogEventSheet(
                vehicle: vehicle,
                lockedEventType: vehicle.status == "guest" ? "outing" : nil
            ) {
                Task { await loadData() }
            }
        }
        .confirmationDialog("Vehicle Photo", isPresented: $showPhotoActionSheet, titleVisibility: .visible) {
            Button("Take Photo") { showCamera = true }
            Button("Choose from Library") { showPhotoPicker = true }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoPickerItem, matching: .images)
        .sheet(isPresented: $showCamera) {
            CameraPickerView { image in
                Task { await uploadPhoto(image) }
            }
        }
        .onChange(of: photoPickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await uploadPhoto(image)
                }
                photoPickerItem = nil
            }
        }
        .overlay {
            if isUploadingPhoto || isUpdatingStatus {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    ProgressView(isUploadingPhoto ? "Uploading photo…" : "Updating…")
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .sheet(item: $selectedSchedule) { schedule in
            MaintenanceActionSheet(schedule: schedule, vehicle: vehicle) {
                Task { await loadData() }
            }
            .environmentObject(auth)
        }
        .sheet(item: $editingEvent) { event in
            EditEventSheet(event: event, vehicle: vehicle, onSaved: {
                Task { await loadData() }
            }, onDeleted: {
                Task { await loadData() }
            })
            .environmentObject(auth)
        }
        .sheet(item: $detailEvent) { event in
            EventDetailSheet(event: event, vehicle: vehicle) {
                Task { await loadData() }
            }
            .environmentObject(auth)
        }
        .sheet(isPresented: $showTrash) {
            TrashView(vehicleId: vehicle.id) {
                Task { await loadData() }
            }
            .environmentObject(auth)
        }
        .overlay {
            if let peek = peekEvent {
                EventPeekOverlay(event: peek, vehicle: vehicle) {
                    peekEvent = nil
                }
            }
        }
        .task { await loadData() }
    }

    private func deleteEvent(_ event: VehicleEvent) async {
        guard let token = auth.accessToken else { return }
        try? await APIClient.shared.delete("/vehicles/events/\(event.id)/", token: token)
        await loadData()
    }

    private func uploadPhoto(_ image: UIImage) async {
        guard let token = auth.accessToken,
              let jpeg = image.jpegData(compressionQuality: 0.85) else { return }
        isUploadingPhoto = true
        do {
            let url = try await APIClient.shared.uploadVehiclePhoto(
                "/vehicles/\(vehicle.id)/photo/", imageData: jpeg, token: token
            )
            vehiclePhotoUrl = url
        } catch { }
        isUploadingPhoto = false
    }

    private func updateStatus(_ newStatus: String) async {
        guard let token = auth.accessToken else { return }
        isUpdatingStatus = true
        struct StatusPatch: Encodable { let status: String }
        let _: Vehicle? = try? await APIClient.shared.patch(
            "/vehicles/\(vehicle.id)/update/", body: StatusPatch(status: newStatus), token: token
        )
        isUpdatingStatus = false
        await loadData()
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

// MARK: - Chart Mode

enum VehicleChartMode: String, CaseIterable {
    case pricePerGallon = "Price/gal"
    case efficiency = "MPG/GPH"
    case fuelCost = "Fuel Cost"
}

// MARK: - Vehicle Chart Section

struct VehicleChartSection: View {
    let events: [VehicleEvent]
    let vehicle: Vehicle
    let mode: VehicleChartMode

    var body: some View {
        let sorted = events.sorted { $0.date < $1.date }

        switch mode {
        case .pricePerGallon:
            let priceEvents = sorted.filter { $0.pricePerGallon != nil }
            if priceEvents.count >= 2 {
                PriceHistoryChart(events: priceEvents)
            }

        case .efficiency:
            let effEvents = vehicle.isBoat
                ? sorted.filter { $0.gallonsperhour != nil }
                : sorted.filter { $0.milespergallon != nil }
            if effEvents.count >= 2 {
                EfficiencyChart(events: effEvents, isBoat: vehicle.isBoat)
            }

        case .fuelCost:
            let costEvents = sorted.filter { $0.totalCost != nil }
            if costEvents.count >= 2 {
                FuelCostChart(events: costEvents)
            }
        }
    }
}

// MARK: - Efficiency Chart (MPG or GPH over time)

struct EfficiencyChart: View {
    let events: [VehicleEvent]
    let isBoat: Bool

    private var values: [Double] { events.compactMap { isBoat ? $0.gallonsperhour : $0.milespergallon } }
    private var minVal: Double { values.min() ?? 0 }
    private var maxVal: Double { values.max() ?? 0 }
    private var avgVal: Double { values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count) }
    private var unit: String { isBoat ? "GPH" : "MPG" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isBoat ? "Gallons per Hour" : "Miles per Gallon")
                .font(.headline)

            Chart(events) { event in
                let val = isBoat ? event.gallonsperhour : event.milespergallon
                if let v = val {
                    LineMark(x: .value("Date", event.date), y: .value(unit, v))
                        .foregroundStyle(Color.accentColor)
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Date", event.date), y: .value(unit, v))
                        .foregroundStyle(Color.accentColor)
                        .symbolSize(30)
                }
            }
            .chartYScale(domain: (minVal * 0.9)...(maxVal * 1.1))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                }
            }
            .frame(height: 160)

            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text("Low")
                    Text(String(format: "%.1f", minVal)).fontWeight(.semibold).foregroundStyle(.primary)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("Avg")
                    Text(String(format: "%.1f", avgVal)).fontWeight(.semibold).foregroundStyle(.primary)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("High")
                    Text(String(format: "%.1f", maxVal)).fontWeight(.semibold).foregroundStyle(.primary)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Fuel Cost Chart

struct FuelCostChart: View {
    let events: [VehicleEvent]

    private var costs: [Double] { events.compactMap { $0.totalCost } }
    private var total: Double { costs.reduce(0, +) }
    private var avg: Double { costs.isEmpty ? 0 : total / Double(costs.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Fuel Cost per Fill-up")
                .font(.headline)

            Chart(events) { event in
                if let cost = event.totalCost {
                    BarMark(x: .value("Date", event.date, unit: .month), y: .value("Cost", cost))
                        .foregroundStyle(Color.accentColor)
                        .cornerRadius(4)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                }
            }
            .chartYAxis {
                AxisMarks { v in
                    AxisValueLabel { if let d = v.as(Double.self) { Text("$\(Int(d))") } }
                }
            }
            .frame(height: 160)

            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text("Avg/fill-up")
                    Text(String(format: "$%.2f", avg)).fontWeight(.semibold).foregroundStyle(.primary)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("Total spent")
                    Text(String(format: "$%.0f", total)).fontWeight(.semibold).foregroundStyle(.primary)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
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
    @Binding var selectedChart: VehicleChartMode

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
                    VehicleStatPill(label: "Avg MPG", value: String(format: "%.1f", mpg), icon: "fuelpump",
                                   isSelected: selectedChart == .efficiency) {
                        selectedChart = .efficiency
                    }
                }
                if let gph = stats.avgGPH {
                    VehicleStatPill(label: "Avg GPH", value: String(format: "%.2f", gph), icon: "fuelpump",
                                   isSelected: selectedChart == .efficiency) {
                        selectedChart = .efficiency
                    }
                }
                if let fuel = vehicle.fuelCostDouble, fuel > 0 {
                    VehicleStatPill(label: "Total Fuel", value: "$\(Int(fuel))", icon: "creditcard",
                                   isSelected: selectedChart == .fuelCost) {
                        selectedChart = .fuelCost
                    }
                }
                VehicleStatPill(label: "Price/gal", value: "", icon: "fuelpump.circle",
                               isSelected: selectedChart == .pricePerGallon) {
                    selectedChart = .pricePerGallon
                }
                if let maint = vehicle.maintenanceCostDouble, maint > 0 {
                    VehicleStatPill(label: "Total Service", value: "$\(Int(maint))", icon: "wrench")
                }
                if vehicle.isBoat {
                    VehicleStatPill(label: "This Month", value: "\(stats.outingsThisMonth)", icon: "map")
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
    var isSelected: Bool = false
    var action: (() -> Void)? = nil

    var body: some View {
        let content = VStack(spacing: 4) {
            Image(systemName: icon).font(.caption)
                .foregroundStyle(isSelected ? .white : .secondary)
            if !value.isEmpty {
                Text(value).font(.subheadline.bold())
                    .foregroundStyle(isSelected ? .white : .primary)
            }
            Text(label).font(.caption2)
                .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
        }
        .frame(minWidth: 72)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(isSelected ? Color.accentColor : Color(.systemGray6),
                    in: RoundedRectangle(cornerRadius: 10))

        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }
}

// MARK: - Maintenance Row

struct MaintenanceRow: View {
    let schedule: MaintenanceSchedule
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(schedule.categoryName ?? "Unknown")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
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
                if onTap != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Event Card

struct EventCard: View {
    let event: VehicleEvent
    let vehicle: Vehicle
    let onTap: () -> Void
    let onLongPress: () -> Void
    var onPeek: ((Bool) -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var swipeOffset: CGFloat = 0
    private let deleteRevealWidth: CGFloat = 76

    var accentColor: Color {
        switch event.eventType {
        case "gas": return .blue
        case "maintenance": return .orange
        case "outing": return .green
        default: return .secondary
        }
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            // Delete button revealed by swipe
            if onDelete != nil {
                Button(role: .destructive) {
                    withAnimation(.spring(response: 0.25)) { swipeOffset = 0 }
                    onDelete?()
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white)
                        .frame(width: deleteRevealWidth)
                        .frame(maxHeight: .infinity)
                }
                .background(Color.red, in: RoundedRectangle(cornerRadius: 10))
                // Slide in from trailing edge as card moves left
                .offset(x: deleteRevealWidth + swipeOffset)
            }

            // Card content
            cardContent
                .offset(x: swipeOffset)
                .gesture(
                    DragGesture(minimumDistance: 12, coordinateSpace: .local)
                        .onChanged { g in
                            // Only respond to mostly-horizontal drags
                            guard abs(g.translation.width) > abs(g.translation.height) else { return }
                            let t = g.translation.width
                            if t < 0 {
                                swipeOffset = max(t, onDelete != nil ? -deleteRevealWidth : 0)
                            } else {
                                swipeOffset = min(0, swipeOffset + t)
                            }
                        }
                        .onEnded { g in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                swipeOffset = (g.translation.width < -36 && onDelete != nil)
                                    ? -deleteRevealWidth : 0
                            }
                        }
                )
                .onTapGesture {
                    if swipeOffset != 0 {
                        withAnimation(.spring(response: 0.25)) { swipeOffset = 0 }
                    } else {
                        onTap()
                    }
                }
                .onLongPressGesture(minimumDuration: 0.4, pressing: { isPressing in
                    onPeek?(isPressing)
                }, perform: { onLongPress() })
        }
        .clipped()
    }

    private var cardContent: some View {
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
                if let items = event.maintenanceItems, !items.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(items) { item in
                            HStack {
                                Text(item.categoryName ?? "Service")
                                if !item.description.isEmpty {
                                    Text("· \(item.description)").foregroundStyle(.secondary)
                                }
                                Spacer()
                                if item.cost > 0 {
                                    Text(String(format: "$%.2f", item.cost))
                                }
                            }
                            .font(.caption)
                        }
                    }
                } else if let notes = event.notes, !notes.isEmpty {
                    Text(notes).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
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

// MARK: - Edit Event Sheet

struct EditEventSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    let event: VehicleEvent
    let vehicle: Vehicle
    let onSaved: () -> Void
    let onDeleted: (() -> Void)?

    @State private var date: Date
    @State private var odometer: String
    @State private var gallons: String
    @State private var pricePerGallon: String
    @State private var notes: String
    @State private var selectedLocationId: Int?
    @State private var locations: [VehicleLocation] = []
    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?

    init(event: VehicleEvent, vehicle: Vehicle, onSaved: @escaping () -> Void, onDeleted: (() -> Void)? = nil) {
        self.event = event
        self.vehicle = vehicle
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        _date = State(initialValue: event.date)
        let odomStr = event.miles.map(String.init) ?? event.hours.map { String(format: "%.1f", $0) } ?? ""
        _odometer = State(initialValue: odomStr)
        _gallons = State(initialValue: event.gallons.map { String(format: "%.3f", $0) } ?? "")
        _pricePerGallon = State(initialValue: event.pricePerGallon.map { String(format: "%.3f", $0) } ?? "")
        _notes = State(initialValue: event.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField(vehicle.isBoat ? "Hours" : "Odometer (miles)", text: $odometer)
                        .keyboardType(.decimalPad)

                    if event.eventType == "gas" {
                        TextField("Gallons", text: $gallons).keyboardType(.decimalPad)
                        TextField("Price per gallon", text: $pricePerGallon).keyboardType(.decimalPad)
                    }

                    if event.eventType == "outing" {
                        Picker("Location", selection: $selectedLocationId) {
                            Text("— None —").tag(nil as Int?)
                            ForEach(locations) { loc in
                                Text(loc.name).tag(loc.id as Int?)
                            }
                        }
                    }

                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                if let err = errorMessage {
                    Section {
                        Label(err, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.red).font(.subheadline)
                    }
                }

                if onDeleted != nil {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete Record", systemImage: "trash")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
            }
            .navigationTitle("Edit \(eventTypeTitle)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving || isDeleting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving || isDeleting { ProgressView() }
                    else { Button("Save") { Task { await save() } } }
                }
            }
            .confirmationDialog("Delete this record?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { await deleteRecord() } }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This cannot be undone.")
            }
        }
        .task {
            if event.eventType == "outing" {
                await loadLocations()
            }
        }
    }

    private var eventTypeTitle: String {
        switch event.eventType {
        case "gas": return "Fill-up"
        case "maintenance": return "Service"
        case "outing": return "Outing"
        default: return "Event"
        }
    }

    private func loadLocations() async {
        guard let token = auth.accessToken else { return }
        locations = (try? await APIClient.shared.get("/vehicles/locations/", token: token)) ?? []
        if let name = event.locationName {
            selectedLocationId = locations.first(where: { $0.name == name })?.id
        }
    }

    private func deleteRecord() async {
        guard let token = auth.accessToken else { return }
        isDeleting = true
        do {
            try await APIClient.shared.delete("/vehicles/events/\(event.id)/", token: token)
            onDeleted?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isDeleting = false
    }

    private func save() async {
        guard let token = auth.accessToken else { return }
        isSaving = true
        errorMessage = nil

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        var body = EditEventRequest(date: formatter.string(from: date))
        if vehicle.isBoat {
            body.hours = Double(odometer)
        } else {
            body.miles = Int(odometer)
        }
        body.gallons = Double(gallons)
        body.pricePerGallon = Double(pricePerGallon)
        body.notes = notes.isEmpty ? nil : notes
        if event.eventType == "outing" {
            body.locationName = locations.first(where: { $0.id == selectedLocationId })?.name ?? ""
        }

        do {
            let _: VehicleEvent = try await APIClient.shared.patch(
                "/vehicles/events/\(event.id)/", body: body, token: token
            )
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}

// MARK: - Event Peek Overlay

struct EventPeekOverlay: View {
    let event: VehicleEvent
    let vehicle: Vehicle
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: event.eventIcon)
                        .font(.title2)
                        .foregroundStyle(eventColor)
                    Text(eventTitle)
                        .font(.headline)
                    Spacer()
                    Button { onDismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.title3)
                    }
                }

                Divider()

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(statRows, id: \.0) { label, value in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(label).font(.caption).foregroundStyle(.secondary)
                            Text(value).font(.subheadline.weight(.medium))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let notes = event.notes, !notes.isEmpty {
                    Text(notes).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 20)
            .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .animation(.easeOut(duration: 0.18), value: true)
    }

    private var eventColor: Color {
        switch event.eventType {
        case "gas": return .blue
        case "maintenance": return .orange
        case "outing": return .green
        default: return .secondary
        }
    }

    private var eventTitle: String {
        switch event.eventType {
        case "gas": return "Gas Fill-up"
        case "maintenance": return event.maintenanceCategoryName ?? "Maintenance"
        case "outing": return event.locationName ?? "Outing"
        default: return event.eventType.capitalized
        }
    }

    private var statRows: [(String, String)] {
        var rows: [(String, String)] = []
        rows.append(("Date", event.date.formatted(.dateTime.month().day().year())))
        if let miles = event.miles { rows.append(("Odometer", "\(miles) mi")) }
        if let hours = event.hours { rows.append(("Hours", String(format: "%.1f hr", hours))) }
        if let gal = event.gallons { rows.append(("Gallons", String(format: "%.3f", gal))) }
        if let ppg = event.pricePerGallon { rows.append(("Price/gal", String(format: "$%.3f", ppg))) }
        if let cost = event.totalCost { rows.append(("Total cost", String(format: "$%.2f", cost))) }
        if let mpg = event.milespergallon { rows.append(("MPG", String(format: "%.1f", mpg))) }
        if let gph = event.gallonsperhour { rows.append(("GPH", String(format: "%.2f", gph))) }
        return rows
    }
}

// MARK: - Event Detail Sheet

struct EventDetailSheet: View {
    let event: VehicleEvent
    let vehicle: Vehicle
    var onRefresh: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var auth: AuthManager
    @State private var showEditSheet = false

    var body: some View {
        NavigationStack {
            List {
                Section("Event") {
                    LabeledContent("Date", value: event.date.formatted(date: .long, time: .omitted))
                    if let loc = event.locationName {
                        LabeledContent("Location", value: loc)
                    }
                    if let miles = event.miles {
                        LabeledContent(vehicle.isBoat ? "Hours" : "Odometer",
                                       value: "\(miles.formatted()) \(vehicle.unitAbbrev)")
                    }
                    if let hours = event.hours {
                        LabeledContent("Hours", value: String(format: "%.1f hrs", hours))
                    }
                }

                if event.eventType == "gas" {
                    Section("Fuel") {
                        if let g = event.gallons {
                            LabeledContent("Gallons", value: String(format: "%.3f", g))
                        }
                        if let ppg = event.pricePerGallon {
                            LabeledContent("Price/gal", value: String(format: "$%.3f", ppg))
                        }
                        if let cost = event.totalCost {
                            LabeledContent("Total", value: String(format: "$%.2f", cost))
                        }
                        if let mpg = event.milespergallon {
                            LabeledContent("MPG", value: String(format: "%.1f", mpg))
                        }
                        if let gph = event.gallonsperhour {
                            LabeledContent("GPH", value: String(format: "%.2f", gph))
                        }
                    }
                }

                if let items = event.maintenanceItems, !items.isEmpty {
                    Section("Service Items") {
                        ForEach(items) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.categoryName ?? "Service")
                                    if !item.description.isEmpty {
                                        Text(item.description).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if item.cost > 0 {
                                    Text(String(format: "$%.2f", item.cost)).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if let cost = event.totalCost, cost > 0 {
                            LabeledContent("Total", value: String(format: "$%.2f", cost))
                                .fontWeight(.semibold)
                        }
                    }
                }

                if let notes = event.notes, !notes.isEmpty {
                    Section("Notes") {
                        Text(notes)
                    }
                }
            }
            .navigationTitle(eventTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { showEditSheet = true }
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditEventSheet(event: event, vehicle: vehicle, onSaved: {
                onRefresh?()
                dismiss()
            }, onDeleted: {
                onRefresh?()
                dismiss()
            })
            .environmentObject(auth)
        }
    }

    private var eventTitle: String {
        switch event.eventType {
        case "gas": return "Gas Fill-up"
        case "maintenance": return event.maintenanceCategoryName ?? "Service"
        case "outing": return event.locationName ?? "Outing"
        default: return event.eventType.capitalized
        }
    }
}

// MARK: - Maintenance Action Sheet

struct MaintenanceActionSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    let schedule: MaintenanceSchedule
    let vehicle: Vehicle
    let onRefresh: () -> Void

    @State private var showLogSheet = false
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Due Service") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(schedule.categoryName ?? "Maintenance")
                                .font(.headline)
                            if let reason = schedule.isDueReason, !reason.isEmpty {
                                Text(reason).font(.subheadline).foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        Text("DUE")
                            .font(.caption.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.orange, in: Capsule())
                    }
                }

                Section("History") {
                    if let last = schedule.lastPerformed {
                        LabeledContent("Last Performed", value: last.formatted(date: .long, time: .omitted))
                    } else {
                        Text("No record of previous service").foregroundStyle(.secondary)
                    }
                    if let miles = schedule.lastMiles {
                        LabeledContent("At Odometer", value: "\(miles.formatted()) \(vehicle.unitAbbrev)")
                    }
                    if let interval = schedule.intervalMiles {
                        LabeledContent("Interval", value: "Every \(interval.formatted()) \(vehicle.unitAbbrev)")
                    }
                    if let interval = schedule.intervalHours {
                        LabeledContent("Interval", value: "Every \(interval) hrs")
                    }
                    if let interval = schedule.intervalDays {
                        LabeledContent("Interval", value: "Every \(interval) days")
                    }
                }

                Section {
                    Button {
                        showLogSheet = true
                    } label: {
                        Label("Log Service Now", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.body.weight(.medium))
                    }
                }

                Section("Snooze Reminder") {
                    Button {
                        Task { await snooze(days: 7) }
                    } label: {
                        Label("Remind Me in 1 Week", systemImage: "clock.arrow.circlepath")
                    }
                    Button {
                        Task { await snooze(days: 30) }
                    } label: {
                        Label("Remind Me in 1 Month", systemImage: "clock.arrow.circlepath")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Remove from Schedule", systemImage: "trash")
                    }
                    .disabled(isDeleting)
                }

                if let err = errorMessage {
                    Section {
                        Label(err, systemImage: "exclamationmark.circle.fill").foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Maintenance Due")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .confirmationDialog(
                "Remove \(schedule.categoryName ?? "this item") from the maintenance schedule?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    Task { await deleteSchedule() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone.")
            }
        }
        .sheet(isPresented: $showLogSheet) {
            LogEventSheet(vehicle: vehicle, prefilledCategoryId: schedule.categoryId) {
                onRefresh()
                dismiss()
            }
        }
    }

    private func snooze(days: Int) async {
        guard let token = auth.accessToken else { return }
        errorMessage = nil
        struct SnoozeBody: Encodable { let days: Int }
        do {
            let _: MaintenanceSchedule = try await APIClient.shared.post(
                "/vehicles/maintenance/\(schedule.id)/snooze/",
                body: SnoozeBody(days: days),
                token: token
            )
            onRefresh()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteSchedule() async {
        guard let token = auth.accessToken else { return }
        isDeleting = true
        errorMessage = nil
        do {
            try await APIClient.shared.delete(
                "/vehicles/maintenance/\(schedule.id)/", token: token
            )
            onRefresh()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isDeleting = false
        }
    }
}
