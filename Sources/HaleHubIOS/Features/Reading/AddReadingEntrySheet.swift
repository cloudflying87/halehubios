import SwiftUI

// MARK: - Mode

private enum EntryMode: String, CaseIterable {
    case single = "Single"
    case bulk = "Bulk"
}

// MARK: - ViewModel

@MainActor
class AddReadingEntryViewModel: ObservableObject {
    @Published var books: [BibleBook] = []
    @Published var isLoading = false
    @Published var error: String?

    var otBooks: [BibleBook] { books.filter { $0.testament == "OT" } }
    var ntBooks: [BibleBook] { books.filter { $0.testament == "NT" } }

    func loadBooks(token: String) async {
        isLoading = true
        do {
            books = try await APIClient.shared.get("/reading/books/", token: token)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func addSingle(planId: String, dayNum: Int, req: AddReadingEntryRequest,
                   token: String) async throws -> ReadingEntry {
        return try await APIClient.shared.post(
            "/reading/plans/\(planId)/days/\(dayNum)/entries/",
            body: req, token: token
        )
    }

    func previewBulk(planId: String, dayNum: Int, references: String,
                     token: String) async throws -> BulkPreviewResponse {
        return try await APIClient.shared.post(
            "/reading/plans/\(planId)/days/\(dayNum)/entries/bulk/?dry_run=true",
            body: BulkAddRequest(references: references), token: token
        )
    }

    func addBulk(planId: String, dayNum: Int, references: String,
                 token: String) async throws -> BulkAddResponse {
        return try await APIClient.shared.post(
            "/reading/plans/\(planId)/days/\(dayNum)/entries/bulk/",
            body: BulkAddRequest(references: references), token: token
        )
    }
}

// MARK: - Sheet

struct AddReadingEntrySheet: View {
    @EnvironmentObject var auth: AuthManager
    @Binding var isPresented: Bool
    let planId: String
    let dayNumber: Int
    var onAdded: ([ReadingEntry]) -> Void

    @StateObject private var vm = AddReadingEntryViewModel()
    @State private var mode: EntryMode = .single

    // Single mode state
    @State private var selectedBook: BibleBook?
    @State private var chapterStart = 1
    @State private var verseStart = 1
    @State private var chapterEnd = 1
    @State private var verseEnd = 1
    @State private var entryNotes = ""
    @State private var isSaving = false
    @State private var saveError: String?

    // Bulk mode state
    @State private var bulkText = ""
    @State private var isBulkSaving = false
    @State private var isBulkPreviewing = false
    @State private var bulkPreview: BulkPreviewResponse?
    @State private var bulkResult: BulkAddResponse?
    @State private var bulkError: String?
    @State private var previewTask: Task<Void, Never>?

    // MARK: Validation helpers (single mode)

    private var maxChapterStart: Int { selectedBook?.totalChapters ?? 999 }
    private var maxVerseStart: Int { selectedBook?.totalVerses(forChapter: chapterStart) ?? 999 }
    private var maxChapterEnd: Int { selectedBook?.totalChapters ?? 999 }
    private var maxVerseEnd: Int { selectedBook?.totalVerses(forChapter: chapterEnd) ?? 999 }

    private var chapterStartError: String? {
        guard let book = selectedBook, book.totalChapters > 0 else { return nil }
        if chapterStart < 1 { return "Must be at least 1" }
        if chapterStart > book.totalChapters { return "\(book.name) has \(book.totalChapters) chapters" }
        return nil
    }
    private var verseStartError: String? {
        let max = maxVerseStart
        guard max > 0 else { return nil }
        if verseStart < 1 { return "Must be at least 1" }
        if verseStart > max { return "Chapter \(chapterStart) has \(max) verses" }
        return nil
    }
    private var chapterEndError: String? {
        guard let book = selectedBook, book.totalChapters > 0 else { return nil }
        if chapterEnd < chapterStart { return "End before start" }
        if chapterEnd > book.totalChapters { return "\(book.name) has \(book.totalChapters) chapters" }
        return nil
    }
    private var verseEndError: String? {
        let max = maxVerseEnd
        guard max > 0 else { return nil }
        if chapterEnd == chapterStart && verseEnd < verseStart { return "End before start" }
        if verseEnd > max { return "Chapter \(chapterEnd) has \(max) verses" }
        return nil
    }
    private var singleFormValid: Bool {
        selectedBook != nil
            && chapterStartError == nil
            && verseStartError == nil
            && chapterEndError == nil
            && verseEndError == nil
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                Picker("Mode", selection: $mode) {
                    ForEach(EntryMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                if mode == .single {
                    singleForm
                } else {
                    bulkForm
                }
            }
            .navigationTitle("Add Reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving || isBulkSaving {
                        ProgressView()
                    } else {
                        Button("Add") {
                            Task {
                                if mode == .single { await saveSingle() }
                                else { await saveBulk() }
                            }
                        }
                        .disabled(mode == .single ? (!singleFormValid || isSaving)
                                                  : (bulkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBulkSaving))
                        .fontWeight(.semibold)
                    }
                }
            }
            .task { await vm.loadBooks(token: auth.accessToken ?? "") }
        }
    }

    // MARK: Single form

