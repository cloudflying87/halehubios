import SwiftUI

struct MaintenanceHistoryView: View {
    @EnvironmentObject var auth: AuthManager

    /// When provided, filters results to this vehicle's events only.
    var vehicle: Vehicle? = nil

    @State private var events: [VehicleEvent] = []
    @State private var categories: [MaintenanceCategory] = []
    @State private var searchText = ""
    @State private var selectedCategoryId: Int? = nil
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search history…", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await loadEvents() } }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        Task { await loadEvents() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Category filter chips
            if !categories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(label: "All", isSelected: selectedCategoryId == nil) {
                            selectedCategoryId = nil
                            Task { await loadEvents() }
                        }
                        ForEach(categories) { cat in
                            FilterChip(label: cat.name, isSelected: selectedCategoryId == cat.id) {
                                selectedCategoryId = (selectedCategoryId == cat.id) ? nil : cat.id
                                Task { await loadEvents() }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 8)
            }

            Divider()

            if isLoading && events.isEmpty {
                Spacer()
                ProgressView("Loading…")
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                ContentUnavailableView("Error", systemImage: "exclamationmark.circle", description: Text(error))
                Spacer()
            } else if events.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "No Results",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different search or filter.")
                )
                Spacer()
            } else {
                List(events) { event in
                    HistoryEventRow(event: event)
                }
                .listStyle(.plain)
                .refreshable { await loadEvents() }
            }
        }
        .navigationTitle(vehicle != nil ? "Service History" : "Maintenance History")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadCategories()
            await loadEvents()
        }
    }

    private func loadCategories() async {
        guard let token = auth.accessToken else { return }
        categories = (try? await APIClient.shared.get(
            "/vehicles/maintenance-categories/", token: token
        )) ?? []
    }

    private func loadEvents() async {
        guard let token = auth.accessToken else { return }
        isLoading = true
        errorMessage = nil

        var queryItems: [URLQueryItem] = []
        if !searchText.isEmpty { queryItems.append(URLQueryItem(name: "search", value: searchText)) }
        if let catId = selectedCategoryId { queryItems.append(URLQueryItem(name: "category_id", value: String(catId))) }
        if let v = vehicle { queryItems.append(URLQueryItem(name: "vehicle_id", value: String(v.id))) }

        var path = "/vehicles/maintenance-history/"
        if !queryItems.isEmpty {
            var comps = URLComponents()
            comps.queryItems = queryItems
            path += "?" + (comps.percentEncodedQuery ?? "")
        }

        do {
            let response: PaginatedResponse<VehicleEvent> = try await APIClient.shared.get(path, token: token)
            events = response.results
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - History Event Row

struct HistoryEventRow: View {
    let event: VehicleEvent

    var accentColor: Color {
        switch event.eventType {
        case "gas": return .blue
        case "maintenance": return .orange
        case "outing": return .green
        default: return .secondary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.eventIcon)
                .font(.subheadline)
                .foregroundStyle(accentColor)
                .frame(width: 28, height: 28)
                .background(accentColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(rowTitle).font(.subheadline.weight(.medium))
                    Spacer()
                    Text(event.date, style: .date).font(.caption).foregroundStyle(.secondary)
                }
                if let items = event.maintenanceItems, !items.isEmpty {
                    ForEach(items) { item in
                        HStack {
                            Text(item.categoryName ?? "Service")
                            if !item.description.isEmpty {
                                Text("· \(item.description)").foregroundStyle(.secondary)
                            }
                            Spacer()
                            if item.cost > 0 {
                                Text(String(format: "$%.2f", item.cost))
                            }
                        }
                        .font(.caption)
                    }
                } else if let notes = event.notes, !notes.isEmpty {
                    Text(notes).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                if let cost = event.totalCost, cost > 0 {
                    Text(String(format: "Total: $%.2f", cost))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    var rowTitle: String {
        switch event.eventType {
        case "gas": return "Gas Fill-up"
        case "maintenance": return event.maintenanceCategoryName ?? "Service"
        case "outing": return event.locationName ?? "Outing"
        default: return event.eventType.capitalized
        }
    }
}
