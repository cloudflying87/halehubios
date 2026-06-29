import SwiftUI

@MainActor
final class BoatGlanceViewModel: ObservableObject {
    @Published var events: [VehicleEvent] = []
    @Published var isLoading = false
    @Published var error: String?

    let vehicle: Vehicle
    init(vehicle: Vehicle) { self.vehicle = vehicle }

    func load(token: String) async {
        isLoading = true
        error = nil
        do {
            let resp: PaginatedResponse<VehicleEvent> =
                try await APIClient.shared.get("/vehicles/\(vehicle.id)/events/?page_size=200", token: token)
            events = resp.results
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    // Events arrive newest-first from the API.
    private var gasEvents: [VehicleEvent] { events.filter { $0.eventType == "gas" } }
    private var outings: [VehicleEvent] { events.filter { $0.eventType == "outing" } }

    var lastFillup: VehicleEvent? { gasEvents.first }

    /// Most recent hour-meter reading across all events (falls back to vehicle).
    var currentHours: Double? {
        vehicle.currentHours ?? events.compactMap { $0.hours }.max()
    }

    /// Engine hours run since the last fuel fill-up (nil if not computable).
    var hoursSinceFillup: Double? {
        guard let cur = currentHours, let last = lastFillup?.hours else { return nil }
        return max(0, cur - last)
    }

    var outingsTotal: Int { outings.count }

    var outingsThisYear: Int {
        let y = Calendar.current.component(.year, from: Date())
        return outings.filter { Calendar.current.component(.year, from: $0.date) == y }.count
    }

    var outingsSinceFillup: Int? {
        guard let lastDate = lastFillup?.date else { return nil }
        return outings.filter { $0.date >= lastDate }.count
    }

    var avgGPH: Double? {
        let vals = gasEvents.compactMap { $0.gallonsperhour }
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }
}

struct BoatGlanceView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm: BoatGlanceViewModel
    @State private var typedHours = ""
    private var token: String { auth.accessToken ?? "" }

    init(vehicle: Vehicle) {
        _vm = StateObject(wrappedValue: BoatGlanceViewModel(vehicle: vehicle))
    }

    /// Current hours: the typed gauge reading if entered, else the latest logged reading.
    private var effectiveCurrentHours: Double? {
        if let typed = Double(typedHours.trimmingCharacters(in: .whitespaces)) { return typed }
        return vm.currentHours
    }

    /// Hours run since the last fuel fill-up, using the typed/derived current hours.
    private var hoursSince: Double? {
        guard let cur = effectiveCurrentHours, let last = vm.lastFillup?.hours else { return nil }
        return max(0, cur - last)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                hoursCard
                outingsCard
                if let gph = vm.avgGPH {
                    miniCard("Average burn", String(format: "%.2f GPH", gph), "fuelpump.fill")
                }
                if let cur = vm.currentHours {
                    miniCard("Engine hours", String(format: "%.1f hrs", cur), "gauge.with.needle")
                }
            }
            .padding(16)
        }
        .navigationTitle("\(vm.vehicle.name) — At a Glance")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load(token: token) }
        .refreshable { await vm.load(token: token) }
        .overlay {
            if vm.isLoading && vm.events.isEmpty { ProgressView() }
        }
        .alert("Error", isPresented: .init(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK") {}
        } message: { Text(vm.error ?? "") }
    }

    private var hoursCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Hours since last fill-up", systemImage: "fuelpump").font(.subheadline).foregroundStyle(.secondary)
            if let h = hoursSince {
                Text(String(format: "%.1f hrs", h)).font(.system(size: 40, weight: .bold))
            } else {
                Text("—").font(.system(size: 40, weight: .bold)).foregroundStyle(.secondary)
            }
            if let last = vm.lastFillup {
                Text("Last fill-up \(last.date.formatted(date: .abbreviated, time: .omitted))"
                     + (last.hours.map { String(format: " at %.1f hrs", $0) } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("No fuel fill-ups logged yet.").font(.caption).foregroundStyle(.secondary)
            }

            Divider()
            HStack {
                Text("Current hour-meter").font(.subheadline)
                Spacer()
                TextField(vm.currentHours.map { String(format: "%.1f", $0) } ?? "e.g. 342.5",
                          text: $typedHours)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
                Text("hrs").foregroundStyle(.secondary)
            }
            Text("Type the reading on your gauge to see hours run since fueling — or log it on an outing and it fills in automatically.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var outingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Outings", systemImage: "water.waves").font(.subheadline).foregroundStyle(.secondary)
            HStack {
                outingStat("\(vm.outingsTotal)", "Total")
                Spacer()
                outingStat("\(vm.outingsThisYear)", "This year")
                Spacer()
                outingStat(vm.outingsSinceFillup.map(String.init) ?? "—", "Since fill-up")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func outingStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2).fontWeight(.bold)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func miniCard(_ label: String, _ value: String, _ icon: String) -> some View {
        HStack {
            Label(label, systemImage: icon).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.headline)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
