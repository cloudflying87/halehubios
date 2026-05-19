import Foundation

struct Vehicle: Identifiable, Codable, Sendable {
    let id: Int
    let name: String
    let make: String?
    let model: String?
    let year: Int?
    let vehicleType: String
    let status: String
    let isActive: Bool
    let photoUrl: String?
    let currentMileage: Int?
    let currentHours: Double?
    let totalFuelCost: Double?
    let totalMaintenanceCost: Double?
    let displayUnit: String?

    var isBoat: Bool { vehicleType == "boat" || vehicleType == "other" }
    var unitAbbrev: String { isBoat ? "hrs" : "mi" }
    var subtitle: String {
        [year.map(String.init), make, model]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }
    var typeIcon: String {
        switch vehicleType {
        case "boat": return "ferry.fill"
        case "motorcycle": return "bicycle"
        case "rv": return "bus.fill"
        default: return "car.fill"
        }
    }
    var fuelCostDouble: Double? { totalFuelCost }
    var maintenanceCostDouble: Double? { totalMaintenanceCost }
}

struct VehicleEvent: Identifiable, Codable, Hashable, Sendable {
    let id: Int
    let eventType: String
    let date: Date
    let miles: Int?
    let hours: Double?
    let gallons: Double?
    let pricePerGallon: Double?
    let totalCost: Double?
    let milespergallon: Double?
    let gallonsperhour: Double?
    let maintenanceCategoryName: String?
    let maintenanceItems: [MaintenanceItemRecord]?
    let locationName: String?
    let notes: String?
    let createdAt: Date?

    var eventIcon: String {
        switch eventType {
        case "gas": return "fuelpump.fill"
        case "maintenance": return "wrench.fill"
        case "outing": return "map.fill"
        default: return "clock.fill"
        }
    }
    var eventColor: String {
        switch eventType {
        case "gas": return "blue"
        case "maintenance": return "orange"
        case "outing": return "green"
        default: return "gray"
        }
    }
}

struct MaintenanceCategory: Identifiable, Codable, Sendable {
    let id: Int
    let name: String
    let description: String?
    let vehicleTypes: [String]?
}

struct MaintenanceSchedule: Identifiable, Codable, Hashable, Sendable {
    let id: Int
    let categoryId: Int?
    let categoryName: String?
    let intervalMiles: Int?
    let intervalHours: Int?
    let intervalDays: Int?
    let lastPerformed: Date?
    let lastMiles: Int?
    let isDue: Bool
    let isDueReason: String?
    let snoozedUntil: Date?
}

struct MaintenanceItemRecord: Identifiable, Codable, Hashable, Sendable {
    let id: Int
    let categoryName: String?
    let description: String
    let cost: Double
}

struct MaintenanceItemInput: Encodable, Sendable {
    let categoryId: Int
    let description: String
    let cost: Double
}

// MARK: - Parts Lookup

struct PartLookupLastUsed: Codable, Sendable {
    let description: String
    let cost: Double
    let date: Date
    let vehicleName: String
}

struct PartLookup: Identifiable, Codable, Sendable {
    let categoryId: Int
    let categoryName: String
    let lastUsed: PartLookupLastUsed?
    var id: Int { categoryId }
}

// MARK: - Outings Analytics

struct OutingsByMonth: Identifiable, Codable, Sendable {
    let month: String
    let count: Int
    var id: String { month }
}

struct OutingsByVehicle: Identifiable, Codable, Sendable {
    let vehicleId: Int
    let vehicleName: String
    let count: Int
    var id: Int { vehicleId }
}

struct OutingsTopLocation: Identifiable, Codable, Sendable {
    let name: String
    let count: Int
    var id: String { name }
}

struct OutingsAnalyticsResponse: Codable, Sendable {
    let byMonth: [OutingsByMonth]
    let byVehicle: [OutingsByVehicle]
    let topLocations: [OutingsTopLocation]
}

// MARK: - Location

struct VehicleLocation: Identifiable, Codable, Sendable {
    let id: Int
    let name: String
    let address: String?
    let latitude: Double?
    let longitude: Double?
}

struct CreateLocationRequest: Encodable, Sendable {
    let name: String
    let address: String?
}

struct EditEventRequest: Encodable, Sendable {
    var date: String
    var miles: Int?
    var hours: Double?
    var gallons: Double?
    var pricePerGallon: Double?
    var notes: String?
    var locationName: String?
}

struct LogEventRequest: Encodable, Sendable {
    let eventType: String
    let date: String
    let loggedAt: String
    var miles: Int?
    var hours: Double?
    var gallons: Double?
    var pricePerGallon: Double?
    var notes: String?
    var maintenanceCategoryId: Int?
    var maintenanceItems: [MaintenanceItemInput]?
    var locationName: String?
}

// Computed stats derived client-side from loaded events
struct VehicleStats {
    let avgMPG: Double?
    let avgGPH: Double?
    let gasEventCount: Int
    let maintenanceEventCount: Int
    let outingEventCount: Int
    let outingsThisMonth: Int
    let lastGasDate: Date?
    let lastMaintenanceDate: Date?

    static func compute(from events: [VehicleEvent], vehicle: Vehicle) -> VehicleStats {
        let gasEvents = events.filter { $0.eventType == "gas" }
        let maintEvents = events.filter { $0.eventType == "maintenance" }
        let outingEvents = events.filter { $0.eventType == "outing" }

        let mpgValues = gasEvents.compactMap { $0.milespergallon }
        let avgMPG = mpgValues.isEmpty ? nil : mpgValues.reduce(0, +) / Double(mpgValues.count)

        let gphValues = gasEvents.compactMap { $0.gallonsperhour }
        let avgGPH = gphValues.isEmpty ? nil : gphValues.reduce(0, +) / Double(gphValues.count)

        let cal = Calendar.current
        let now = Date()
        let thisMonth = cal.component(.month, from: now)
        let thisYear = cal.component(.year, from: now)
        let outingsThisMonth = outingEvents.filter {
            cal.component(.month, from: $0.date) == thisMonth &&
            cal.component(.year, from: $0.date) == thisYear
        }.count

        return VehicleStats(
            avgMPG: vehicle.isBoat ? nil : avgMPG,
            avgGPH: vehicle.isBoat ? avgGPH : nil,
            gasEventCount: gasEvents.count,
            maintenanceEventCount: maintEvents.count,
            outingEventCount: outingEvents.count,
            outingsThisMonth: outingsThisMonth,
            lastGasDate: gasEvents.first?.date,
            lastMaintenanceDate: maintEvents.first?.date
        )
    }
}
