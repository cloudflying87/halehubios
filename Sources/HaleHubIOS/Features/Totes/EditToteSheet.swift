import SwiftUI

struct EditToteSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    let tote: ToteDetail
    var onSaved: (Tote) -> Void

    @State private var name: String
    @State private var selectedLocationId: String?
    @State private var locationNotes: String
    @State private var notes: String
    @State private var isSaving = false
    @State private var error: String?

    init(tote: ToteDetail, onSaved: @escaping (Tote) -> Void) {
        self.tote = tote
        self.onSaved = onSaved
        _name = State(initialValue: tote.name)
        _selectedLocationId = State(initialValue: tote.locationObjId)
        _locationNotes = State(initialValue: tote.locationNotes)
        _notes = State(initialValue: tote.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Winter Clothes", text: $name)
                        .autocorrectionDisabled()
                }
                Section("Location") {
                    LocationPickerView(selectionId: $selectedLocationId)
                    TextField("Details (e.g. Top shelf)", text: $locationNotes)
                }
                Section("Notes (optional)") {
                    TextField("Any additional notes…", text: $notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).font(.subheadline)
                    }
                }
            }
            .navigationTitle("Edit Tote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func save() async {
        guard let token = auth.accessToken else { return }
        isSaving = true
        error = nil
        let body = EditToteRequest(
            name: name.trimmingCharacters(in: .whitespaces),
            locationObjId: selectedLocationId,
            locationNotes: locationNotes.trimmingCharacters(in: .whitespaces),
            notes: notes.trimmingCharacters(in: .whitespaces)
        )
        do {
            let updated: Tote = try await APIClient.shared.patch("/totes/\(tote.id)/", body: body, token: token)
            onSaved(updated)
            dismiss()
        } catch {
            self.error = error.localizedDescription
            isSaving = false
        }
    }
}
