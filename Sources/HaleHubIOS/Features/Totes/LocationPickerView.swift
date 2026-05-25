import SwiftUI

/// Reusable location picker for tote create/edit forms.
///
/// Fetches the family's ToteLocation list from GET /api/totes/locations/
/// and binds `selectionId` to the chosen location's UUID. If the parent
/// has a legacy slug from an existing tote (no FK assigned yet), pass it
/// as `legacySlug` and the picker will preselect the matching ToteLocation
/// once the list loads.
struct LocationPickerView: View {
    @EnvironmentObject var auth: AuthManager

    @Binding var selectionId: String?
    var legacySlug: String? = nil

    @State private var locations: [ToteLocation] = []
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        Group {
            if isLoading && locations.isEmpty {
                HStack {
                    ProgressView().scaleEffect(0.8)
                    Text("Loading locations…")
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                }
            } else if let err = loadError, locations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Couldn't load locations").font(.subheadline)
                    Text(err).font(.caption).foregroundStyle(.red)
                    Button("Retry") { Task { await load() } }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            } else if locations.isEmpty {
                Text("No locations yet — add one on the web at Manage → Locations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Location", selection: $selectionId) {
                    Text("— Pick a location —").tag(Optional<String>.none)
                    ForEach(locations) { loc in
                        Text(loc.name).tag(Optional(loc.id))
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        loadError = nil
        do {
            let fetched: [ToteLocation] = try await APIClient.shared.get(
                "/totes/locations/", token: auth.accessToken ?? ""
            )
            locations = fetched.sorted { ($0.order, $0.name) < ($1.order, $1.name) }

            // If parent gave us a legacy slug (existing tote with no FK yet),
            // auto-select the matching ToteLocation row so the form looks
            // pre-populated instead of "— Pick a location —".
            if selectionId == nil, let slug = legacySlug,
               let match = locations.first(where: { $0.slug == slug }) {
                selectionId = match.id
            }
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
