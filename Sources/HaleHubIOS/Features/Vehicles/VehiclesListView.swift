import SwiftUI

struct VehiclesListView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = VehiclesViewModel()

    @Environment(\.horizontalSizeClass) private var hSize
    @State private var selectedVehicleID: Vehicle.ID?

    private var allVehicles: [Vehicle] { vm.filtered + vm.guestVehicles }

    var body: some View {
        Group {
            if hSize == .regular {
                splitBody
            } else {
                stackBody
            }
        }
        .task { await vm.load(token: auth.accessToken ?? "") }
        .alert("Error", isPresented: .constant(vm.error != nil)) {
            Button("OK") { vm.error = nil }
        } message: { Text(vm.error ?? "") }
    }

    // MARK: iPhone — push stack

    private var stackBody: some View {
        vehiclesContent(selectable: false)
            .navigationTitle("Vehicles")
            .toolbar { vehicleToolbar }
    }

    // MARK: iPad — split view

    private var splitBody: some View {
        NavigationSplitView {
            vehiclesContent(selectable: true)
                .navigationTitle("Vehicles")
                .toolbar { vehicleToolbar }
        } detail: {
            NavigationStack {
                if let id = selectedVehicleID, let vehicle = allVehicles.first(where: { $0.id == id }) {
                    VehicleDetailView(vehicle: vehicle).id(id)
                } else {
                    ContentUnavailableView(
                        "Select a Vehicle",
                        systemImage: "car",
                        description: Text("Pick a vehicle to see its details and event log.")
                    )
                }
            }
        }
    }

    // MARK: Shared content

    @ViewBuilder
    private func vehiclesContent(selectable: Bool) -> some View {
        if vm.isLoading && vm.vehicles.isEmpty {
            ProgressView("Loading vehicles…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.vehicles.isEmpty {
            ContentUnavailableView(
                "No Vehicles",
                systemImage: "car",
                description: Text("Add vehicles on the website.")
            )
        } else {
            VStack(spacing: 0) {
                filterChips
                if selectable {
                    List(selection: $selectedVehicleID) {
                        ForEach(vm.filtered) { vehicle in
                            VehicleRow(vehicle: vehicle).tag(vehicle.id)
                        }
                        guestSection(selectable: true)
                    }
                    .listStyle(.plain)
                    .refreshable { await vm.load(token: auth.accessToken ?? "") }
                } else {
                    List {
                        ForEach(vm.filtered) { vehicle in
                            NavigationLink(destination: VehicleDetailView(vehicle: vehicle)) {
                                VehicleRow(vehicle: vehicle)
                            }
                        }
                        guestSection(selectable: false)
                    }
                    .listStyle(.plain)
                    .refreshable { await vm.load(token: auth.accessToken ?? "") }
                }
            }
        }
    }

    @ViewBuilder
    private var filterChips: some View {
        if vm.availableFilters.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.availableFilters) { filter in
                        FilterChip(label: filter.rawValue, isSelected: vm.typeFilter == filter) {
                            vm.typeFilter = filter
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 8)
            Divider()
        }
    }

    @ViewBuilder
    private func guestSection(selectable: Bool) -> some View {
        if !vm.guestVehicles.isEmpty {
            if vm.showGuestVehicles {
                Section {
                    ForEach(vm.guestVehicles) { vehicle in
                        if selectable {
                            VehicleRow(vehicle: vehicle).tag(vehicle.id)
                        } else {
                            NavigationLink(destination: VehicleDetailView(vehicle: vehicle)) {
                                VehicleRow(vehicle: vehicle)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Guest Vehicles")
                        Spacer()
                        Button("Hide") { vm.showGuestVehicles = false }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Button {
                    vm.showGuestVehicles = true
                } label: {
                    Label(
                        "Show \(vm.guestVehicles.count) guest vehicle\(vm.guestVehicles.count == 1 ? "" : "s")",
                        systemImage: "person.badge.clock"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .listRowSeparator(.hidden)
            }
        }
    }

    @ToolbarContentBuilder
    private var vehicleToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { Task { await vm.load(token: auth.accessToken ?? "") } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(vm.isLoading)
        }
        ToolbarItem(placement: .primaryAction) {
            NavigationLink {
                OutingsAnalyticsView().environmentObject(auth)
            } label: {
                Image(systemName: "map")
            }
        }
    }
}

struct VehicleRow: View {
    let vehicle: Vehicle

    var body: some View {
        HStack(spacing: 12) {
            VehicleThumbnail(url: vehicle.photoUrl, icon: vehicle.typeIcon)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(vehicle.name).font(.headline)
                    if vehicle.status == "guest" {
                        Text("Guest")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.teal)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.teal.opacity(0.12), in: Capsule())
                    }
                }

                if !vehicle.subtitle.isEmpty {
                    Text(vehicle.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 14) {
                    if vehicle.isBoat, let hours = vehicle.currentHours {
                        Label(String(format: "%.1f hrs", hours), systemImage: "gauge.with.dots.needle.67percent")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else if !vehicle.isBoat, let mileage = vehicle.currentMileage {
                        Label("\(mileage.formatted()) mi", systemImage: "gauge.with.dots.needle.67percent")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if let fuel = vehicle.fuelCostDouble, fuel > 0 {
                        Label("$\(Int(fuel)) fuel", systemImage: "fuelpump")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}

struct VehicleThumbnail: View {
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
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    var placeholderView: some View {
        Color(.systemGray5)
            .overlay(
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            )
    }
}
