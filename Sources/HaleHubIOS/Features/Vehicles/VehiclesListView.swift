import SwiftUI

struct VehiclesListView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = VehiclesViewModel()

    var body: some View {
        Group {
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
                    if vm.availableFilters.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(vm.availableFilters) { filter in
                                    FilterChip(
                                        label: filter.rawValue,
                                        isSelected: vm.typeFilter == filter
                                    ) { vm.typeFilter = filter }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .padding(.vertical, 8)
                        Divider()
                    }
                    List(vm.filtered) { vehicle in
                        NavigationLink(destination: VehicleDetailView(vehicle: vehicle)) {
                            VehicleRow(vehicle: vehicle)
                        }
                    }
                    .listStyle(.plain)
                }
                .refreshable { await vm.load(token: auth.accessToken ?? "") }
            }
        }
        .navigationTitle("Vehicles")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await vm.load(token: auth.accessToken ?? "") } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(vm.isLoading)
            }
        }
        .task { await vm.load(token: auth.accessToken ?? "") }
        .alert("Error", isPresented: .constant(vm.error != nil)) {
            Button("OK") { vm.error = nil }
        } message: { Text(vm.error ?? "") }
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
                    if let mileage = vehicle.currentMileage {
                        Label("\(mileage.formatted()) \(vehicle.unitAbbrev)", systemImage: "gauge.with.dots.needle.67percent")
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
