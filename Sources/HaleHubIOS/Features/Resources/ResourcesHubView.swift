import SwiftUI

// MARK: - ViewModel

@MainActor
class ResourcesHubViewModel: ObservableObject {
    @Published var resources: [Resource] = []
    @Published var letters: [Letter] = []
    @Published var isLoading = false
    @Published var error: String?

    func load(token: String) async {
        isLoading = true
        error = nil

        async let resourcesTask: [Resource] = APIClient.shared.get("/resources/", token: token)
        async let lettersTask: [Letter] = APIClient.shared.get("/letters/", token: token)

        do {
            let (r, l) = try await (resourcesTask, lettersTask)
            resources = r
            letters = l.sorted { $0.year > $1.year }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
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
                            LetterRow(letter: letter)
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
    }
}

// MARK: - Letter Row

private struct LetterRow: View {
    let letter: Letter

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
                Text(letter.title)
                    .font(.headline)
                    .lineLimit(1)

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
            Image(systemName: resource.isActive ? "doc.text" : "archivebox")
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
