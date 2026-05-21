import SwiftUI

// MARK: - ViewModel

@MainActor
class AddReadingEntryViewModel: ObservableObject {
    @Published var books: [BibleBook] = []
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var error: String?

    func loadBooks(token: String) async {
        isLoading = true
        do {
            books = try await APIClient.shared.get("/reading/books/", token: token)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func addEntry(planId: String, dayNum: Int, bookId: Int,
                  chapterStart: Int, verseStart: Int,
                  chapterEnd: Int, verseEnd: Int,
                  notes: String, token: String) async throws -> ReadingEntry {
        let req = AddReadingEntryRequest(
            bookId: bookId,
            chapterStart: chapterStart,
            verseStart: verseStart,
            chapterEnd: chapterEnd,
            verseEnd: verseEnd,
            notes: notes
        )
        return try await APIClient.shared.post(
            "/reading/plans/\(planId)/days/\(dayNum)/entries/", body: req, token: token
        )
    }

    var otBooks: [BibleBook] { books.filter { $0.testament == "OT" } }
    var ntBooks: [BibleBook] { books.filter { $0.testament == "NT" } }
}

// MARK: - View

struct AddReadingEntrySheet: View {
    @EnvironmentObject var auth: AuthManager
    @Binding var isPresented: Bool
    let planId: String
    let dayNumber: Int
    var onAdded: (ReadingEntry) -> Void

    @StateObject private var vm = AddReadingEntryViewModel()
    @State private var selectedBook: BibleBook?
    @State private var chapterStartText = "1"
    @State private var verseStartText = "1"
    @State private var chapterEndText = "1"
    @State private var verseEndText = "1"
    @State private var notes = ""
    @State private var saveError: String?
    @State private var isSaving = false

    private var chapterStart: Int { Int(chapterStartText) ?? 1 }
    private var verseStart: Int { Int(verseStartText) ?? 1 }
    private var chapterEnd: Int { Int(chapterEndText) ?? 1 }
    private var verseEnd: Int { Int(verseEndText) ?? 1 }

    private var canAdd: Bool {
        selectedBook != nil && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                // Book picker
                Section("Book") {
                    if vm.isLoading {
                        HStack {
                            ProgressView()
                            Text("Loading books…")
                                .foregroundStyle(.secondary)
                                .padding(.leading, 8)
                        }
                    } else {
                        Picker("Book", selection: $selectedBook) {
                            Text("Select a book…").tag(Optional<BibleBook>.none)

                            if !vm.otBooks.isEmpty {
                                Section("Old Testament") {
                                    ForEach(vm.otBooks) { book in
                                        Text(book.name).tag(Optional(book))
                                    }
                                }
                            }

                            if !vm.ntBooks.isEmpty {
                                Section("New Testament") {
                                    ForEach(vm.ntBooks) { book in
                                        Text(book.name).tag(Optional(book))
                                    }
                                }
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                }

                // Passage range
                Section {
                    HStack {
                        Text("Chapter Start")
                        Spacer()
                        TextField("1", text: $chapterStartText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                    }
                    HStack {
                        Text("Verse Start")
                        Spacer()
                        TextField("1", text: $verseStartText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                    }
                    HStack {
                        Text("Chapter End")
                        Spacer()
                        TextField("1", text: $chapterEndText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                    }
                    HStack {
                        Text("Verse End")
                        Spacer()
                        TextField("1", text: $verseEndText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                    }
                } header: {
                    Text("Passage")
                } footer: {
                    Text("e.g. Genesis 1:1–2:3")
                        .font(.caption)
                }

                // Notes
                Section("Notes (optional)") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }

                // Error
                if let err = saveError {
                    Section {
                        Text(err)
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("Add Reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Add") {
                            Task { await save() }
                        }
                        .disabled(!canAdd)
                    }
                }
            }
            .task { await vm.loadBooks(token: auth.accessToken ?? "") }
        }
    }

    private func save() async {
        guard let book = selectedBook else { return }
        isSaving = true
        saveError = nil
        do {
            let entry = try await vm.addEntry(
                planId: planId,
                dayNum: dayNumber,
                bookId: book.id,
                chapterStart: chapterStart,
                verseStart: verseStart,
                chapterEnd: chapterEnd,
                verseEnd: verseEnd,
                notes: notes,
                token: auth.accessToken ?? ""
            )
            onAdded(entry)
            isPresented = false
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}
