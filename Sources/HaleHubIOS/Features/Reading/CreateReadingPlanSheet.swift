import SwiftUI

struct CreateReadingPlanSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Binding var isPresented: Bool
    var onCreated: (ReadingPlanSummary) -> Void

    @State private var name = ""
    @State private var startDate = Date()
    @State private var totalDays = 365
    @State private var description = ""
    @State private var isPrimary = true
    @State private var isSaving = false
    @State private var error: String?

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && totalDays >= 1 }

    var body: some View {
        NavigationStack {
            Form {
                Section("Plan Details") {
                    TextField("Plan name (e.g. Bible in a Year 2026)", text: $name)
                        .autocorrectionDisabled()

                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)

                    Stepper("Length: \(totalDays) days", value: $totalDays, in: 1...3650, step: 1)

                    HStack {
                        Text("End Date")
                        Spacer()
                        Text(endDateLabel)
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                }

                Section {
                    TextEditor(text: $description)
                        .frame(minHeight: 60)
                } header: {
                    Text("Description (optional)")
                }

                Section {
                    Toggle("Set as primary plan", isOn: $isPrimary)
                } footer: {
                    Text("Your primary plan is shown on the Reading Plan dashboard.")
                }

                if let err = error {
                    Section {
                        Text(err).foregroundStyle(.red).font(.subheadline)
                    }
                }
            }
            .navigationTitle("New Reading Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Create") {
                            Task { await save() }
                        }
                        .disabled(!isValid)
                        .fontWeight(.semibold)
                    }
                }
            }
        }
    }

    private var endDateLabel: String {
        let end = Calendar.current.date(byAdding: .day, value: totalDays - 1, to: startDate) ?? startDate
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        return fmt.string(from: end)
    }

    private func save() async {
        isSaving = true
        error = nil
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let req = CreatePlanRequest(
            name: name.trimmingCharacters(in: .whitespaces),
            startDate: fmt.string(from: startDate),
            totalDays: totalDays,
            description: description.trimmingCharacters(in: .whitespaces),
            isPrimary: isPrimary
        )
        do {
            let plan: ReadingPlanSummary = try await APIClient.shared.post(
                "/reading/plans/", body: req, token: auth.accessToken ?? ""
            )
            onCreated(plan)
            isPresented = false
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}
