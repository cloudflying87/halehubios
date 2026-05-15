import Foundation

enum VehicleTypeFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case car = "Cars"
    case boat = "Boats"
    case motorcycle = "Motorcycles"
    case rv = "RVs"
    var id: String { rawValue }
    var queryValue: String? {
        switch self {
        case .all: return nil
        case .car: return "car"
        case .boat: return "boat"
        case .motorcycle: return "motorcycle"
        case .rv: return "rv"
        }
    }
}

@MainActor
class VehiclesViewModel: ObservableObject {
    @Published var vehicles: [Vehicle] = []
    @Published var maintenanceCategories: [MaintenanceCategory] = []
    @Published var typeFilter: VehicleTypeFilter = .all
    @Published var isLoading = false
    @Published var error: String?

    var filtered: [Vehicle] {
        guard typeFilter != .all, let typeVal = typeFilter.queryValue else { return vehicles }
        return vehicles.filter { $0.vehicleType == typeVal }
    }

    // Only show filter chips for types actually present in the list
    var availableFilters: [VehicleTypeFilter] {
        let types = Set(vehicles.map { $0.vehicleType })
        return VehicleTypeFilter.allCases.filter { filter in
            filter == .all || types.contains(filter.queryValue ?? "")
        }
    }

    func load(token: String) async {
        isLoading = true
        error = nil
        async let vehiclesTask: PaginatedResponse<Vehicle> = APIClient.shared.get("/vehicles/", token: token)
        async let categoriesTask: [MaintenanceCategory] = APIClient.shared.get("/vehicles/maintenance-categories/", token: token)
        if let v = try? await vehiclesTask { vehicles = v.results }
        if let c = try? await categoriesTask { maintenanceCategories = c }
        isLoading = false
    }
}
