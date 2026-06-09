import SwiftUI

// MARK: - ViewModel

@MainActor
class BibleProgressViewModel: ObservableObject {
    @Published var books: [BibleBookProgress] = []
    @Published var isLoading = false
    @Published var error: String?

    func load(planId: String, token: String) async {
        isLoading = true
        error = nil
        do {
            books = try await APIClient.shared.get(
                "/reading/plans/\(planId)/bible-progress/", token: token
            )
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    var otBooks: [BibleBookProgress] { books.filter { $0.testament == "OT" } }
    var ntBooks: [BibleBookProgress] { books.filter { $0.testament == "NT" } }

    var totalBooksStarted: Int { books.filter { $0.isStarted }.count }
    var totalBooksComplete: Int { books.filter { $0.isComplete }.count }
}

// MARK: - View

struct BibleProgressView: View {
    @EnvironmentObject var auth: AuthManager
    let planId: String
    @StateObject private var vm = BibleProgressViewModel()

    var body: some View {
        Group {
            if vm.isLoading && vm.books.isEmpty {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMsg = vm.error, vm.books.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 44))
                        .foregroundStyle(.orange)
                    Text(errorMsg)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await vm.load(planId: planId, token: auth.accessToken ?? "") }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                bookList
            }
        }
        .navigationTitle("Bible Progress")
        .navigationBarTitleDisplayMode(.large)
        .task { await vm.load(planId: planId, token: auth.accessToken ?? "") }
        .refreshable { await vm.load(planId: planId, token: auth.accessToken ?? "") }
    }

    // MARK: - Book List

    private var bookList: some View {
        List {
            // Summary header
            Section {
                HStack(spacing: 20) {
                    statCell(value: vm.totalBooksStarted, label: "Started")
                    statCell(value: vm.totalBooksComplete, label: "Complete")
                    statCell(value: 66 - vm.totalBooksStarted, label: "Not Started")
                }
                .padding(.vertical, 4)
            }

            if !vm.otBooks.isEmpty {
                Section("Old Testament") {
                    ForEach(vm.otBooks, id: \.bookId) { book in
                        bookLink(book)
                    }
                }
            }

            if !vm.ntBooks.isEmpty {
                Section("New Testament") {
                    ForEach(vm.ntBooks, id: \.bookId) { book in
                        bookLink(book)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func bookLink(_ book: BibleBookProgress) -> some View {
        NavigationLink {
            BookDetailView(planId: planId, bookId: book.bookId, bookName: book.bookName)
        } label: {
            BookProgressRow(book: book)
        }
    }

    private func statCell(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.title3.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Book Progress Row

private struct BookProgressRow: View {
    let book: BibleBookProgress

    var body: some View {
        HStack(spacing: 12) {
            // Status dot
            Circle()
                .fill(book.isComplete ? Color.green :
                      book.isStarted ? Color.blue : Color(.systemGray4))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(book.bookName).font(.subheadline)
                if book.totalChapters > 0 {
                    ProgressView(value: Double(book.chaptersRead), total: Double(book.totalChapters))
                        .tint(book.isComplete ? .green : .blue)
                }
            }

            Spacer()

            Text("\(book.chaptersRead)/\(book.totalChapters)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}
