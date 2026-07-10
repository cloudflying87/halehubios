import SwiftUI

// MARK: - ViewModel

@MainActor
class ResourcesHubViewModel: ObservableObject {
    @Published var resources: [Resource] = []
    @Published var letters: [Letter] = []
    @Published var isLoading = false
    @Published var error: String?
    /// Slugs of letters whose detail is saved for offline reading.
    @Published var downloadedSlugs: Set<String> = []
    @Published var downloadingSlugs: Set<String> = []

    private let lettersKey = "letters_list"
    private let resourcesKey = "resources_list"
    private func detailKey(_ slug: String) -> String { "letter_detail_\(slug)" }

    func load(token: String) async {
        isLoading = true
        error = nil

        // Cache-first: show the saved list instantly and as the offline fallback.
        if letters.isEmpty, let cachedL: [Letter] = await CacheManager.shared.load(key: lettersKey) {
            letters = cachedL.sorted { $0.year > $1.year }
        }
        if resources.isEmpty, let cachedR: [Resource] = await CacheManager.shared.load(key: resourcesKey) {
            resources = cachedR
        }
        await refreshDownloaded()

        async let resourcesTask: [Resource] = APIClient.shared.get("/resources/", token: token)
        async let lettersTask: [Letter] = APIClient.shared.get("/letters/", token: token)

        do {
            let (r, l) = try await (resourcesTask, lettersTask)
            resources = r
            letters = l.sorted { $0.year > $1.year }
            await CacheManager.shared.save(r, key: resourcesKey)
            await CacheManager.shared.save(l, key: lettersKey)
        } catch {
            // Offline with a cached list → keep showing it silently.
            if letters.isEmpty && resources.isEmpty {
                self.error = error.localizedDescription
            }
        }

        await refreshDownloaded()
        isLoading = false
    }

    /// Recompute which letters have a cached detail (the offline badge).
    func refreshDownloaded() async {
        var found: Set<String> = []
        for letter in letters {
            if let _: LetterDetail = await CacheManager.shared.load(key: detailKey(letter.slug)) {
                found.insert(letter.slug)
            }
        }
        downloadedSlugs = found
    }

