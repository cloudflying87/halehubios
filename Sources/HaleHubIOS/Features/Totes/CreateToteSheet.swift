import SwiftUI

struct CreateToteSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    var qrIdentifier: String?       // nil when creating without a scanned QR
    var onCreated: (Tote) -> Void
    var onCancel: (() -> Void)?     // nil when presented as a regular sheet (dismiss handles it)

    @State private var name = ""
    @State private var selectedLocationId: String? = nil
    @State private var locationNotes = ""
    @State private var notes = ""
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if let qr = qrIdentifier, !qr.isEmpty {
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: "qrcode")
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("QR Code Scanned")
                                    .font(.subheadline.weight(.medium))
                                Text(qr)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("New Tote")
                    } footer: {
                        Text("This QR code isn't linked to a tote yet. Fill in the details below to create one.")
                    }
                }

                Section("Name") {
                    TextField("e.g. Winter Clothes, Baby Items", text: $name)
                        .autocorrectionDisabled()
                }

                Section("Location") {
                    LocationPickerView(selectionId: $selectedLocationId)
                    TextField("Details (e.g. Top shelf, Left corner)", text: $locationNotes)
                }

                Section("Notes (optional)") {
                    TextField("Any additional notes…", text: $notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }

                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("Create Tote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if let onCancel { onCancel() } else { dismiss() }
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Button("Create") {
                            Task { await save() }
                        }
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

        let trimmedQR = qrIdentifier?.trimmingCharacters(in: .whitespaces)
        let body = CreateToteRequest(
            name: name.trimmingCharacters(in: .whitespaces),
            locationObjId: selectedLocationId,
            locationNotes: locationNotes.trimmingCharacters(in: .whitespaces),
            notes: notes.trimmingCharacters(in: .whitespaces),
            qrCodeIdentifier: (trimmedQR?.isEmpty == false) ? trimmedQR : nil
        )

        do {
            let newTote: Tote = try await APIClient.shared.post("/totes/", body: body, token: token)
            onCreated(newTote)
            dismiss()
        } catch {
            self.error = error.localizedDescription
            isSaving = false
        }
    }
}
