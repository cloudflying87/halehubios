import SwiftUI

// MARK: - Archive Hub

struct ArchiveHubView: View {
    @EnvironmentObject var auth: AuthManager

    enum Tab: String, CaseIterable { case resources = "Resources", letters = "Letters" }
    @State private var tab: Tab = .resources

    @State private var archivedResources: [Resource] = []
    @State private var archivedLetters: [Letter] = []
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding()

            Group {
                if isLoading {
                    ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    ContentUnavailableView {
                        Label("Couldn't Load", systemImage: "exclamationmark.triangle")
                    } description: { Text(error) } actions: {
                        Button("Retry") { Task { await load() } }.buttonStyle(.bordered)
                    }
                } else {
                    switch tab {
                    case .resources: resourcesList
                    case .letters: lettersList
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Archive")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Resources list

    private var resourcesList: some View {
        Group {
            if archivedResources.isEmpty {
                ContentUnavailableView(
                    "No Archived Resources",
                    systemImage: "archivebox",
                    description: Text("Archived resources will appear here.")
                )
            } else {
                List {
                    ForEach(archivedResources) { resource in
                        NavigationLink(destination: ResourceDetailView(resource: resource).environmentObject(auth)) {
                            ArchivedResourceRow(resource: resource)
                        }
                        .swipeActions(edge: .trailing) {
                            if resource.canEdit {
                                Button("Restore") {
                                    Task { await restoreResource(resource) }
                                }
                                .tint(.green)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    // MARK: Letters list

    private var lettersList: some View {
        Group {
            if archivedLetters.isEmpty {
                ContentUnavailableView(
                    "No Archived Letters",
                    systemImage: "archivebox",
                    description: Text("Archived letters will appear here.")
                )
            } else {
                List {
                    ForEach(archivedLetters) { letter in
                        NavigationLink(destination: LetterDetailView(letter: letter).environmentObject(auth)) {
                            ArchivedLetterRow(letter: letter)
                        }
                        .swipeActions(edge: .trailing) {
                            if letter.canEdit {
                                Button("Restore") {
                                    Task { await restoreLetter(letter) }
                                }
                                .tint(.green)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    // MARK: Data

    private func load() async {
        guard let token = auth.accessToken else { return }
        isLoading = true
        error = nil
        async let resourcesTask: [Resource] = APIClient.shared.get("/resources/?archived_only=1", token: token)
        async let lettersTask: [Letter] = APIClient.shared.get("/letters/?archived_only=1", token: token)
        do {
            let (r, l) = try await (resourcesTask, lettersTask)
            archivedResources = r
            archivedLetters = l
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func restoreResource(_ resource: Resource) async {
        guard let token = auth.accessToken else { return }
        let body = ResourceArchiveRequest(archived: false)
        let _: ResourceDetail? = try? await APIClient.shared.post(
            "/resources/\(resource.slug)/archive/", body: body, token: token
        )
        archivedResources.removeAll { $0.id == resource.id }
    }

    private func restoreLetter(_ letter: Letter) async {
        guard let token = auth.accessToken else { return }
        struct Req: Encodable { let archived: Bool }
        let _: LetterDetail? = try? await APIClient.shared.post(
            "/letters/\(letter.slug)/archive/", body: Req(archived: false), token: token
        )
        archivedLetters.removeAll { $0.id == letter.id }
    }
}

// MARK: - Rows

private struct ArchivedResourceRow: View {
    let resource: Resource
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: resource.isReact ? "safari" : "doc.text")
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(resource.title).font(.body)
                if !resource.description.isEmpty {
                    Text(resource.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if resource.canEdit {
                Text("Swipe to restore")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ArchivedLetterRow: View {
    let letter: Letter
    var body: some View {
        HStack(spacing: 12) {
            Text(String(letter.year))
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.secondary, in: RoundedRectangle(cornerRadius: 8))
                .fixedSize()
            VStack(alignment: .leading, spacing: 3) {
                Text(letter.title).font(.body).lineLimit(1)
                if let eventDate = letter.eventDate {
                    Text(formattedDate(eventDate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if letter.canEdit {
                Text("Swipe to restore")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func formattedDate(_ s: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: s) else { return s }
        f.dateStyle = .medium; return f.string(from: d)
    }
}
