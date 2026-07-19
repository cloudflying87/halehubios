import SwiftUI

// MARK: - Manage Maintenance Categories

struct ManageMaintenanceCategoriesView: View {
    @EnvironmentObject var auth: AuthManager

    @State private var categories: [MaintenanceCategory] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showInactive = false
    @State private var showAddSheet = false
    @State private var editingCategory: MaintenanceCategory? = nil

    private var visibleCategories: [MaintenanceCategory] {
        let sorted = categories.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return showInactive ? sorted : sorted.filter { $0.isActive != false }
    }

    var body: some View {
        Group {
            if isLoading && categories.isEmpty {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        ForEach(visibleCategories) { category in
                            CategoryRow(category: category)
                                .contentShape(Rectangle())
                                .onTapGesture { editingCategory = category }
                                .swipeActions(edge: .trailing) {
                                    if category.isActive == false {
                                        Button("Reactivate") { Task { await setActive(category, active: true) } }
                                            .tint(.green)
                                    } else {
                                        Button("Deactivate", role: .destructive) {
                                            Task { await setActive(category, active: false) }
                                        }
                                    }
                                }
                        }
                    } footer: {
                        Text("Deactivating a category hides it from pickers but keeps existing schedules and history intact.")
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Maintenance Types")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Toggle("Show Inactive", isOn: $showInactive)
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $showAddSheet, onDismiss: { Task { await load() } }) {
            AddEditCategorySheet(category: nil)
                .environmentObject(auth)
        }
        .sheet(item: $editingCategory, onDismiss: { Task { await load() } }) { c in
            AddEditCategorySheet(category: c)
                .environmentObject(auth)
        }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func load() async {
        guard let token = auth.accessToken else { return }
        isLoading = true
        do {
            categories = try await APIClient.shared.get(
                "/vehicles/maintenance-categories/?include_inactive=1", token: token
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func setActive(_ category: MaintenanceCategory, active: Bool) async {
        guard let token = auth.accessToken else { return }
        do {
            if active {
                let _: MaintenanceCategory = try await APIClient.shared.patch(
                    "/vehicles/maintenance-categories/\(category.id)/",
                    body: SetCategoryActiveRequest(isActive: true), token: token
                )
            } else {
                try await APIClient.shared.delete(
                    "/vehicles/maintenance-categories/\(category.id)/", token: token
                )
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Category Row

private struct CategoryRow: View {
    let category: MaintenanceCategory

    private var vehicleTypeLabel: String {
        guard let types = category.vehicleTypes, !types.isEmpty else { return "All vehicle types" }
        let allTypes: Set<String> = ["car", "boat", "motorcycle", "rv", "other"]
        if Set(types) == allTypes { return "All vehicle types" }
        return types.map { $0.capitalized }.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(category.name).font(.body.weight(.medium))
                if category.isActive == false {
                    Text("Inactive")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(.systemGray5), in: Capsule())
                }
            }
            Text(vehicleTypeLabel).font(.caption).foregroundStyle(.secondary)
            if let desc = category.description, !desc.isEmpty {
                Text(desc).font(.caption).foregroundStyle(.tertiary).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
        .opacity(category.isActive == false ? 0.6 : 1)
    }
}

// MARK: - Add / Edit Category Sheet

private struct AddEditCategorySheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    let category: MaintenanceCategory?

    private static let vehicleTypeOptions = [
        ("car", "Car"), ("boat", "Boat"), ("motorcycle", "Motorcycle"),
        ("rv", "RV"), ("other", "Other"),
    ]
    private static let boatEngineOptions = [
        ("inboard", "Inboard"), ("outboard", "Outboard"), ("io", "Inboard/Outboard (I/O)"),
    ]

    @State private var name = ""
    @State private var description = ""
    @State private var selectedVehicleTypes: Set<String> = []
    @State private var selectedBoatEngineTypes: Set<String> = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var isEditing: Bool { category != nil }
    private var title: String { isEditing ? "Edit Maintenance Type" : "New Maintenance Type" }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Drive Shaft", text: $name)
                    TextField("Description (optional)", text: $description)
                }

                Section {
                    ForEach(Self.vehicleTypeOptions, id: \.0) { value, label in
                        Toggle(label, isOn: Binding(
                            get: { selectedVehicleTypes.contains(value) },
                            set: { on in
                                if on { selectedVehicleTypes.insert(value) }
                                else { selectedVehicleTypes.remove(value) }
                            }
                        ))
                    }
                } header: {
                    Text("Applies To")
                } footer: {
                    Text("Leave all unchecked to apply to every vehicle type.")
                }

                if selectedVehicleTypes.contains("boat") {
                    Section {
                        ForEach(Self.boatEngineOptions, id: \.0) { value, label in
                            Toggle(label, isOn: Binding(
                                get: { selectedBoatEngineTypes.contains(value) },
                                set: { on in
                                    if on { selectedBoatEngineTypes.insert(value) }
                                    else { selectedBoatEngineTypes.remove(value) }
                                }
                            ))
                        }
                    } header: {
                        Text("Boat Engine Types")
                    } footer: {
                        Text("Leave all unchecked to apply to every boat engine type.")
                    }
                }

                if let err = errorMessage {
                    Section {
                        Text(err).foregroundStyle(.red).font(.callout)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }.disabled(!canSave)
                    }
                }
            }
        }
        .onAppear { prefill() }
    }

    private func prefill() {
        guard let c = category else { return }
        name = c.name
        description = c.description ?? ""
        selectedVehicleTypes = Set(c.vehicleTypes ?? [])
        selectedBoatEngineTypes = Set(c.boatEngineTypes ?? [])
    }

    private func save() async {
        guard let token = auth.accessToken else { return }
        isSaving = true
        errorMessage = nil

        let vehicleTypes = selectedVehicleTypes.isEmpty
            ? Self.vehicleTypeOptions.map(\.0)
            : Array(selectedVehicleTypes)
        let body = UpdateMaintenanceCategoryRequest(
            name: name.trimmingCharacters(in: .whitespaces),
            description: description.trimmingCharacters(in: .whitespaces),
            vehicleTypes: vehicleTypes,
            boatEngineTypes: Array(selectedBoatEngineTypes)
        )

        do {
            if let c = category {
                let _: MaintenanceCategory = try await APIClient.shared.patch(
                    "/vehicles/maintenance-categories/\(c.id)/", body: body, token: token
                )
            } else {
                let _: MaintenanceCategory = try await APIClient.shared.post(
                    "/vehicles/maintenance-categories/", body: body, token: token
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }
}
