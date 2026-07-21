import SwiftUI

/// Pick unpaid sessions and record the check/cash/etc that pays for them —
/// the counterpart to the web "Record Payment" page.
struct RecordPaymentSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    let babysitter: Babysitter
    let unpaidSessions: [BabysittingSession]
    let onSaved: () -> Void

    @State private var selectedIds: Set<String> = []
    @State private var amount: String = ""
    @State private var datePaid = Date()
    @State private var method = "check"
    @State private var checkNumber = ""
    @State private var notes = ""
    @State private var isSaving = false
    @State private var error: String?

    private var selectedTotal: Double {
        unpaidSessions.filter { selectedIds.contains($0.id) }.reduce(0) { $0 + ($1.amountOwed ?? 0) }
    }
    private var canSave: Bool { !selectedIds.isEmpty && Double(amount) != nil && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section("Sessions to pay") {
                    ForEach(unpaidSessions) { session in
                        Button {
                            toggle(session.id)
                        } label: {
                            HStack {
                                Image(systemName: selectedIds.contains(session.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedIds.contains(session.id) ? Color.accentColor : Color.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.dateDisplay).font(.subheadline)
                                    Text("\(session.startDisplay)–\(session.endDisplay) · \(session.durationDisplay ?? "")")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(session.amountDisplay).font(.subheadline)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
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
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Record Payment")
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
            .onAppear {
                selectedIds = Set(unpaidSessions.map(\.id))
                amount = String(format: "%.2f", selectedTotal)
            }
            .onChange(of: selectedIds) { _, _ in
                amount = String(format: "%.2f", selectedTotal)
            }
        }
    }

    private func toggle(_ id: String) {
        if selectedIds.contains(id) { selectedIds.remove(id) } else { selectedIds.insert(id) }
    }

    private func save() async {
        guard let amountValue = Double(amount) else { return }
        isSaving = true
        error = nil
        let token = auth.accessToken ?? ""
        let body = RecordPaymentRequest(
            babysitter: babysitter.id,
            sessionIds: Array(selectedIds),
            amount: amountValue,
            datePaid: BabysitterFormat.ymdString(datePaid),
            method: method,
            checkNumber: checkNumber.trimmingCharacters(in: .whitespaces),
            notes: notes.trimmingCharacters(in: .whitespaces)
        )
        do {
            let _: Payment = try await APIClient.shared.post(
                "/babysitters/payments/", body: body, token: token)
            onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}
