import SwiftUI

// MARK: - ViewModel

@MainActor
class ReadingDayDetailViewModel: ObservableObject {
    @Published var day: ReadingDay?
    @Published var isLoading = false
    @Published var error: String?
    @Published var isToggling = false

    let planId: String
    let dayNumber: Int

    init(planId: String, dayNumber: Int) {
        self.planId = planId
        self.dayNumber = dayNumber
    }

    func load(token: String) async {
        isLoading = true
        error = nil
        do {
            day = try await APIClient.shared.get(
                "/reading/plans/\(planId)/days/\(dayNumber)/", token: token
            )
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func toggle(token: String) async {
        isToggling = true
        do {
            let r: ReadingToggleResponse = try await APIClient.shared.postEmpty(
                "/reading/plans/\(planId)/days/\(dayNumber)/toggle/", token: token
            )
            if let d = day {
                day = ReadingDay(
                    dayNumber: d.dayNumber,
                    date: d.date,
                    isCompleted: r.isCompleted,
                    entries: d.entries,
                    notes: d.notes
                )
            }
        } catch {
            self.error = error.localizedDescription
        }
        isToggling = false
    }

    func deleteEntry(entryId: String, token: String) async {
        do {
            try await APIClient.shared.delete("/reading/entries/\(entryId)/", token: token)
            if let d = day {
                day = ReadingDay(
                    dayNumber: d.dayNumber,
                    date: d.date,
                    isCompleted: d.isCompleted,
                    entries: d.entries.filter { $0.id != entryId },
                    notes: d.notes
                )
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func entryAdded(_ entry: ReadingEntry) {
        if let d = day {
            day = ReadingDay(
                dayNumber: d.dayNumber,
                date: d.date,
                isCompleted: d.isCompleted,
                entries: d.entries + [entry],
                notes: d.notes
            )
        }
    }

    func updateNotes(notes: String, token: String) async {
        do {
            let req = UpdateDayNotesRequest(notes: notes)
            let _: ReadingDay = try await APIClient.shared.patch(
                "/reading/plans/\(planId)/days/\(dayNumber)/",
                body: req, token: token
            )
            if let d = day {
                day = ReadingDay(
                    dayNumber: d.dayNumber,
                    date: d.date,
                    isCompleted: d.isCompleted,
                    entries: d.entries,
                    notes: notes
                )
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - View

struct ReadingDayDetailView: View {
    @EnvironmentObject var auth: AuthManager
    let planId: String
    let dayNumber: Int
    let dateString: String   // "YYYY-MM-DD" for display

    @StateObject private var vm: ReadingDayDetailViewModel
    @State private var showAddEntry = false
    @State private var editingNotes = false
    @State private var notesText = ""

    init(planId: String, dayNumber: Int, dateString: String) {
        self.planId = planId
        self.dayNumber = dayNumber
        self.dateString = dateString
        _vm = StateObject(wrappedValue: ReadingDayDetailViewModel(planId: planId, dayNumber: dayNumber))
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return dateString }
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    var body: some View {
        Group {
            if vm.isLoading && vm.day == nil {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let day = vm.day {
                dayContent(day)
            } else if let err = vm.error {
                VStack(spacing: 16) {
                    Text(err)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await vm.load(token: auth.accessToken ?? "") }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Day \(dayNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddEntry = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddEntry) {
            AddReadingEntrySheet(
                isPresented: $showAddEntry,
                planId: planId,
                dayNumber: dayNumber
            ) { entries in
                entries.forEach { vm.entryAdded($0) }
            }
            .environmentObject(auth)
        }
        .task { await vm.load(token: auth.accessToken ?? "") }
        .onAppear { notesText = vm.day?.notes ?? "" }
        .onChange(of: vm.day?.notes) { _, newValue in
            if !editingNotes { notesText = newValue ?? "" }
        }
        .alert("Error", isPresented: .init(
            get: { vm.error != nil && vm.day != nil },
            set: { if !$0 { vm.error = nil } }
        )) {
            Button("OK") { vm.error = nil }
        } message: { Text(vm.error ?? "") }
    }

    // MARK: - Day Content

    @ViewBuilder
    private func dayContent(_ day: ReadingDay) -> some View {
        List {
            // Date header
            Section {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundStyle(Color.accentColor)
                    Text(formattedDate)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Toggle complete button
            Section {
                Button {
                    Task { await vm.toggle(token: auth.accessToken ?? "") }
                } label: {
                    HStack(spacing: 12) {
                        if vm.isToggling {
                            ProgressView()
                                .frame(width: 24, height: 24)
                        } else {
                            Image(systemName: day.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.title2)
                                .foregroundStyle(day.isCompleted ? .green : Color.accentColor)
                        }
                        Text(day.isCompleted ? "Marked Complete" : "Mark as Complete")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(day.isCompleted ? .green : Color.accentColor)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .disabled(vm.isToggling)
            }

            // Reading entries
            Section {
                if day.entries.isEmpty {
                    ContentUnavailableView(
                        "No readings yet",
                        systemImage: "book",
                        description: Text("Tap + to add a reading.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(day.entries) { entry in
                        DayEntryRow(entry: entry)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task {
                                        await vm.deleteEntry(
                                            entryId: entry.id,
                                            token: auth.accessToken ?? ""
                                        )
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            } header: {
                Text("Readings")
            }

            // Notes — always shown, editable
            Section("Notes") {
                if editingNotes {
                    TextEditor(text: $notesText)
                        .frame(minHeight: 80)
                    HStack {
                        Button("Cancel") {
                            editingNotes = false
                            notesText = day.notes ?? ""
                        }
                        .foregroundStyle(.secondary)
                        Spacer()
                        Button("Save") {
                            Task {
                                await vm.updateNotes(
                                    notes: notesText,
                                    token: auth.accessToken ?? ""
                                )
                                editingNotes = false
                            }
                        }
                        .fontWeight(.semibold)
                    }
                } else {
                    HStack {
                        Text(day.notes?.isEmpty == false ? day.notes! : "No notes — tap to add")
                            .foregroundStyle(day.notes?.isEmpty == false ? .primary : .secondary)
                            .italic(day.notes?.isEmpty != false)
                            .font(.subheadline)
                        Spacer()
                        Button {
                            editingNotes = true
                            notesText = day.notes ?? ""
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Day Entry Row

private struct DayEntryRow: View {
    let entry: ReadingEntry

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 36, height: 36)
                Text((entry.bookAbbrev ?? entry.reference).prefix(3))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.reference)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                if let notes = entry.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
