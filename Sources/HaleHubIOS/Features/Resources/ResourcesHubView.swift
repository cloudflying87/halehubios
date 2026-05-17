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
}

// MARK: - Hub View

struct ResourcesHubView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = ResourcesHubViewModel()

    var body: some View {
        Group {
            if vm.isLoading && vm.resources.isEmpty && vm.letters.isEmpty {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if let errorMessage = vm.error {
                        Section {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                                .font(.callout)
                        }
                    }

                    // MARK: Family Letters Section
                    if !vm.letters.isEmpty {
                        Section {
                            ForEach(vm.letters) { letter in
                                NavigationLink(
                                    destination: LetterDetailView(letter: letter)
                                        .environmentObject(auth)
                                ) {
                                    LetterRow(letter: letter)
                                }
                            }
                        } header: {
                            Label("Family Letters", systemImage: "envelope.open.fill")
                        }
                    }

                    // MARK: Resources Section
                    if !vm.resources.isEmpty {
                        Section {
                            ForEach(vm.resources) { resource in
                                NavigationLink(
                                    destination: ResourceDetailView(resource: resource)
                                        .environmentObject(auth)
                                ) {
                                    ResourceRow(resource: resource)
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
        .navigationTitle("Resources & Letters")
        .navigationBarTitleDisplayMode(.large)
        .task { await vm.load(token: auth.accessToken ?? "") }
    }
}

// MARK: - Letter Row

private struct LetterRow: View {
    let letter: Letter

    var body: some View {
        HStack(spacing: 12) {
            // Year badge
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
                        Label("\(letter.photoCount) photo\(letter.photoCount == 1 ? "" : "s")",
                              systemImage: "photo.on.rectangle")
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
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Resource Row

private struct ResourceRow: View {
    let resource: Resource

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(resource.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if resource.isPublic {
                    Image(systemName: "globe")
                        .font(.caption)
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
        .padding(.vertical, 4)
    }
}
