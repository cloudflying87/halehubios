import SwiftUI

/// Edit an existing reading entry on a day (book + chapter/verse range + notes).
/// PATCHes /reading/entries/<id>/ and hands the updated entry back to the parent.
struct EditReadingEntrySheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    let entry: ReadingEntry
    var onSaved: (ReadingEntry) -> Void

    @StateObject private var vm = AddReadingEntryViewModel()

    @State private var selectedBook: BibleBook?
    @State private var chapterStart = 1
    @State private var verseStart = 1
    @State private var chapterEnd = 1
    @State private var verseEnd = 1
    @State private var entryNotes = ""
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var didPopulate = false

    private var maxChapter: Int { selectedBook?.totalChapters ?? 999 }
    private var maxVerseStart: Int { selectedBook?.totalVerses(forChapter: chapterStart) ?? 999 }
    private var maxVerseEnd: Int { selectedBook?.totalVerses(forChapter: chapterEnd) ?? 999 }
    private var formValid: Bool {
        selectedBook != nil && chapterEnd >= chapterStart
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Book") {
                    if vm.isLoading && vm.books.isEmpty {
                        HStack { ProgressView(); Text("Loading…").foregroundStyle(.secondary).padding(.leading, 8) }
                    } else {
                        Picker("Book", selection: $selectedBook) {
                            Text("Select a book…").tag(Optional<BibleBook>.none)
                            if !vm.otBooks.isEmpty {
                                Section("Old Testament") {
                                    ForEach(vm.otBooks) { Text($0.name).tag(Optional($0)) }
                                }
                            }
                            if !vm.ntBooks.isEmpty {
                                Section("New Testament") {
                                    ForEach(vm.ntBooks) { Text($0.name).tag(Optional($0)) }
                                }
                            }
                        }
                        .pickerStyle(.navigationLink)
                        .onChange(of: selectedBook) { _, book in
                            // Only reset the range when the user actively changes book
                            // (not during the initial populate).
                            if didPopulate, let book {
                                chapterStart = 1; chapterEnd = 1
                                verseStart = 1; verseEnd = max(1, book.totalVerses(forChapter: 1))
                            }
                        }
                    }
                }

                Section {
                    stepperRow("Chapter Start", $chapterStart, 1...max(1, maxChapter)) { v in
                        if chapterEnd < v { chapterEnd = v }
                    }
                    stepperRow("Verse Start", $verseStart, 1...max(1, maxVerseStart))
                    stepperRow("Chapter End", $chapterEnd, max(1, chapterStart)...max(1, maxChapter))
                    stepperRow("Verse End", $verseEnd, 1...max(1, maxVerseEnd))
                } header: {
                    Text("Passage")
                } footer: {
                    if let book = selectedBook {
                        Text("\(book.name) has \(book.totalChapters) chapters")
                    }
                }

                Section("Notes (optional)") {
                    TextEditor(text: $entryNotes).frame(minHeight: 60)
                }

                if let err = saveError {
                    Section { Text(err).foregroundStyle(.red).font(.subheadline) }
                }
            }
            .navigationTitle("Edit Reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(!formValid)
                            .fontWeight(.semibold)
                    }
                }
            }
            .task {
                await vm.loadBooks(token: auth.accessToken ?? "")
                populate()
            }
        }
    }

    @ViewBuilder
    private func stepperRow(_ label: String, _ value: Binding<Int>, _ range: ClosedRange<Int>,
                            onChange: ((Int) -> Void)? = nil) -> some View {
        HStack {
            Text(label)
            Spacer()
            Stepper("\(value.wrappedValue)", value: value, in: range)
                .fixedSize()
                .onChange(of: value.wrappedValue) { _, v in onChange?(v) }
        }
    }

    private func populate() {
        guard !didPopulate else { return }
        selectedBook = vm.books.first { $0.name == entry.bookName }
        chapterStart = entry.chapterStart ?? 1
        verseStart = entry.verseStart ?? 1
        chapterEnd = entry.chapterEnd ?? (entry.chapterStart ?? 1)
        verseEnd = entry.verseEnd ?? (entry.verseStart ?? 1)
        entryNotes = entry.notes ?? ""
        didPopulate = true
    }

    private func save() async {
        guard let book = selectedBook else { return }
        isSaving = true; saveError = nil
        let req = AddReadingEntryRequest(
            bookId: book.id, chapterStart: chapterStart, verseStart: verseStart,
            chapterEnd: chapterEnd, verseEnd: verseEnd, notes: entryNotes
        )
        do {
            let updated = try await vm.updateSingle(entryId: entry.id, req: req, token: auth.accessToken ?? "")
            onSaved(updated)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}
