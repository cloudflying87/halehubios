import SwiftUI

// MARK: - ViewModel

@MainActor
class ResourceDetailViewModel: ObservableObject {
    @Published var detail: ResourceDetail?
    @Published var isLoading = false
    @Published var error: String?

    func load(slug: String, token: String) async {
        isLoading = true
        error = nil
        do {
            detail = try await APIClient.shared.get("/resources/\(slug)/", token: token)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - View

struct ResourceDetailView: View {
    @EnvironmentObject var auth: AuthManager
    let resource: Resource

    @StateObject private var vm = ResourceDetailViewModel()

    var body: some View {
        Group {
            if vm.isLoading && vm.detail == nil {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = vm.error, vm.detail == nil {
                ContentUnavailableView {
                    Label("Couldn't Load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again") {
                        Task { await vm.load(slug: resource.slug, token: auth.accessToken ?? "") }
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Description subtitle
                        if !resource.description.isEmpty {
                            Text(resource.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.bottom, 4)
                        }

                        Divider()

                        // Markdown content
                        if let detail = vm.detail {
                            MarkdownContentView(content: detail.content)
                        } else {
                            // Skeleton while content loads after detail is nil (first render)
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle(resource.title)
        .navigationBarTitleDisplayMode(.large)
        .task { await vm.load(slug: resource.slug, token: auth.accessToken ?? "") }
    }
}

// MARK: - Markdown Content

/// Renders Markdown using AttributedString with a plain-text fallback.
struct MarkdownContentView: View {
    let content: String

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: content,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            Text(attributed)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            // Plain-text fallback — no crash if markdown parsing fails
            Text(content)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
