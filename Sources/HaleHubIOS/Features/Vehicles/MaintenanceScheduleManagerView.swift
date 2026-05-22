import SwiftUI

// MARK: - Schedule Manager

struct MaintenanceScheduleManagerView: View {
    @EnvironmentObject var auth: AuthManager
    let vehicle: Vehicle

    @State private var schedules: [MaintenanceSchedule] = []
    @State private var categories: [MaintenanceCategory] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showAddSheet = false
    @State private var editingSchedule: MaintenanceSchedule? = nil
    @State private var deleteConfirmSchedule: MaintenanceSchedule? = nil

    var dueSchedules: [MaintenanceSchedule] { schedules.filter(\.isDue) }
    var upcomingSchedules: [MaintenanceSchedule] { schedules.filter { !$0.isDue } }

    var body: some View {
        Group {
            if isLoading && schedules.isEmpty {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if schedules.isEmpty {
                ContentUnavailableView {
                    Label("No Schedules", systemImage: "wrench.and.screwdriver")
                } description: {
                    Text("Add maintenance items to track service intervals.")
                } actions: {
                    Button("Add Schedule") { showAddSheet = true }
                        .buttonStyle(.bordered)
                }
            } else {
                List {
                    if !dueSchedules.isEmpty {
                        Section {
                            ForEach(dueSchedules) { schedule in
                                ScheduleRow(schedule: schedule, vehicle: vehicle)
                                    .contentShape(Rectangle())
                                    .onTapGesture { editingSchedule = schedule }
                                    .swipeActions(edge: .trailing) {
                                        Button("Delete", role: .destructive) {
                                            deleteConfirmSchedule = schedule
                                        }
                                    }
                            }
                        } header: {
                            Label("Due Now", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }

                    if !upcomingSchedules.isEmpty {
                        Section("Upcoming") {
                            ForEach(upcomingSchedules) { schedule in
                                ScheduleRow(schedule: schedule, vehicle: vehicle)
                                    .contentShape(Rectangle())
                                    .onTapGesture { editingSchedule = schedule }
                                    .swipeActions(edge: .trailing) {
                                        Button("Delete", role: .destructive) {
                                            deleteConfirmSchedule = schedule
                                        }
                                    }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Maintenance Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .refreshable { await load() }
        .task {
            await loadCategories()
            await load()
        }
        .sheet(isPresented: $showAddSheet, onDismiss: { Task { await load() } }) {
            AddEditScheduleSheet(vehicle: vehicle, schedule: nil, categories: categories)
                .environmentObject(auth)
        }
        .sheet(item: $editingSchedule, onDismiss: { Task { await load() } }) { s in
            AddEditScheduleSheet(vehicle: vehicle, schedule: s, categories: categories)
                .environmentObject(auth)
        }
        .confirmationDialog(
            "Delete \(deleteConfirmSchedule?.categoryName ?? "this schedule")?",
            isPresented: Binding(get: { deleteConfirmSchedule != nil }, set: { if !$0 { deleteConfirmSchedule = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let s = deleteConfirmSchedule { Task { await delete(s) } }
            }
            Button("Cancel", role: .cancel) { deleteConfirmSchedule = nil }
        } message: {
            Text("This cannot be undone.")
        }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func loadCategories() async {
        guard let token = auth.accessToken else { return }
        categories = (try? await APIClient.shared.get("/vehicles/maintenance-categories/", token: token)) ?? []
    }

    private func load() async {
        guard let token = auth.accessToken else { return }
        isLoading = true
        do {
            let response: PaginatedResponse<MaintenanceSchedule> = try await APIClient.shared.get(
                "/vehicles/\(vehicle.id)/maintenance/", token: token
            )
            schedules = response.results
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func delete(_ schedule: MaintenanceSchedule) async {
        guard let token = auth.accessToken else { return }
        do {
            try await APIClient.shared.delete("/vehicles/maintenance/\(schedule.id)/", token: token)
            schedules.removeAll { $0.id == schedule.id }
        } catch {
            errorMessage = error.localizedDescription
        }
        deleteConfirmSchedule = nil
    }
}

// MARK: - Schedule Row

private struct ScheduleRow: View {
    let schedule: MaintenanceSchedule
    let vehicle: Vehicle

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(schedule.categoryName ?? "Unknown")
                    .font(.body.weight(.medium))
                Spacer()
                if schedule.isDue {
                    Text("DUE")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.orange, in: Capsule())
                } else if let snoozed = schedule.snoozedUntil {
                    Text("Snoozed until \(snoozed.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                if let m = schedule.intervalMiles {
                    Label("Every \(m.formatted()) \(vehicle.unitAbbrev)", systemImage: "gauge.with.dots.needle.67percent")
                }
                if let h = schedule.intervalHours {
                    Label("Every \(h) hrs", systemImage: "clock")
                }
                if let d = schedule.intervalDays {
                    Label("Every \(d) days", systemImage: "calendar")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let last = schedule.lastPerformed {
                Text("Last: \(last.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Add / Edit Sheet

struct AddEditScheduleSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    let vehicle: Vehicle
    let schedule: MaintenanceSchedule?
    let categories: [MaintenanceCategory]

    @State private var selectedCategoryId: Int?
    @State private var intervalMilesText = ""
    @State private var intervalHoursText = ""
    @State private var intervalDaysText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var isEditing: Bool { schedule != nil }
    private var title: String { isEditing ? "Edit Schedule" : "Add Schedule" }

    private var selectedCategory: MaintenanceCategory? {
        categories.first { $0.id == selectedCategoryId }
    }

    var body: some View {
        NavigationStack {
            Form {
                if !isEditing {
                    Section("Service Type") {
                        if categories.isEmpty {
                            Text("Loading categories…").foregroundStyle(.secondary)
                        } else {
                            Picker("Category", selection: $selectedCategoryId) {
                                Text("Select…").tag(Optional<Int>.none)
                                ForEach(categories) { cat in
                                    Text(cat.name).tag(Optional(cat.id))
                                }
                            }
                        }
                    }
                } else {
                    Section("Service Type") {
                        Text(schedule?.categoryName ?? "Unknown")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    HStack {
                        Text(vehicle.unitAbbrev == "mi" ? "Every (miles)" : "Every (km)")
                        Spacer()
                        TextField("optional", text: $intervalMilesText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    HStack {
                        Text("Every (hours)")
                        Spacer()
                        TextField("optional", text: $intervalHoursText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    HStack {
                        Text("Every (days)")
                        Spacer()
                        TextField("optional", text: $intervalDaysText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                } header: {
                    Text("Intervals")
                } footer: {
                    Text("Set one or more intervals. A reminder triggers when any interval is exceeded.")
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
                        Button("Save") { Task { await save() } }
                            .disabled(!canSave)
                    }
                }
            }
        }
        .onAppear { prefill() }
    }

    private var canSave: Bool {
        let hasCategory = isEditing || selectedCategoryId != nil
        let hasInterval = !intervalMilesText.trimmingCharacters(in: .whitespaces).isEmpty
            || !intervalHoursText.trimmingCharacters(in: .whitespaces).isEmpty
            || !intervalDaysText.trimmingCharacters(in: .whitespaces).isEmpty
        return hasCategory && hasInterval
    }

    private func prefill() {
        guard let s = schedule else { return }
        selectedCategoryId = s.categoryId
        intervalMilesText = s.intervalMiles.map { String($0) } ?? ""
        intervalHoursText = s.intervalHours.map { String($0) } ?? ""
        intervalDaysText = s.intervalDays.map { String($0) } ?? ""
    }

    private func save() async {
        guard let token = auth.accessToken else { return }
        isSaving = true
        errorMessage = nil

        let miles = Int(intervalMilesText.trimmingCharacters(in: .whitespaces))
        let hours = Int(intervalHoursText.trimmingCharacters(in: .whitespaces))
        let days = Int(intervalDaysText.trimmingCharacters(in: .whitespaces))

        do {
            if let s = schedule {
                let body = MaintenanceScheduleUpdateRequest(
                    intervalMiles: miles, intervalHours: hours, intervalDays: days
                )
                let _: MaintenanceSchedule = try await APIClient.shared.patch(
                    "/vehicles/maintenance/\(s.id)/", body: body, token: token
                )
            } else {
                guard let catId = selectedCategoryId else { return }
                let body = MaintenanceScheduleCreateRequest(
                    categoryId: catId, intervalMiles: miles, intervalHours: hours, intervalDays: days
                )
                let _: MaintenanceSchedule = try await APIClient.shared.post(
                    "/vehicles/\(vehicle.id)/maintenance/", body: body, token: token
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }
}
