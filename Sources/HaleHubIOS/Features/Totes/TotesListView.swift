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
        } catch is CancellationError {
            // SwiftUI cancelled the task (e.g. view disappeared) — keep existing data, no error
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
    @State private var showCreate = false
    @State private var showQRBatch = false

    @Environment(\.horizontalSizeClass) private var hSize
    @State private var selectedToteID: String?

    /// The canonical location key for a tote — prefer the FK id, fall back to legacy slug.
    private func locationKey(for tote: Tote) -> String {
        tote.locationObjId ?? tote.locationName ?? tote.id
    }

    /// Human-readable label for a location key.
    private func locationLabel(for key: String, totes: [Tote]) -> String {
        totes.first(where: { locationKey(for: $0) == key })?.displayLocation ?? key
    }

    /// Ordered location keys (FK id or legacy slug) that have at least one tote.
    private var presentLocationKeys: [String] {
        var seen = Set<String>()
        return vm.totes.compactMap { tote -> String? in
            let key = locationKey(for: tote)
            return seen.insert(key).inserted ? key : nil
        }
    }

    /// Totes for the currently selected filter, grouped by location key.
    private var groupedTotes: [(key: String, totes: [Tote])] {
        if searchLocation == "all" {
            var groups: [(String, [Tote])] = []
            var seen = Set<String>()
            for tote in vm.totes {
                let key = locationKey(for: tote)
                if seen.insert(key).inserted {
                    groups.append((key, vm.totes.filter { locationKey(for: $0) == key }))
                }
            }
            return groups
        } else {
            let filtered = vm.totes.filter { locationKey(for: $0) == searchLocation }
            return filtered.isEmpty ? [] : [(searchLocation, filtered)]
        }
    }

    var body: some View {
        Group {
            if hSize == .regular {
                splitBody
            } else {
                stackBody
            }
        }
        .task { await vm.load(token: auth.accessToken ?? "") }
        .alert("Error", isPresented: .constant(vm.error != nil && !vm.totes.isEmpty)) {
            Button("OK") { vm.error = nil }
        } message: { Text(vm.error ?? "") }
        .sheet(isPresented: $showScanner) {
            ToteScannerSheet { tote in scannedTote = tote }
                .environmentObject(auth)
        }
        .sheet(isPresented: $showCreate) {
            CreateToteSheet(qrIdentifier: nil) { newTote in
                vm.totes.insert(newTote, at: 0)
                if hSize == .regular { selectedToteID = newTote.id }
            }
            .environmentObject(auth)
        }
        .sheet(isPresented: $showQRBatch) {
            QRBatchSheet().environmentObject(auth)
        }
        .onChange(of: scannedTote?.id) { _, newID in
            // On iPad, route a scanned tote into the detail pane instead of pushing.
            if hSize == .regular, let id = newID {
                selectedToteID = id
                scannedTote = nil
            }
        }
    }

    // MARK: iPhone — push stack

    private var stackBody: some View {
        totesContent(selectable: false)
            .navigationTitle("Totes")
            .toolbar { toteToolbar }
            .navigationDestination(item: $scannedTote) { tote in
                ToteDetailView(toteId: tote.id, toteName: tote.name)
            }
    }

    // MARK: iPad — split view

    private var splitBody: some View {
        NavigationSplitView {
            totesContent(selectable: true)
                .navigationTitle("Totes")
                .toolbar { toteToolbar }
        } detail: {
            NavigationStack {
                if let id = selectedToteID, let tote = vm.totes.first(where: { $0.id == id }) {
                    ToteDetailView(toteId: tote.id, toteName: tote.name).id(tote.id)
                } else {
                    ContentUnavailableView(
                        "Select a Tote",
                        systemImage: "shippingbox",
                        description: Text("Pick a tote to see its contents.")
                    )
                }
            }
        }
    }

    // MARK: Shared content

    @ViewBuilder
    private func totesContent(selectable: Bool) -> some View {
        if vm.isLoading && vm.totes.isEmpty {
            ProgressView("Loading totes…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMsg = vm.error, vm.totes.isEmpty {
            ContentUnavailableView {
                Label("Couldn't Load Totes", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMsg)
            } actions: {
                Button("Retry") { Task { await vm.load(token: auth.accessToken ?? "") } }
                    .buttonStyle(.borderedProminent)
            }
        } else if vm.totes.isEmpty {
            ContentUnavailableView {
                Label("No Totes", systemImage: "shippingbox")
            } description: {
                Text("Tap the + button in the top right to add your first tote.")
            } actions: {
                Button { showCreate = true } label: {
                    Label("New Tote", systemImage: "shippingbox.badge.plus")
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            VStack(spacing: 0) {
                countHeader
                chipsBar
                if selectable {
                    List(selection: $selectedToteID) {
                        ForEach(groupedTotes, id: \.key) { group in
                            Section {
                                ForEach(group.totes) { tote in
                                    ToteRow(tote: tote).tag(tote.id)
                                }
                            } header: { groupHeader(group) }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { await vm.load(token: auth.accessToken ?? "") }
                } else {
                    List {
                        ForEach(groupedTotes, id: \.key) { group in
                            Section {
                                ForEach(group.totes) { tote in
                                    NavigationLink {
                                        ToteDetailView(toteId: tote.id, toteName: tote.name)
                                    } label: {
                                        ToteRow(tote: tote)
                                    }
                                }
                            } header: { groupHeader(group) }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { await vm.load(token: auth.accessToken ?? "") }
                }
            }
        }
    }

    // Grand total across all locations (matches the web's count)
    private var countHeader: some View {
        HStack {
            Text("\(vm.totes.count) tote\(vm.totes.count == 1 ? "" : "s")")
                .font(.subheadline.weight(.semibold))
            if presentLocationKeys.count > 1 {
                Text("· \(presentLocationKeys.count) locations")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var chipsBar: some View {
        if presentLocationKeys.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    LocationFilterChip(label: "All", isSelected: searchLocation == "all") {
                        searchLocation = "all"
                    }
                    ForEach(presentLocationKeys, id: \.self) { key in
                        LocationFilterChip(
                            label: locationLabel(for: key, totes: vm.totes),
                            isSelected: searchLocation == key
                        ) { searchLocation = key }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 8)
            Divider()
        }
    }

    private func groupHeader(_ group: (key: String, totes: [Tote])) -> some View {
        HStack {
            Label(
                locationLabel(for: group.key, totes: group.totes),
                systemImage: "mappin.circle"
            )
            .font(.subheadline.weight(.semibold))
            .textCase(nil)
            .foregroundStyle(.primary)
            Spacer()
            Text("\(group.totes.count) tote\(group.totes.count == 1 ? "" : "s")")
                .font(.caption)
                .textCase(nil)
                .foregroundStyle(.secondary)
        }
    }

    @ToolbarContentBuilder
    private var toteToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button { showScanner = true } label: {
                Image(systemName: "qrcode.viewfinder")
            }
            .accessibilityLabel("Scan tote QR code")
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button("New Tote", systemImage: "shippingbox.badge.plus") { showCreate = true }
                Button("Print Blank QR Codes", systemImage: "printer") { showQRBatch = true }
                Divider()
                // Escape hatch for users (e.g. totes-only) who might not have
                // access to the More/Account tab. Always reachable.
                Button(role: .destructive) {
                    auth.logout()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } label: {
                Image(systemName: "plus")
            }
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
