import SwiftUI

// MARK: - ViewModel

@MainActor
class ReadingDayDetailViewModel: ObservableObject {
    @Published var day: ReadingDay?
    @Published var isLoading = false
    @Published var error: String?
    @Published var isToggling = false

    let planId: String
    @Published private(set) var dayNumber: Int

    init(planId: String, dayNumber: Int) {
        self.planId = planId
        self.dayNumber = dayNumber
    }

    /// Switch to another day in the same plan and reload it in place.
    func goToDay(_ newDay: Int, token: String) async {
        guard newDay >= 1, newDay != dayNumber else { return }
        dayNumber = newDay
        await load(token: token)
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

    /// Moves a single entry to a different day in the same plan.
    /// On success the entry disappears from this view (it now belongs to
    /// the target day). Errors surface via `vm.error`.
    func moveEntry(entryId: String, toDayNumber: Int, token: String) async {
        guard toDayNumber != dayNumber else { return }
        do {
            let req = MoveReadingEntryRequest(dayNumber: toDayNumber)
            let _: ReadingEntry = try await APIClient.shared.post(
                "/reading/entries/\(entryId)/move/",
                body: req, token: token
            )
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

    func entryUpdated(_ entry: ReadingEntry) {
        if let d = day {
            day = ReadingDay(
                dayNumber: d.dayNumber,
                date: d.date,
                isCompleted: d.isCompleted,
                entries: d.entries.map { $0.id == entry.id ? entry : $0 },
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
    let totalDays: Int?      // upper bound for next-day navigation (nil = unbounded)

    @StateObject private var vm: ReadingDayDetailViewModel
    @State private var showAddEntry = false
    @State private var editingNotes = false
    @State private var notesText = ""
    @State private var movingEntry: ReadingEntry?     // non-nil → move sheet visible
    @State private var editingEntry: ReadingEntry?    // non-nil → edit sheet visible
    /// Non-nil → alert with the "N saved, M had errors" summary after a bulk add.
    @State private var bulkResultSummary: BulkAddSummary?

    init(planId: String, dayNumber: Int, dateString: String, totalDays: Int? = nil) {
        self.planId = planId
        self.dayNumber = dayNumber
        self.dateString = dateString
        self.totalDays = totalDays
        _vm = StateObject(wrappedValue: ReadingDayDetailViewModel(planId: planId, dayNumber: dayNumber))
    }

    private var formattedDate: String {
        // Prefer the loaded day's date so it stays correct while paging days.
        let source = vm.day?.date ?? dateString
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: source) else { return source }
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private var canGoNext: Bool {
        if let total = totalDays { return vm.dayNumber < total }
        return true
    }

    private func goToDay(_ newDay: Int) {
        Task { await vm.goToDay(newDay, token: auth.accessToken ?? "") }
    }

    var body: some View {
        Group {
            if vm.isLoading && vm.day == nil {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let day = vm.day {
                dayContent(day)
            } else {
                // Error or empty — always show something visible
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundStyle(.orange)
                    Text(vm.error ?? "Could not load this day.")
                        .foregroundStyle(.secondary)
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
        .navigationTitle("Day \(vm.dayNumber)")
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
                dayNumber: vm.dayNumber,
                onAdded: { entries in entries.forEach { vm.entryAdded($0) } },
                onBulkResult: { result in
                    // Only surface an alert when there's something worth saying.
                    if result.errorCount > 0 || result.savedCount > 1 {
                        bulkResultSummary = BulkAddSummary(
                            saved: result.savedCount,
                            errors: result.errors,
                        )
                    }
                }
            )
            .environmentObject(auth)
        }
        .alert(
            bulkResultSummary?.title ?? "",
            isPresented: Binding(
                get: { bulkResultSummary != nil },
                set: { if !$0 { bulkResultSummary = nil } }
            ),
            presenting: bulkResultSummary,
        ) { _ in
            Button("OK") { bulkResultSummary = nil }
        } message: { summary in
            Text(summary.detail)
        }
        .sheet(item: $movingEntry) { entry in
            MoveReadingEntrySheet(
                entry: entry,
                currentDayNumber: vm.dayNumber
            ) { targetDay in
                Task {
                    await vm.moveEntry(
                        entryId: entry.id,
                        toDayNumber: targetDay,
                        token: auth.accessToken ?? ""
                    )
                }
            }
        }
        .sheet(item: $editingEntry) { entry in
            EditReadingEntrySheet(entry: entry) { updated in
                vm.entryUpdated(updated)
            }
            .environmentObject(auth)
        }
        .task { await vm.load(token: auth.accessToken ?? "") }
        .onAppear { notesText = vm.day?.notes ?? "" }
        .onChange(of: vm.day?.notes) { _, newValue in
            if !editingNotes { notesText = newValue ?? "" }
        }
        .alert("Error", isPresented: .init(
            get: { vm.error != nil && vm.day != nil },  // only for non-fatal errors when day is loaded
            set: { if !$0 { vm.error = nil } }
        )) {
            Button("OK") { vm.error = nil }
        } message: { Text(vm.error ?? "") }

    }

    // MARK: - Day Content

    @ViewBuilder
    private func dayContent(_ day: ReadingDay) -> some View {
        List {
            // Previous / next day navigation
            Section {
                HStack {
                    if vm.dayNumber > 1 {
                        Button { goToDay(vm.dayNumber - 1) } label: {
                            Label("Day \(vm.dayNumber - 1)", systemImage: "chevron.left")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    Spacer()
                    if canGoNext {
                        Button { goToDay(vm.dayNumber + 1) } label: {
                            HStack(spacing: 4) {
                                Text("Day \(vm.dayNumber + 1)")
                                Image(systemName: "chevron.right")
                            }
                        }
                    }
                }
                .font(.subheadline.weight(.medium))
                .buttonStyle(.borderless)
            }

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
                            .contentShape(Rectangle())
                            .onTapGesture { editingEntry = entry }
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
                                Button {
                                    movingEntry = entry
                                } label: {
                                    Label("Move…", systemImage: "arrow.right.arrow.left")
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    editingEntry = entry
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.orange)
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

// MARK: - Move Reading Entry Sheet

/// Sheet that lets the user move a single reading entry to a different day
/// of the same plan. Day-number validation lives on the backend — bad
/// values surface via the parent's `vm.error` alert after the sheet closes.
struct MoveReadingEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    let entry: ReadingEntry
    let currentDayNumber: Int
    var onMove: (Int) -> Void

    @State private var targetDayString: String = ""

    private var parsedTargetDay: Int? {
        let trimmed = targetDayString.trimmingCharacters(in: .whitespaces)
        guard let n = Int(trimmed), n > 0 else { return nil }
        return n
    }

    private var canMove: Bool {
        guard let target = parsedTargetDay else { return false }
        return target != currentDayNumber
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "book")
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.reference)
                                .font(.body.weight(.medium))
                            Text("Currently on day \(currentDayNumber)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Moving")
                }

                Section {
                    HStack {
                        Text("Day number")
                        Spacer()
                        TextField("e.g. 145", text: $targetDayString)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                    }
                } header: {
                    Text("Move to")
                } footer: {
                    Text("Enter the day number you want to move this reading to. If the target day doesn't have an entry yet it will be created automatically.")
                        .font(.caption)
                }
            }
            .navigationTitle("Move Reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") {
                        if let target = parsedTargetDay {
                            onMove(target)
                            dismiss()
                        }
                    }
                    .disabled(!canMove)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Bulk add result summary

/// Lightweight container for the post-bulk-add alert message. Built from a
/// BulkAddResponse so we don't keep the full response around — just what
/// the alert needs.
private struct BulkAddSummary {
    let saved: Int
    let errors: [BulkEntryError]

    var title: String {
        if errors.isEmpty {
            return saved == 1 ? "1 reading added" : "\(saved) readings added"
        }
        if saved == 0 {
            return "Nothing added"
        }
        return "\(saved) added, \(errors.count) skipped"
    }

    var detail: String {
        if errors.isEmpty { return "" }
        // Cap at the first few so the alert stays compact.
        let preview = errors.prefix(4).map { "• \($0.input.isEmpty ? "(empty)" : $0.input): \($0.error)" }
        var msg = preview.joined(separator: "\n")
        if errors.count > 4 {
            msg += "\n+ \(errors.count - 4) more"
        }
        return msg
    }
}
