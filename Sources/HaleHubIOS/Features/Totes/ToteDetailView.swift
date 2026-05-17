import SwiftUI

// MARK: - ViewModel

@MainActor
class ToteDetailViewModel: ObservableObject {
    @Published var toteDetail: ToteDetail?
    @Published var categories: [ToteCategory] = []
    @Published var isLoading = false
    @Published var error: String?

    func load(id: String, token: String) async {
        isLoading = true
        error = nil

        // Fetch tote detail and categories in parallel.
        async let detailFetch: ToteDetail = APIClient.shared.get("/totes/\(id)/", token: token)
        async let categoriesFetch: [ToteCategory] = APIClient.shared.get("/totes/categories/", token: token)

        do {
            let (detail, cats) = try await (detailFetch, categoriesFetch)
            toteDetail = detail
            categories = cats
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func deleteItem(itemId: String, token: String) async {
        do {
            try await APIClient.shared.delete("/tote-items/\(itemId)/", token: token)
            // Remove from local state immediately (optimistic).
            if let detail = toteDetail {
                toteDetail = ToteDetail(
                    id: detail.id,
                    name: detail.name,
                    location: detail.location,
                    locationNotes: detail.locationNotes,
                    itemCount: detail.itemCount - 1,
                    dateSorted: detail.dateSorted,
                    qrCodeIdentifier: detail.qrCodeIdentifier,
                    notes: detail.notes,
                    items: detail.items.filter { $0.id != itemId }
                )
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Items grouped by category name, preserving insertion order.
    var itemsByCategory: [(categoryName: String, items: [ToteItem])] {
        guard let detail = toteDetail else { return [] }
        var groups: [(String, [ToteItem])] = []
        var seen = Set<String>()
        for item in detail.items {
            if seen.insert(item.categoryName).inserted {
                groups.append((item.categoryName, detail.items.filter { $0.categoryName == item.categoryName }))
            }
        }
        return groups
    }
}

// MARK: - Main detail view

struct ToteDetailView: View {
    @EnvironmentObject var auth: AuthManager
    let toteId: String
    let toteName: String

    @StateObject private var vm = ToteDetailViewModel()
    @State private var showAddItem = false

    var body: some View {
        Group {
            if vm.isLoading && vm.toteDetail == nil {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail = vm.toteDetail {
                toteContent(detail: detail)
            } else if let errorMsg = vm.error {
                ContentUnavailableView {
                    Label("Couldn't Load Tote", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMsg)
                } actions: {
                    Button("Retry") {
                        Task { await vm.load(id: toteId, token: auth.accessToken ?? "") }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle(toteName)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddItem = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(vm.categories.isEmpty)
            }
        }
        .sheet(isPresented: $showAddItem) {
            AddToteItemSheet(
                isPresented: $showAddItem,
                toteId: toteId,
                categories: vm.categories
            ) { newItem in
                // Append the new item and bump count.
                if let detail = vm.toteDetail {
                    vm.toteDetail = ToteDetail(
                        id: detail.id,
                        name: detail.name,
                        location: detail.location,
                        locationNotes: detail.locationNotes,
                        itemCount: detail.itemCount + 1,
                        dateSorted: detail.dateSorted,
                        qrCodeIdentifier: detail.qrCodeIdentifier,
                        notes: detail.notes,
                        items: detail.items + [newItem]
                    )
                }
            }
            .environmentObject(auth)
        }
        .task { await vm.load(id: toteId, token: auth.accessToken ?? "") }
        .refreshable { await vm.load(id: toteId, token: auth.accessToken ?? "") }
        .alert("Error", isPresented: .constant(vm.error != nil && vm.toteDetail != nil)) {
            Button("OK") { vm.error = nil }
        } message: { Text(vm.error ?? "") }
    }

    @ViewBuilder
    private func toteContent(detail: ToteDetail) -> some View {
        List {
            // Location chip header
            Section {
                HStack(spacing: 8) {
                    Image(systemName: detail.locationIcon)
                        .foregroundStyle(Color.accentColor)
                    Text(detail.locationLabel)
                        .font(.subheadline.weight(.medium))
                    if !detail.locationNotes.isEmpty {
                        Text("· \(detail.locationNotes)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let qr = detail.qrCodeIdentifier {
                        Label(qr, systemImage: "qrcode")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Items grouped by category
            if vm.itemsByCategory.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No items yet",
                        systemImage: "shippingbox",
                        description: Text("Tap + to add some!")
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                ForEach(vm.itemsByCategory, id: \.categoryName) { group in
                    Section(group.categoryName) {
                        ForEach(group.items) { item in
                            ToteItemRow(item: item)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        Task {
                                            await vm.deleteItem(
                                                itemId: item.id,
                                                token: auth.accessToken ?? ""
                                            )
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - ToteItemRow

struct ToteItemRow: View {
    let item: ToteItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.itemTypeName)
                .font(.body)

            HStack(spacing: 12) {
                if !item.quantity.isEmpty {
                    Label(item.quantity, systemImage: "number")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !item.notes.isEmpty {
                    Text(item.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - ToteDetail location helpers (mirror Tote extension)

private extension ToteDetail {
    var locationLabel: String { Tote.locationLabel(for: location) }
    var locationIcon: String {
        switch location {
        case "basement":        return "stairs"
        case "attic":           return "house.lodge"
        case "garage":          return "car.garage.door"
        case "storage_unit":    return "building.2"
        case "bedroom_closet":  return "door.sliding.right.hand.closed"
        case "guest_room":      return "bed.double"
        case "shed":            return "leaf"
        default:                return "shippingbox"
        }
    }
}
