import SwiftUI

struct BabysitterFormSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    /// nil → create; non-nil → edit.
    let babysitter: Babysitter?
    let onSaved: () -> Void

    @State private var name: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var rate: String = ""
    @State private var notes: String = ""
    @State private var isActive: Bool = true
    @State private var isSaving = false
    @State private var error: String?

    private var isEditing: Bool { babysitter != nil }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Email (optional)", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    TextField("Phone (optional)", text: $phone)
                        .keyboardType(.phonePad)
                }
                Section("Pay") {
                    HStack {
                        Text("$")
                        TextField("0.00", text: $rate)
                            .keyboardType(.decimalPad)
                        Text("/ hr")
                    }
                }
                Section {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                    if isEditing {
                        Toggle("Active", isOn: $isActive)
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle(isEditing ? "Edit Babysitter" : "Add Babysitter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: populate)
        }
    }

    private func populate() {
        guard let b = babysitter else { return }
        name = b.name
        email = b.email
        phone = b.phoneNumber
        rate = String(format: "%.2f", b.hourlyRate)
        notes = b.notes
        isActive = b.isActive ?? true
    }

    private func save() async {
        isSaving = true
        error = nil
        let token = auth.accessToken ?? ""
        let body = BabysitterRequest(
            name: name.trimmingCharacters(in: .whitespaces),
            email: email.trimmingCharacters(in: .whitespaces),
            phoneNumber: phone.trimmingCharacters(in: .whitespaces),
            hourlyRate: Double(rate) ?? 0,
            notes: notes,
            isActive: isActive
        )
        do {
            if let b = babysitter {
                let _: Babysitter = try await APIClient.shared.patch("/babysitters/\(b.id)/", body: body, token: token)
            } else {
                let _: Babysitter = try await APIClient.shared.post("/babysitters/", body: body, token: token)
            }
            onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}
