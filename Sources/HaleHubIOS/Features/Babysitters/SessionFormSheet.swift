import SwiftUI

struct SessionFormSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    /// nil → log new; non-nil → edit.
    let session: BabysittingSession?
    let defaultBabysitterId: String?
    let onSaved: () -> Void

    @State private var babysitters: [Babysitter] = []
    @State private var babysitterId: String = ""
    @State private var date = Date()
    @State private var startTime = Date()
    @State private var endTime = Date()
    @State private var isPaid = false
    @State private var notes = ""
    @State private var isSaving = false
    @State private var error: String?

    private var isEditing: Bool { session != nil }
    private var canSave: Bool { !babysitterId.isEmpty && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Babysitter", selection: $babysitterId) {
                        Text("Select…").tag("")
                        ForEach(babysitters) { sitter in
                            Text(sitter.name).tag(sitter.id)
                        }
                    }
                }
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    DatePicker("Arrived", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("Left", selection: $endTime, displayedComponents: .hourAndMinute)
                } footer: {
                    Text("Hours are rounded to the nearest 15 minutes.")
                }
                Section {
                    Toggle("Paid", isOn: $isPaid)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle(isEditing ? "Edit Session" : "Log Session")
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
            .task { await loadBabysitters() }
            .onAppear(perform: populate)
        }
    }

    private func loadBabysitters() async {
        let token = auth.accessToken ?? ""
        do {
            let resp: PaginatedResponse<Babysitter> = try await APIClient.shared.get("/babysitters/", token: token)
            babysitters = resp.results
            if babysitterId.isEmpty {
                babysitterId = defaultBabysitterId ?? session?.babysitter ?? ""
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func populate() {
        guard let s = session else {
            babysitterId = defaultBabysitterId ?? ""
            return
        }
        babysitterId = s.babysitter
        isPaid = s.isPaid
        notes = s.notes
        if let d = BabysitterFormat.ymdDate(s.date) { date = d }
        startTime = parseTime(s.startTime) ?? startTime
        endTime = parseTime(s.endTime) ?? endTime
    }

    private func parseTime(_ hms: String) -> Date? {
        let parts = hms.split(separator: ":")
        guard parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date())
    }

    private func save() async {
        isSaving = true
        error = nil
        let token = auth.accessToken ?? ""
        let body = SessionRequest(
            babysitter: babysitterId,
            date: BabysitterFormat.ymdString(date),
            startTime: BabysitterFormat.hmString(startTime),
            endTime: BabysitterFormat.hmString(endTime),
            isPaid: isPaid,
            notes: notes
        )
        do {
            if let s = session {
                let _: BabysittingSession = try await APIClient.shared.patch(
                    "/babysitters/sessions/\(s.id)/", body: body, token: token)
            } else {
                let _: BabysittingSession = try await APIClient.shared.post(
                    "/babysitters/sessions/", body: body, token: token)
            }
            onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}
