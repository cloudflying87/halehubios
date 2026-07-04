import SwiftUI

@MainActor
final class ChoresViewModel: ObservableObject {
    @Published var dashboard: ChoreDashboard?
    @Published var manageChores: [ChoreManage] = []
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var error: String?

    private var token = ""
    func configure(token: String) { self.token = token }

    func load() async {
        isLoading = true
        error = nil
        do {
            dashboard = try await APIClient.shared.get("/chores/dashboard/", token: token)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    /// Full chore list for the parent's manage sheet.
    func loadManage() async {
        do {
            manageChores = try await APIClient.shared.get("/chores/", token: token)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func createChore(childId: String, name: String, days: [Int]) async -> Bool {
        isSaving = true
        defer { isSaving = false }
        do {
            let _: ChoreManage = try await APIClient.shared.post(
                "/chores/",
                body: ChoreCreateRequest(childId: childId, name: name, daysOfWeek: days.sorted()),
                token: token
            )
            await loadManage()
            await load()  // refresh today's dashboard cards
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func deleteChore(id: String) async {
        do {
            try await APIClient.shared.delete("/chores/\(id)/", token: token)
            await loadManage()
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func toggle(choreId: String, date: String, done: Bool) async {
        do {
            let _: ChoreCompleteResponse = try await APIClient.shared.post(
                "/chores/\(choreId)/complete/",
                body: ChoreCompleteRequest(date: date, done: done),
                token: token
            )
            await load()  // refresh counts + summaries
        } catch {
            self.error = error.localizedDescription
            await load()
        }
    }
}

private struct ChoreCompleteResponse: Codable, Sendable {
    let choreId: String
    let date: String
    let done: Bool
}

struct ChoresView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = ChoresViewModel()
    @State private var showManage = false
    private var token: String { auth.accessToken ?? "" }
    private var isParent: Bool { auth.currentUser?.isAdult ?? false }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let dash = vm.dashboard {
                    if dash.children.isEmpty {
                        ContentUnavailableView("No Chores", systemImage: "checklist",
                                               description: Text("No chores assigned yet."))
                            .frame(minHeight: 200)
                    } else {
                        ForEach(dash.children) { child in
                            childCard(child)
                        }
                    }
                } else if vm.isLoading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(16)
        }
        .navigationTitle("Chores")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isParent {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showManage = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add or manage chores")
                }
            }
        }
        .sheet(isPresented: $showManage) {
            ManageChoresSheet(vm: vm, children: vm.dashboard?.children ?? [])
        }
        .task { vm.configure(token: token); await vm.load() }
        .refreshable { await vm.load() }
        .alert("Error", isPresented: .init(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK") {}
        } message: { Text(vm.error ?? "") }
    }

    private func childCard(_ child: ChoreChild) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(child.childName).font(.headline)
                Spacer()
                Text("\(child.week.perfectDays)/\(child.week.daysWithChores) all-done days")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if child.today.items.isEmpty {
                Text("No chores today 🎉").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(child.today.items) { item in
                    Button {
                        Task { await vm.toggle(choreId: item.choreId, date: child.today.date, done: !item.done) }
                    } label: {
                        HStack {
                            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.done ? .green : .secondary)
                            Text(item.name)
                                .strikethrough(item.done)
                                .foregroundStyle(item.done ? .secondary : .primary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                    Divider()
                }
                HStack {
                    Text("Today: \(child.today.done)/\(child.today.required)")
                        .font(.caption).foregroundStyle(child.today.allDone ? .green : .secondary)
                    Spacer()
                    Text("Week: \(child.week.totalDone)/\(child.week.totalRequired) done")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Add / manage chores (parents only)

struct ManageChoresSheet: View {
    @ObservedObject var vm: ChoresViewModel
    let children: [ChoreChild]
    @Environment(\.dismiss) private var dismiss

    @State private var childId = ""
    @State private var name = ""
    @State private var days: Set<Int> = []

    // Backend days_of_week: 0=Mon … 6=Sun. Empty = every day.
    private let weekdays: [(Int, String)] = [
        (0, "Mon"), (1, "Tue"), (2, "Wed"), (3, "Thu"), (4, "Fri"), (5, "Sat"), (6, "Sun"),
    ]

    private var canAdd: Bool {
        !childId.isEmpty && !name.trimmingCharacters(in: .whitespaces).isEmpty && !vm.isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("New chore") {
                    Picker("Child", selection: $childId) {
                        Text("Select…").tag("")
                        ForEach(children) { Text($0.childName).tag($0.childId) }
                    }
                    TextField("Chore name", text: $name)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Days (none = every day)")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            ForEach(weekdays, id: \.0) { num, label in
                                dayChip(num, label)
                            }
                        }
                    }
                    .padding(.vertical, 2)

                    Button {
                        Task {
                            let ok = await vm.createChore(
                                childId: childId,
                                name: name.trimmingCharacters(in: .whitespaces),
                                days: Array(days)
                            )
                            if ok { name = ""; days = [] }
                        }
                    } label: {
                        if vm.isSaving { ProgressView() } else { Text("Add chore") }
                    }
                    .disabled(!canAdd)
                }

                Section("Existing chores") {
                    if vm.manageChores.isEmpty {
                        Text("No chores yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(vm.manageChores) { c in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.name)
                                Text("\(c.childName) · \(c.daysLabel)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { vm.manageChores[$0].id }
                            Task { for id in ids { await vm.deleteChore(id: id) } }
                        }
                    }
                }
            }
            .navigationTitle("Manage Chores")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { await vm.loadManage() }
        }
    }

    private func dayChip(_ num: Int, _ label: String) -> some View {
        let on = days.contains(num)
        return Text(label)
            .font(.caption2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(on ? Color.accentColor : Color(.tertiarySystemFill),
                        in: RoundedRectangle(cornerRadius: 7))
            .foregroundStyle(on ? .white : .primary)
            .contentShape(Rectangle())
            .onTapGesture {
                if on { days.remove(num) } else { days.insert(num) }
            }
    }
}