    /// Save a letter (text + photos) for offline reading, straight from the list.
    func downloadLetter(slug: String, token: String) async {
        downloadingSlugs.insert(slug)
        defer { downloadingSlugs.remove(slug) }
        do {
            let detail: LetterDetail = try await APIClient.shared.get("/letters/\(slug)/", token: token)
            await CacheManager.shared.save(detail, key: detailKey(slug))
            for photo in detail.photos {
                await OfflineImageStore.shared.download(photo.url)
            }
            downloadedSlugs.insert(slug)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func archiveLetter(slug: String, token: String) async {
        do {
            struct Req: Encodable { let archived: Bool }
            let _: LetterDetail = try await APIClient.shared.post(
                "/letters/\(slug)/archive/", body: Req(archived: true), token: token
            )
            letters.removeAll { $0.slug == slug }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func archiveResource(slug: String, archived: Bool, token: String) async {
        do {
            let body = ResourceArchiveRequest(archived: archived)
            let _: ResourceDetail = try await APIClient.shared.post(
                "/resources/\(slug)/archive/", body: body, token: token
            )
            await load(token: token)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Hub View

struct ResourcesHubView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = ResourcesHubViewModel()
    @State private var showCreateResource = false
    @State private var showCreateLetter = false
    @State private var showArchive = false
    @State private var shareItem: ShareItem?

    private var canCreate: Bool {
        vm.resources.first?.canEdit ?? vm.letters.first?.canEdit ?? false
    }

    var body: some View {
        Group {
            if vm.isLoading && vm.resources.isEmpty && vm.letters.isEmpty {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }
        }
        .navigationTitle("Resources & Letters")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Archive", systemImage: "archivebox") {
                    showArchive = true
                }
            }
            if canCreate {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("New Resource", systemImage: "doc.text.badge.plus") {
                            showCreateResource = true
                        }
                        Button("New Letter", systemImage: "envelope.badge.plus") {
                            showCreateLetter = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .navigationDestination(isPresented: $showArchive) {
            ArchiveHubView().environmentObject(auth)
        }
        .sheet(isPresented: $showCreateResource) {
            ResourceEditorSheet(mode: .create) { _ in
                Task { await vm.load(token: auth.accessToken ?? "") }
            }
            .environmentObject(auth)
        }
        .sheet(isPresented: $showCreateLetter) {
            LetterEditorSheet(mode: .create) { _ in
                Task { await vm.load(token: auth.accessToken ?? "") }
            }
            .environmentObject(auth)
        }
        .task { await vm.load(token: auth.accessToken ?? "") }
    }

    private var list: some View {
        List {
            if let errorMessage = vm.error {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }

            // Family Letters
            if !vm.letters.isEmpty {
                Section {
                    ForEach(vm.letters) { letter in
                        NavigationLink(
                            destination: LetterDetailView(letter: letter).environmentObject(auth)
                        ) {
                            LetterRow(
                                letter: letter,
                                isDownloaded: vm.downloadedSlugs.contains(letter.slug),
                                isDownloading: vm.downloadingSlugs.contains(letter.slug)
                            )
                        }
                        .swipeActions(edge: .leading) {
                            if !vm.downloadedSlugs.contains(letter.slug) {
                                Button("Download", systemImage: "arrow.down.circle") {
                                    Task { await vm.downloadLetter(slug: letter.slug, token: auth.accessToken ?? "") }
                                }
                                .tint(.blue)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            if let url = URL(string: "https://flyhomemn.com/letters/\(letter.slug)/") {
                                Button("Share", systemImage: "square.and.arrow.up") {
                                    shareItem = ShareItem(url: url)
                                }
                                .tint(.green)
                            }
                            if letter.canEdit {
                                Button("Archive") {
                                    Task { await vm.archiveLetter(slug: letter.slug, token: auth.accessToken ?? "") }
                                }
                                .tint(.orange)
                            }
                        }
                    }
                } header: {
                    Label("Family Letters", systemImage: "envelope.open.fill")
                }
            }

            // Resources
            if !vm.resources.isEmpty {
                Section {
                    ForEach(vm.resources) { resource in
                        NavigationLink(
                            destination: ResourceDetailView(resource: resource).environmentObject(auth)
                        ) {
                            ResourceRow(resource: resource)
                        }
                        .swipeActions(edge: .trailing) {
                            if let url = URL(string: "https://flyhomemn.com/blog/\(resource.slug)/") {
                                Button("Share", systemImage: "square.and.arrow.up") {
                                    shareItem = ShareItem(url: url)
                                }
                                .tint(.green)
                            }
                            if resource.canEdit {
                                Button(resource.isActive ? "Archive" : "Restore") {
                                    Task {
                                        await vm.archiveResource(
                                            slug: resource.slug,
                                            archived: resource.isActive,
                                            token: auth.accessToken ?? ""
                                        )
                                    }
                                }
                                .tint(resource.isActive ? .orange : .green)
                            }
                        }
                    }
                } header: {
                    Label("Resources", systemImage: "doc.text.fill")
                }
            }

            if vm.resources.isEmpty && vm.letters.isEmpty && !vm.isLoading {
                Section {
                    ContentUnavailableView(
                        "Nothing Here Yet",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Resources and family letters will appear here.")
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await vm.load(token: auth.accessToken ?? "") }
        .sheet(item: $shareItem) { item in
            ActivityViewController(items: [item.url])
        }
    }
}

/// Identifiable wrapper so a swiped row can drive `.sheet(item:)` for sharing.
private struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

// MARK: - Letter Row

private struct LetterRow: View {
    let letter: Letter
    var isDownloaded: Bool = false
    var isDownloading: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Text(String(letter.year))
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
                .fixedSize()

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(letter.title)
                        .font(.headline)
                        .lineLimit(1)
                    if isDownloading {
                        ProgressView().controlSize(.mini)
                    } else if isDownloaded {
                        Image(systemName: "checkmark.icloud.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Available offline")
                    }
                }

                HStack(spacing: 10) {
                    if let eventDate = letter.eventDate {
                        Label(formattedDate(eventDate), systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if letter.photoCount > 0 {
                        Label("\(letter.photoCount)", systemImage: "photo.on.rectangle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if letter.hasRsvp {
                        Label("RSVP", systemImage: "person.crop.circle.badge.checkmark")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func formattedDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return dateString }
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Resource Row

private struct ResourceRow: View {
    let resource: Resource

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: resource.isActive ? (resource.contentType == "react" ? "safari" : "doc.text") : "archivebox")
                .foregroundStyle(resource.isActive ? Color.accentColor : .orange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(resource.title)
                        .font(.headline)
                        .lineLimit(1)
                    if !resource.isActive {
                        Text("Archived")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.1), in: Capsule())
                    }
                    if !resource.isPublic {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if !resource.description.isEmpty {
                    Text(resource.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
