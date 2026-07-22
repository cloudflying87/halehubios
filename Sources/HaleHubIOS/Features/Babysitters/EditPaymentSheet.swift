import SwiftUI

/// Correct a recorded payment's amount/date/method/check#/notes. Which
/// sessions it covers isn't editable here — void and re-record instead.
struct EditPaymentSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    let payment: Payment
    let onSaved: () -> Void

    @State private var amount: String = ""
    @State private var datePaid = Date()
    @State private var method = "check"
    @State private var checkNumber = ""
    @State private var notes = ""
    @State private var isSaving = false
    @State private var error: String?

    private var canSave: Bool { Double(amount) != nil && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section("Payment details") {
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("0.00", text: $amount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    DatePicker("Date paid", selection: $datePaid, displayedComponents: .date)
                    Picker("Method", selection: $method) {
                        ForEach(Payment.methods, id: \.self) { m in
                            Text(Payment.methodLabels[m] ?? m.capitalized).tag(m)
                        }
                    }
                    TextField("Check number (optional)", text: $checkNumber)
                        .textInputAutocapitalization(.characters)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                } footer: {
                    Text("To change which sessions this payment covers, void it and record a new one instead.")
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Edit Payment")
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
        amount = String(format: "%.2f", payment.amount)
        datePaid = BabysitterFormat.ymdDate(payment.datePaid) ?? Date()
        method = payment.method
        checkNumber = payment.checkNumber
        notes = payment.notes
    }

    private func save() async {
        guard let amountValue = Double(amount) else { return }
        isSaving = true
        error = nil
        let token = auth.accessToken ?? ""
        let body = UpdatePaymentRequest(
            amount: amountValue,
            datePaid: BabysitterFormat.ymdString(datePaid),
            method: method,
            checkNumber: checkNumber.trimmingCharacters(in: .whitespaces),
            notes: notes.trimmingCharacters(in: .whitespaces)
        )
        do {
            let _: Payment = try await APIClient.shared.patch(
                "/babysitters/payments/\(payment.id)/", body: body, token: token)
            onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}
