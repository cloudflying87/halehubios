import SwiftUI

@MainActor
class BookDetailViewModel: ObservableObject {
    @Published var detail: BookProgressDetail?
    @Published var isLoading = false
    @Published var error: String?

    func load(planId: String, bookId: String, token: String) async {
        isLoading = true
        error = nil
        do {
            detail = try await APIClient.shared.get(
                "/reading/plans/\(planId)/books/\(bookId)/", token: token
            )
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

/// Lists a book's chapters, highlighting which are missing (not fully read).
struct BookDetailView: View {
    @EnvironmentObject var auth: AuthManager
    let planId: String
    let bookId: String
    let bookName: String

    @StateObject private var vm = BookDetailViewModel()

    private var missingCount: Int {
        vm.detail?.chapters.filter { !$0.isComplete }.count ?? 0
    }

    var body: some View {
        Group {
            if vm.isLoading && vm.detail == nil {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let msg = vm.error, vm.detail == nil {
                ContentUnavailableView {
                    Label("Couldn't Load", systemImage: "exclamationmark.triangle")
                } description: { Text(msg) } actions: {
                    Button("Retry") { Task { await load() } }.buttonStyle(.borderedProminent)
                }
            } else if let detail = vm.detail {
                List {
                    Section {
                        HStack {
                            Label("\(missingCount) chapter\(missingCount == 1 ? "" : "s") left",
                                  systemImage: missingCount == 0 ? "checkmark.seal.fill" : "circle.dashed")
                                .foregroundStyle(missingCount == 0 ? .green : .secondary)
                            Spacer()
                            Text("\(detail.chapters.count - missingCount)/\(detail.chapters.count) done")
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    Section("Chapters") {
                        ForEach(detail.chapters) { ch in
                            NavigationLink {
                                ChapterDetailView(bookName: detail.bookName, chapter: ch)
                            } label: {
                                ChapterRow(chapter: ch)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(bookName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        await vm.load(planId: planId, bookId: bookId, token: auth.accessToken ?? "")
    }
}

private struct ChapterRow: View {
    let chapter: ChapterProgress

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: chapter.isComplete ? "checkmark.circle.fill"
                  : chapter.isStarted ? "circle.lefthalf.filled" : "circle")
                .foregroundStyle(chapter.isComplete ? .green : chapter.isStarted ? .blue : Color(.systemGray3))
            Text("Chapter \(chapter.chapterNumber)").font(.subheadline)
            Spacer()
            if chapter.totalVerses > 0 {
                Text("\(chapter.versesRead)/\(chapter.totalVerses)")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            } else if !chapter.isComplete {
                Text("missing").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
