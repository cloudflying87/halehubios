import SwiftUI

/// Edit a vehicle's identification + registration details (name, VIN, plate,
/// plate state, registration expiry). PATCHes /vehicles/<id>/update/.
struct VehicleEditSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    let vehicle: Vehicle
    /// Called with the updated vehicle on a successful save.
    let onSaved: (Vehicle) -> Void

    @State private var name: String = ""
    @State private var vin: String = ""
    @State private var licensePlate: String = ""
    @State private var plateState: String = ""
    @State private var boatEngineType: String = ""
    @State private var tracksRegistration = false
    @State private var registrationDate = Date()
    @State private var saving = false
    @State private var error: String?

    private var token: String { auth.accessToken ?? "" }

    var body: some View {
        NavigationStack {
            Form {
                Section("Vehicle") {
                    TextField("Name", text: $name)
                    TextField("VIN", text: $vin)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                Section("License plate") {
                    TextField("Plate number", text: $licensePlate)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Picker("State / Province", selection: $plateState) {
                        Text("—").tag("")
                        ForEach(VehicleEditSheet.plateRegions, id: \.self) { Text($0).tag($0) }
                    }
                }
                if vehicle.vehicleType == "boat" {
                    Section("Engine") {
                        Picker("Engine type", selection: $boatEngineType) {
                            Text("—").tag("")
                            ForEach(VehicleEditSheet.boatEngineTypes, id: \.value) { opt in
                                Text(opt.label).tag(opt.value)
                            }
                        }
                    }
                }
                Section {
                    Toggle("Track registration", isOn: $tracksRegistration.animation())
                    if tracksRegistration {
                        DatePicker("Expires", selection: $registrationDate, displayedComponents: .date)
                    }
                } header: {
                    Text("Registration")
                } footer: {
                    if tracksRegistration {
                        Text("You'll get a reminder as the date approaches.")
                    }
                }
            }
            .navigationTitle("Edit Vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: populate)
            .alert("Error", isPresented: .init(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") {}
            } message: { Text(error ?? "") }
        }
    }

    private func populate() {
        name = vehicle.name
        vin = vehicle.vin ?? ""
        licensePlate = vehicle.licensePlate ?? ""
        plateState = vehicle.plateState ?? ""
        boatEngineType = vehicle.boatEngineType ?? ""
        if let raw = vehicle.registrationExpires, let d = Self.parseYMD(raw) {
            tracksRegistration = true
            registrationDate = d
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let req = VehicleEditRequest(
            name: name.trimmingCharacters(in: .whitespaces),
            vin: vin.trimmingCharacters(in: .whitespaces),
            licensePlate: licensePlate.trimmingCharacters(in: .whitespaces),
            plateState: plateState,
            boatEngineType: vehicle.vehicleType == "boat" ? boatEngineType : nil,
            registrationExpires: tracksRegistration ? Self.ymd(registrationDate) : ""
        )
        do {
            let updated: Vehicle = try await APIClient.shared.patch(
                "/vehicles/\(vehicle.id)/update/", body: req, token: token
            )
            onSaved(updated)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    static func ymd(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    static func parseYMD(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(s.prefix(10)))
    }

    static let plateRegions: [String] = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "DC", "FL", "GA", "HI", "ID", "IL",
        "IN", "IA", "KS", "KY", "LA", "ME", "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE",
        "NV", "NH", "NJ", "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC", "SD",
        "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY",
        "AB", "BC", "MB", "NB", "NL", "NS", "ON", "PE", "QC", "SK",
    ]

    struct EngineTypeOption { let value: String; let label: String }
    static let boatEngineTypes: [EngineTypeOption] = [
        EngineTypeOption(value: "inboard", label: "Inboard"),
        EngineTypeOption(value: "outboard", label: "Outboard"),
        EngineTypeOption(value: "io", label: "Inboard/Outboard (I/O)"),
    ]
}

struct VehicleEditRequest: Encodable, Sendable {
    let name: String
    let vin: String
    let licensePlate: String
    let plateState: String
    /// nil for non-boat vehicles — omitted from the request entirely rather
    /// than sent as null, since the API rejects null for this field.
    let boatEngineType: String?
    let registrationExpires: String  // "YYYY-MM-DD", or "" to clear

    enum CodingKeys: String, CodingKey {
        case name, vin, licensePlate, boatEngineType, plateState, registrationExpires
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(vin, forKey: .vin)
        try container.encode(licensePlate, forKey: .licensePlate)
        try container.encode(plateState, forKey: .plateState)
        try container.encodeIfPresent(boatEngineType, forKey: .boatEngineType)
        try container.encode(registrationExpires, forKey: .registrationExpires)
    }
}
