import SwiftUI

enum LetterEditorMode {
    case create
    case edit(LetterDetail)
}

struct LetterEditorSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    let mode: LetterEditorMode
    var onSave: (LetterDetail) -> Void

    @State private var title = ""
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var greetingMessage = ""
    @State private var showPreview = false
    @State private var hasRsvp = false
    @State private var hasEventDate = false
    @State private var eventDate = Date()
    @State private var eventTime = ""
    @State private var eventLocation = ""
    @State private var isSaving = false
    @State private var error: String?

    private var isCreate: Bool {
        if case .create = mode { return true }
        return false
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var body: some View {
        NavigationStack {
            Form {
                Section("Basics") {
                    TextField("Title", text: $title)
                    Stepper("Year: \(year)", value: $year, in: 2000...2100)
                }

                Section("Greeting Message") {
                    if !greetingMessage.isEmpty || !showPreview {
                        Picker("", selection: $showPreview) {
                            Text("Write").tag(false)
                            Text("Preview").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    if showPreview {
                        MarkdownContentView(content: greetingMessage)
                            .frame(minHeight: 200)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        TextEditor(text: $greetingMessage)
                            .frame(minHeight: 200)
                    }
                }

                Section {
                    Toggle("Has RSVP / Event", isOn: $hasRsvp.animation())
                    if hasRsvp {
                        Toggle("Set event date", isOn: $hasEventDate.animation())
                        if hasEventDate {
                            DatePicker("Date", selection: $eventDate, displayedComponents: .date)
                        }
                        TextField("Time (e.g. 11am–dusk)", text: $eventTime)
                        TextField("Location", text: $eventLocation)
                    }
                } header: {
                    Text("Event")
                }

                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).font(.subheadline)
                    }
                }
            }
            .navigationTitle(isCreate ? "New Letter" : "Edit Letter")
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
                            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .onAppear { hydrate() }
        }
    }

    private func hydrate() {
        guard case .edit(let d) = mode else { return }
        title = d.title
        year = d.year
        greetingMessage = d.greetingMessage
        hasRsvp = d.hasRsvp
        eventTime = d.eventTime
        eventLocation = d.eventLocation
        if let dateStr = d.eventDate, let date = Self.dateFmt.date(from: dateStr) {
            hasEventDate = true
            eventDate = date
        }
    }

    private func save() async {
        guard let token = auth.accessToken else { return }
        isSaving = true
        error = nil
        let eventDateStr = hasRsvp && hasEventDate ? Self.dateFmt.string(from: eventDate) : nil
        do {
            let saved: LetterDetail
            switch mode {
            case .create:
                let body = LetterDraft(
                    title: title.trimmingCharacters(in: .whitespaces),
                    year: year,
                    greetingMessage: greetingMessage,
                    hasRsvp: hasRsvp,
                    eventDate: eventDateStr,
                    eventTime: hasRsvp ? eventTime : "",
                    eventLocation: hasRsvp ? eventLocation : "",
                    isActive: true
                )
                saved = try await APIClient.shared.post("/letters/", body: body, token: token)
            case .edit(let original):
                let body = LetterPatch(
                    title: title.trimmingCharacters(in: .whitespaces),
                    greetingMessage: greetingMessage,
                    year: year,
                    hasRsvp: hasRsvp,
                    eventDate: eventDateStr,
                    eventTime: hasRsvp ? eventTime : "",
                    eventLocation: hasRsvp ? eventLocation : ""
                )
                saved = try await APIClient.shared.patch("/letters/\(original.slug)/", body: body, token: token)
            }
            onSave(saved)
            dismiss()
        } catch {
            self.error = error.localizedDescription
            isSaving = false
        }
    }
}