    @ViewBuilder
    private var singleForm: some View {
        // Book picker
        Section("Book") {
            if vm.isLoading {
                HStack {
                    ProgressView()
                    Text("Loading…").foregroundStyle(.secondary).padding(.leading, 8)
                }
            } else {
                Picker("Book", selection: $selectedBook) {
                    Text("Select a book…").tag(Optional<BibleBook>.none)
                    if !vm.otBooks.isEmpty {
                        Section("Old Testament") {
                            ForEach(vm.otBooks) { book in Text(book.name).tag(Optional(book)) }
                        }
                    }
                    if !vm.ntBooks.isEmpty {
                        Section("New Testament") {
                            ForEach(vm.ntBooks) { book in Text(book.name).tag(Optional(book)) }
                        }
                    }
                }
                .pickerStyle(.navigationLink)
                .onChange(of: selectedBook) { _, book in
                    if let book {
                        chapterStart = 1
                        chapterEnd = 1
                        verseStart = 1
                        verseEnd = book.totalVerses(forChapter: 1)
                    }
                }
            }
        }

        // Passage range
        Section {
            passageRow(label: "Chapter Start", value: $chapterStart,
                       range: 1...max(1, maxChapterStart), error: chapterStartError,
                       onChange: { v in
                           if chapterEnd < v { chapterEnd = v }
                           verseStart = 1
                           verseEnd = max(1, selectedBook?.totalVerses(forChapter: v) ?? 1)
                       })
            passageRow(label: "Verse Start", value: $verseStart,
                       range: 1...max(1, maxVerseStart), error: verseStartError)
            passageRow(label: "Chapter End", value: $chapterEnd,
                       range: max(1, chapterStart)...max(1, maxChapterEnd), error: chapterEndError,
                       onChange: { v in
                           verseEnd = max(1, selectedBook?.totalVerses(forChapter: v) ?? 1)
                       })
            passageRow(label: "Verse End", value: $verseEnd,
                       range: 1...max(1, maxVerseEnd), error: verseEndError)
        } header: {
            Text("Passage")
        } footer: {
            if let book = selectedBook {
                Text("\(book.name) has \(book.totalChapters) chapters")
                    .foregroundStyle(.secondary)
            } else {
                Text("e.g. Psalm 23:1–6 or Genesis 1:1–2:3")
            }
        }

        // Notes
        Section("Notes (optional)") {
            TextEditor(text: $entryNotes).frame(minHeight: 60)
        }

        if let err = saveError {
            Section { Text(err).foregroundStyle(.red).font(.subheadline) }
        }
    }

    @ViewBuilder
    private func passageRow(label: String, value: Binding<Int>, range: ClosedRange<Int>,
                             error: String?, onChange: ((Int) -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Stepper("\(value.wrappedValue)",
                        value: value,
                        in: range,
                        onEditingChanged: { _ in onChange?(value.wrappedValue) })
                    .fixedSize()
                    .onChange(of: value.wrappedValue) { _, v in onChange?(v) }
            }
            if let err = error {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: Bulk form

    @ViewBuilder
    private var bulkForm: some View {
        Section {
            TextEditor(text: $bulkText)
                .frame(minHeight: 140)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: bulkText) { _, text in
                    bulkResult = nil
                    bulkError = nil
                    schedulePreview(text: text)
                }
        } header: {
            Text("Paste references")
        } footer: {
            Text("One per line, or separated by commas or ·\nExample: Genesis 1:1-2:3")
                .font(.caption)
        }

        // Live validation preview
        if isBulkPreviewing {
            Section {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Validating…").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        } else if let preview = bulkPreview, !bulkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Section {
                ForEach(preview.valid, id: \.input) { item in
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.reference).font(.subheadline).fontWeight(.medium)
                            if item.input != item.reference {
                                Text(item.input).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                ForEach(preview.errors, id: \.input) { err in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(err.input.isEmpty ? "(empty)" : err.input)
                                .font(.subheadline).fontWeight(.medium)
                            Text(err.error).font(.caption).foregroundStyle(.red)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Preview")
                    Spacer()
                    if preview.validCount > 0 {
                        Text("\(preview.validCount) valid · \(preview.errorCount) error\(preview.errorCount == 1 ? "" : "s")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }

        // Post-save results
        if let result = bulkResult {
            Section {
                Label("\(result.savedCount) reading\(result.savedCount == 1 ? "" : "s") added",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                ForEach(result.errors, id: \.input) { err in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(err.input.isEmpty ? "(empty)" : err.input)
                            .font(.caption.bold())
                        Text(err.error).font(.caption).foregroundStyle(.red)
                    }
                }
            } header: { Text("Results") }
        }

        if let err = bulkError {
            Section { Text(err).foregroundStyle(.red).font(.subheadline) }
        }
    }

    private func schedulePreview(text: String) {
        previewTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { bulkPreview = nil; return }
        previewTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            isBulkPreviewing = true
            do {
                let preview = try await vm.previewBulk(
                    planId: planId, dayNum: dayNumber,
                    references: trimmed, token: auth.accessToken ?? ""
                )
                bulkPreview = preview
            } catch { }
            isBulkPreviewing = false
        }
    }

    // MARK: Save actions

    private func saveSingle() async {
        guard let book = selectedBook else { return }
        isSaving = true; saveError = nil
        let req = AddReadingEntryRequest(bookId: book.id, chapterStart: chapterStart,
                                         verseStart: verseStart, chapterEnd: chapterEnd,
                                         verseEnd: verseEnd, notes: entryNotes)
        do {
            let entry = try await vm.addSingle(planId: planId, dayNum: dayNumber,
                                               req: req, token: auth.accessToken ?? "")
            onAdded([entry])
            isPresented = false
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }

    private func saveBulk() async {
        let text = bulkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isBulkSaving = true; bulkError = nil; bulkResult = nil
        do {
            let result = try await vm.addBulk(planId: planId, dayNum: dayNumber,
                                              references: text, token: auth.accessToken ?? "")
            bulkResult = result
            if result.savedCount > 0 {
                onAdded(result.saved)
                if result.errorCount == 0 { isPresented = false }
                // If there were errors, stay open so user can see what failed
            }
        } catch {
            bulkError = error.localizedDescription
        }
        isBulkSaving = false
    }
}
