import SwiftUI

// MARK: - ViewModel

@MainActor
class TotesViewModel: ObservableObject {
    @Published var totes: [Tote] = []
    @Published var isLoading = false
    @Published var error: String?

    func load(token: String) async {
        isLoading = true
        error = nil
        do {
            let fetched: [Tote] = try await APIClient.shared.get("/totes/", token: token)
            totes = fetched
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Main list view

struct TotesListView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = TotesViewModel()
    @State private var searchLocation: String = "all"
    @State private var showScanner = false
    @State private var scannedTote: Tote? = nil

    // Ordered location slugs that have at least one tote.
    private var presentLocations: [String] {
        let slugs = totes(for: "all").map(\.location)
        // Preserve stable order: deduplicate while keeping first-seen order.
        var seen = Set<String>()
        return slugs.filter { seen.insert($0).inserted }
    }

    /// Totes visible under the current location filter.
    private func totes(for location: String) -> [Tote] {
        location == "all" ? vm.totes : vm.totes.filter { $0.location == location }
    }

    /// Totes for the currently selected filter, grouped by location slug → [Tote].
    private var groupedTotes: [(location: String, totes: [Tote])] {
        if searchLocation == "all" {
            // Group by every location that appears.
            var groups: [(String, [Tote])] = []
            var seen = Set<String>()
            for tote in vm.totes {
                if seen.insert(tote.location).inserted {
                    groups.append((tote.location, vm.totes.filter { $0.location == tote.location }))
                }
            }
            return groups
        } else {
            let filtered = vm.totes.filter { $0.location == searchLocation }
            return filtered.isEmpty ? [] : [(searchLocation, filtered)]
        }
    }

    var body: some View {
        Group {
            if vm.isLoading && vm.totes.isEmpty {
                ProgressView("Loading totes…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMsg = vm.error, vm.totes.isEmpty {
                ContentUnavailableView {
                    Label("Couldn't Load Totes", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMsg)
                } actions: {
                    Button("Retry") {
                        Task { await vm.load(token: auth.accessToken ?? "") }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if vm.totes.isEmpty {
                ContentUnavailableView(
                    "No Totes",
                    systemImage: "shippingbox",
                    description: Text("Add storage totes on the website.")
                )
            } else {
                VStack(spacing: 0) {
                    // Location filter chips
                    if presentLocations.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                LocationFilterChip(
                                    label: "All",
                                    isSelected: searchLocation == "all"
                                ) { searchLocation = "all" }

                                ForEach(presentLocations, id: \.self) { slug in
                                    LocationFilterChip(
                                        label: Tote.locationLabel(for: slug),
                                        isSelected: searchLocation == slug
                                    ) { searchLocation = slug }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .padding(.vertical, 8)
                        Divider()
                    }

                    List {
                        ForEach(groupedTotes, id: \.location) { group in
                            Section {
                                ForEach(group.totes) { tote in
                                    NavigationLink {
                                        ToteDetailView(toteId: tote.id, toteName: tote.name)
                                    } label: {
                                        ToteRow(tote: tote)
                                    }
                                }
                            } header: {
                                Label(
                                    Tote.locationLabel(for: group.location),
                                    systemImage: group.totes.first?.locationIcon ?? "shippingbox"
                                )
                                .font(.subheadline.weight(.semibold))
                                .textCase(nil)
                                .foregroundStyle(.primary)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { await vm.load(token: auth.accessToken ?? "") }
                }
            }
        }
        .navigationTitle("Totes")
        .task { await vm.load(token: auth.accessToken ?? "") }
        .alert("Error", isPresented: .constant(vm.error != nil && !vm.totes.isEmpty)) {
            Button("OK") { vm.error = nil }
        } message: { Text(vm.error ?? "") }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showScanner = true
                } label: {
                    Image(systemName: "qrcode.viewfinder")
                }
                .accessibilityLabel("Scan tote QR code")
            }
        }
        .sheet(isPresented: $showScanner) {
            ToteScannerSheet { tote in
                scannedTote = tote
            }
            .environmentObject(auth)
        }
        .navigationDestination(item: $scannedTote) { tote in
            ToteDetailView(toteId: tote.id, toteName: tote.name)
        }
    }
}

// MARK: - Subviews

struct ToteRow: View {
    let tote: Tote

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(tote.name)
                    .font(.headline)

                if !tote.locationNotes.isEmpty {
                    Text(tote.locationNotes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(tote.itemCount)")
                    .font(.title3.bold())
                    .foregroundStyle(tote.itemCount > 0 ? Color.accentColor : .secondary)
                Text(tote.itemCount == 1 ? "item" : "items")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct LocationFilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.systemGray5),
                            in: Capsule())
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
