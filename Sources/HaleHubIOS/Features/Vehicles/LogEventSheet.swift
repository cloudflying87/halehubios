import SwiftUI

struct LogEventSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) var dismiss

    let vehicle: Vehicle
    var prefilledCategoryId: Int? = nil
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
    @State private var isAddingLocation = false
    @State private var addLocationError: String?
    @State private var serviceItems: [ServiceItem] = [ServiceItem()]
    @State private var categories: [MaintenanceCategory] = []
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var savedGasEvent: VehicleEvent? = nil

    private let eventTypes = ["gas", "maintenance", "outing"]

    var relevantCategories: [MaintenanceCategory] {
        categories.filter { $0.vehicleTypes?.contains(vehicle.vehicleType) ?? true }
    }

    var serviceTotal: Double {
        serviceItems.compactMap { Double($0.cost) }.reduce(0, +)
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
            if let event = savedGasEvent {
                GasSuccessCard(event: event, vehicle: vehicle) { dismiss() }
            } else {
                Form {
                Section("Type") {
                    Picker("Event Type", selection: $eventType) {
                        ForEach(eventTypes, id: \.self) {
                            Text($0 == "maintenance" ? "Service" : $0.capitalized).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: eventType) { _, _ in serviceItems = [ServiceItem()] }

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

                    if eventType == "maintenance" {
                        ForEach($serviceItems) { $item in
                            ServiceItemRow(item: $item, categories: relevantCategories) {
                                serviceItems.removeAll { $0.id == item.id }
                            }
                        }
                        Button {
                            serviceItems.append(ServiceItem())
                        } label: {
                            Label("Add Another Item", systemImage: "plus.circle")
                                .font(.subheadline)
                        }
                        if serviceTotal > 0 {
                            HStack {
                                Text("Total").foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "$%.2f", serviceTotal))
                                    .fontWeight(.semibold)
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
            } // end else
        } // end NavigationStack
        .task {
            await loadCategories()
            await loadLocations()
            if let catId = prefilledCategoryId {
                eventType = "maintenance"
                var prefilled = ServiceItem()
                prefilled.categoryId = catId
                serviceItems = [prefilled]
            }
        }
        .sheet(isPresented: $showAddLocation) {
            NavigationStack {
                Form {
                    Section {
                        TextField("Location name", text: $newLocationName)
                        TextField("Address (optional)", text: $newLocationAddress)
                    }
                    if let err = addLocationError {
                        Section {
                            Label(err, systemImage: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                                .font(.subheadline)
                        }
                    }
                }
                .navigationTitle("New Location")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            addLocationError = nil
                            showAddLocation = false
                        }
                        .disabled(isAddingLocation)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isAddingLocation {
                            ProgressView()
                        } else {
                            Button("Add") {
                                Task { await addLocation() }
                            }
                            .disabled(newLocationName.isEmpty)
                        }
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
        do {
            locations = try await APIClient.shared.get("/vehicles/locations/", token: token)
        } catch {
            // Locations endpoint may not be deployed yet — silently degrade to add-new only
            locations = []
        }
    }

    private func addLocation() async {
        guard let token = auth.accessToken, !newLocationName.isEmpty else { return }
        isAddingLocation = true
        addLocationError = nil
        let body = CreateLocationRequest(
            name: newLocationName,
            address: newLocationAddress.isEmpty ? nil : newLocationAddress
        )
        do {
            let created: VehicleLocation = try await APIClient.shared.post("/vehicles/locations/", body: body, token: token)
            locations.append(created)
            locations.sort { $0.name < $1.name }
            selectedLocationId = created.id
            newLocationName = ""
            newLocationAddress = ""
            showAddLocation = false
        } catch {
            addLocationError = error.localizedDescription
        }
        isAddingLocation = false
    }

    private func save() async {
        guard let token = auth.accessToken else { return }
        isSaving = true
        errorMessage = nil

        let dateFmt = ISO8601DateFormatter()
        dateFmt.formatOptions = [.withFullDate]

        let tsFmt = ISO8601DateFormatter()
        tsFmt.formatOptions = [.withInternetDateTime]

        var body = LogEventRequest(
            eventType: eventType,
            date: dateFmt.string(from: date),
            loggedAt: tsFmt.string(from: Date())
        )
        body.miles = vehicle.isBoat ? nil : Int(odometer)
        body.hours = vehicle.isBoat ? Double(odometer) : nil
        body.gallons = Double(gallons)
        body.pricePerGallon = Double(pricePerGallon)
        body.notes = notes.isEmpty ? nil : notes
        if eventType == "maintenance" {
            let items = serviceItems.compactMap { item -> MaintenanceItemInput? in
                guard let catId = item.categoryId else { return nil }
                return MaintenanceItemInput(
                    categoryId: catId,
                    description: item.description,
                    cost: Double(item.cost) ?? 0
                )
            }
            body.maintenanceItems = items.isEmpty ? nil : items
            body.maintenanceCategoryId = items.first?.categoryId
        }
        body.locationName = locations.first(where: { $0.id == selectedLocationId })?.name

        do {
            let saved: VehicleEvent = try await APIClient.shared.post(
                "/vehicles/\(vehicle.id)/log/", body: body, token: token
            )
            onSaved()
            if eventType == "gas" {
                savedGasEvent = saved  // show success card
            } else {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}

// MARK: - Service Item helpers

struct ServiceItem: Identifiable {
    let id = UUID()
    var categoryId: Int? = nil
    var description: String = ""
    var cost: String = ""
}

struct ServiceItemRow: View {
    @Binding var item: ServiceItem
    let categories: [MaintenanceCategory]
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("Category", selection: $item.categoryId) {
                    Text("— Select type —").tag(nil as Int?)
                    ForEach(categories) { cat in
                        Text(cat.name).tag(cat.id as Int?)
                    }
                }
                .labelsHidden()
                Spacer()
                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
            HStack {
                TextField("Description (e.g. Mobil 1 5W-30)", text: $item.description)
                    .font(.subheadline)
                Spacer()
                HStack(spacing: 2) {
                    Text("$").foregroundStyle(.secondary)
                    TextField("0.00", text: $item.cost)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                }
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Gas Success Card

struct GasSuccessCard: View {
    let event: VehicleEvent
    let vehicle: Vehicle
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "fuelpump.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)

            Text("Fill-up Recorded!")
                .font(.title2.bold())

            // Stats grid
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    SuccessStatBox(label: "Gallons", value: event.gallons.map { String(format: "%.3f", $0) } ?? "—")
                    SuccessStatBox(label: "Total Cost", value: event.totalCost.map { String(format: "$%.2f", $0) } ?? "—", highlight: true)
                }

                if let mpg = event.milespergallon {
                    EfficiencyBox(label: "Fuel Efficiency", value: String(format: "%.1f", mpg), unit: "MPG", color: Color.accentColor)
                } else if let gph = event.gallonsperhour {
                    EfficiencyBox(label: "Fuel Consumption", value: String(format: "%.2f", gph), unit: "GPH", color: Color.accentColor)
                } else {
                    Text("Efficiency calculated on next fill-up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                }

                if let ppg = event.pricePerGallon {
                    SuccessStatBox(label: "Price per Gallon", value: String(format: "$%.3f", ppg))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)

            Spacer()

            Button(action: onDone) {
                Text("Got it!")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .navigationTitle(vehicle.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SuccessStatBox: View {
    let label: String
    let value: String
    var highlight = false

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(highlight ? Color.green : .primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct EfficiencyBox: View {
    let label: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                Text(unit)
                    .font(.title3.bold())
                    .foregroundStyle(color)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.3), lineWidth: 1))
    }
}
