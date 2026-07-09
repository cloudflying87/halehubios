import SwiftUI
import WebKit

// MARK: - ViewModel

@MainActor
class ResourceDetailViewModel: ObservableObject {
    @Published var detail: ResourceDetail?
    @Published var isLoading = false
    @Published var isSaving = false
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

    func archive(slug: String, archived: Bool, token: String) async {
        isSaving = true
        do {
            let body = ResourceArchiveRequest(archived: archived)
            let updated: ResourceDetail = try await APIClient.shared.post(
                "/resources/\(slug)/archive/", body: body, token: token
            )
            detail = updated
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}

// MARK: - View

struct ResourceDetailView: View {
    @EnvironmentObject var auth: AuthManager
    let resource: Resource

    @StateObject private var vm = ResourceDetailViewModel()
    @State private var showEditor = false
    @State private var showDeleteConfirm = false

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
            } else if let detail = vm.detail {
                contentView(detail: detail)
            } else {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(resource.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if let detail = vm.detail, let shareURL = URL(string: "https://flyhomemn.com/blog/\(detail.slug)/") {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: shareURL, subject: Text(detail.title)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                if detail.canEdit {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Edit", systemImage: "pencil") { showEditor = true }
                            Divider()
                            Button(
                                detail.isActive ? "Archive" : "Restore",
                                systemImage: detail.isActive ? "archivebox" : "arrow.uturn.backward"
                            ) {
                                Task {
                                    await vm.archive(
                                        slug: detail.slug,
                                        archived: detail.isActive,
                                        token: auth.accessToken ?? ""
                                    )
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            if let detail = vm.detail {
                ResourceEditorSheet(mode: .edit(detail)) { _ in
                    Task { await vm.load(slug: detail.slug, token: auth.accessToken ?? "") }
                }
                .environmentObject(auth)
            }
        }
        .task { await vm.load(slug: resource.slug, token: auth.accessToken ?? "") }
    }

    @ViewBuilder
    private func contentView(detail: ResourceDetail) -> some View {
        if !detail.isActive {
            // Archived banner
            HStack(spacing: 8) {
                Image(systemName: "archivebox")
                Text("Archived")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.1))
        }

        if detail.contentType == "react" {
            // React components can't run on iOS — show a friendly link to the web version
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "safari")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.accentColor)
                VStack(spacing: 8) {
                    Text("View in Browser")
                        .font(.title3.weight(.semibold))
                    Text("This content uses interactive components\nthat are only available on the web.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if let url = URL(string: "https://flyhomemn.com/blog/\(detail.slug)/") {
                    Link(destination: url) {
                        Label("Open \(detail.title)", systemImage: "arrow.up.right.square")
                            .frame(maxWidth: 280)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if let html = detail.contentHtml, !html.isEmpty {
            HTMLWebView(html: html)
        } else {
            // Fallback for older API responses without contentHtml
            ScrollView {
                MarkdownContentView(content: detail.content)
                    .padding(20)
            }
        }
    }
}

// MARK: - WKWebView wrapper

struct HTMLWebView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.showsHorizontalScrollIndicator = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let css = """
        <style>
        :root { color-scheme: light dark; }
        body {
            font-family: -apple-system, sans-serif;
            font-size: 17px;
            line-height: 1.6;
            padding: 16px;
            margin: 0;
            word-break: break-word;
        }
        h1, h2, h3, h4 { color: #1E4D6B; margin-top: 1.2em; }
        a { color: #1E4D6B; }
        img { max-width: 100%; height: auto; border-radius: 8px; }
        code {
            background: rgba(127,127,127,0.15);
            padding: 2px 4px;
            border-radius: 4px;
            font-family: ui-monospace, monospace;
            font-size: 0.875em;
        }
        pre {
            background: rgba(127,127,127,0.1);
            padding: 12px;
            border-radius: 8px;
            overflow-x: auto;
        }
        pre code { background: none; padding: 0; }
        blockquote {
            border-left: 4px solid #1E4D6B;
            margin: 1em 0;
            padding-left: 12px;
            color: #666;
        }
        ul, ol { padding-left: 1.5em; }
        li { margin-bottom: 4px; }
        input[type=checkbox] { accent-color: #1E4D6B; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid rgba(127,127,127,0.3); padding: 8px; text-align: left; }
        th { background: rgba(127,127,127,0.1); }
        @media (prefers-color-scheme: dark) {
            blockquote { color: #aaa; }
        }
        </style>
        """
        webView.loadHTMLString(css + html, baseURL: URL(string: "https://flyhomemn.com"))
    }
}

// MARK: - Markdown Content (fallback)

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
            Text(content)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
