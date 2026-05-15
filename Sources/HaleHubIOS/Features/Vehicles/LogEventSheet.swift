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
    @State private var locationName = ""
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
                        TextField("Location (optional)", text: $locationName)
                    }

                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Log \(eventType == "maintenance" ? "Service" : eventType.capitalized)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
        }
        .task { await loadCategories() }
    }

    private func loadCategories() async {
        guard let token = auth.accessToken else { return }
        categories = (try? await APIClient.shared.get("/vehicles/maintenance-categories/", token: token)) ?? []
    }

    private func save() async {
        guard let token = auth.accessToken else { return }
        isSaving = true
        errorMessage = nil

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        var body = LogEventRequest(eventType: eventType, date: formatter.string(from: date))
        body.miles = vehicle.isBoat ? nil : Int(odometer)
        body.hours = vehicle.isBoat ? Int(odometer) : nil
        body.gallons = Double(gallons)
        body.pricePerGallon = Double(pricePerGallon)
        body.notes = notes.isEmpty ? nil : notes
        body.maintenanceCategoryId = selectedCategoryId
        body.locationName = locationName.isEmpty ? nil : locationName

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
