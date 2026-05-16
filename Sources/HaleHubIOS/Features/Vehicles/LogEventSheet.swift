import SwiftUI

struct LogEventSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) var dismiss

    let vehicle: Vehicle
    let onSaved: () -> Void

    @State private var eventType = "gas"
    @State private var date = Date()
    @State private var odometer = ""
    @State private var gallons = ""
    @State private var pricePerGallon = ""
    @State private var notes = ""
    @State private var selectedLocationId: Int? = nil
    @State private var locations: [VehicleLocation] = []
    @State private var showAddLocation = false
    @State private var newLocationName = ""
    @State private var newLocationAddress = ""
    @State private var selectedCategoryId: Int? = nil
    @State private var categories: [MaintenanceCategory] = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let eventTypes = ["gas", "maintenance", "outing"]

    var relevantCategories: [MaintenanceCategory] {
        categories.filter { cat in
            cat.vehicleTypes?.contains(vehicle.vehicleType) ?? true
        }
    }

    var isValid: Bool {
        switch eventType {
        case "gas":
            return !gallons.isEmpty && Double(gallons) != nil
                && !pricePerGallon.isEmpty && Double(pricePerGallon) != nil
        default:
            return true
        }
    }

    var validationHint: String? {
        if eventType == "gas" {
            if gallons.isEmpty { return "Enter the number of gallons" }
            if Double(gallons) == nil { return "Gallons must be a number" }
            if pricePerGallon.isEmpty { return "Enter price per gallon" }
            if Double(pricePerGallon) == nil { return "Price must be a number" }
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Event Type", selection: $eventType) {
                        ForEach(eventTypes, id: \.self) {
                            Text($0 == "maintenance" ? "Service" : $0.capitalized).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: eventType) { _, _ in selectedCategoryId = nil }

                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                Section("Details") {
                    TextField(vehicle.isBoat ? "Hours" : "Odometer (miles)", text: $odometer)
                        .keyboardType(.numberPad)

                    if eventType == "gas" {
                        TextField("Gallons", text: $gallons)
                            .keyboardType(.decimalPad)
                        TextField("Price per gallon", text: $pricePerGallon)
                            .keyboardType(.decimalPad)
                        if let gallonsVal = Double(gallons), let priceVal = Double(pricePerGallon), gallonsVal > 0, priceVal > 0 {
                            HStack {
                                Text("Total").foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "$%.2f", gallonsVal * priceVal))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if eventType == "maintenance" && !relevantCategories.isEmpty {
                        Picker("Category", selection: $selectedCategoryId) {
                            Text("— Select —").tag(nil as Int?)
                            ForEach(relevantCategories) { cat in
                                Text(cat.name).tag(cat.id as Int?)
                            }
                        }
                    }

                    if eventType == "outing" {
                        Picker("Location", selection: $selectedLocationId) {
                            Text("— None —").tag(nil as Int?)
                            ForEach(locations) { loc in
                                Text(loc.name).tag(loc.id as Int?)
                            }
                        }
                        Button {
                            showAddLocation = true
                        } label: {
                            Label("Add New Location", systemImage: "plus.circle")
                                .font(.subheadline)
                        }
                    }

                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                if let hint = validationHint {
                    Section {
                        Label(hint, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = errorMessage {
                    Section {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.subheadline)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Log \(eventType == "maintenance" ? "Service" : eventType.capitalized)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving || !isValid)
                }
            }
        }
        .task { await loadCategories(); await loadLocations() }
        .sheet(isPresented: $showAddLocation) {
            NavigationStack {
                Form {
                    Section {
                        TextField("Location name", text: $newLocationName)
                        TextField("Address (optional)", text: $newLocationAddress)
                    }
                }
                .navigationTitle("New Location")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showAddLocation = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            Task { await addLocation() }
                        }
                        .disabled(newLocationName.isEmpty)
                    }
                }
            }
        }
    }

    private func loadCategories() async {
        guard let token = auth.accessToken else { return }
        categories = (try? await APIClient.shared.get("/vehicles/maintenance-categories/", token: token)) ?? []
    }

    private func loadLocations() async {
        guard let token = auth.accessToken else { return }
        locations = (try? await APIClient.shared.get("/vehicles/locations/", token: token)) ?? []
    }

    private func addLocation() async {
        guard let token = auth.accessToken, !newLocationName.isEmpty else { return }
        let body = CreateLocationRequest(
            name: newLocationName,
            address: newLocationAddress.isEmpty ? nil : newLocationAddress
        )
        if let created: VehicleLocation = try? await APIClient.shared.post("/vehicles/locations/", body: body, token: token) {
            locations.append(created)
            locations.sort { $0.name < $1.name }
            selectedLocationId = created.id
        }
        newLocationName = ""
        newLocationAddress = ""
        showAddLocation = false
    }

    private func save() async {
        guard let token = auth.accessToken else { return }
        isSaving = true
        errorMessage = nil

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        var body = LogEventRequest(eventType: eventType, date: formatter.string(from: date))
        body.miles = vehicle.isBoat ? nil : Int(odometer)
        body.hours = vehicle.isBoat ? Double(odometer) : nil
        body.gallons = Double(gallons)
        body.pricePerGallon = Double(pricePerGallon)
        body.notes = notes.isEmpty ? nil : notes
        body.maintenanceCategoryId = selectedCategoryId
        body.locationName = locations.first(where: { $0.id == selectedLocationId })?.name

        do {
            let _: VehicleEvent = try await APIClient.shared.post(
                "/vehicles/\(vehicle.id)/log/", body: body, token: token
            )
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
