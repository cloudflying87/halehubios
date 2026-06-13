import SwiftUI

@MainActor
final class YNABViewModel: ObservableObject {
    @Published var status: YNABStatus?
    @Published var budgets: [YNABBudgetOption] = []
    @Published var isLoading = false
    @Published var busy = false
    @Published var error: String?
    @Published var syncMessage: String?

    func loadStatus(token authToken: String) async {
        isLoading = true
        error = nil
        do {
            status = try await APIClient.shared.get("/finance/ynab/settings/", token: authToken)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func loadBudgets(ynabToken: String, authToken: String) async -> Bool {
        busy = true
        defer { busy = false }
        do {
            struct Body: Encodable, Sendable { let token: String }
            let resp: YNABBudgetsResponse = try await APIClient.shared.post(
                "/finance/ynab/budgets/", body: Body(token: ynabToken), token: authToken
            )
            budgets = resp.budgets
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func save(ynabToken: String?, budget: YNABBudgetOption?, authToken: String) async -> Bool {
        busy = true
        defer { busy = false }
        do {
            let req = YNABSettingsRequest(
                token: ynabToken, budgetId: budget?.id, budgetName: budget?.name, syncEnabled: nil
            )
            status = try await APIClient.shared.put("/finance/ynab/settings/", body: req, token: authToken)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func setSyncEnabled(_ enabled: Bool, authToken: String) async {
        do {
            let req = YNABSettingsRequest(token: nil, budgetId: nil, budgetName: nil, syncEnabled: enabled)
            status = try await APIClient.shared.put("/finance/ynab/settings/", body: req, token: authToken)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func syncNow(authToken: String) async {
        busy = true
        defer { busy = false }
        do {
            let s: YNABSyncSummary = try await APIClient.shared.postEmpty("/finance/ynab/sync/", token: authToken)
            syncMessage = "Synced \(s.budgets.created + s.budgets.updated) budget rows and "
                + "\(s.transactions.created + s.transactions.updated) transactions "
                + "(\(s.months.joined(separator: ", ")))."
            await loadStatus(token: authToken)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct YNABSettingsView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = YNABViewModel()

    @State private var tokenInput = ""
    @State private var selectedBudgetId: String?

    private var authToken: String { auth.accessToken ?? "" }

    var body: some View {
        Form {
            if let status = vm.status, status.connected {
                connectedSection(status)
            }
            connectSection
            if vm.status?.connected == true {
                Section {
                    Toggle("Nightly auto-sync", isOn: Binding(
                        get: { vm.status?.syncEnabled ?? true },
                        set: { newVal in Task { await vm.setSyncEnabled(newVal, authToken: authToken) } }
                    ))
                }
            }
            Section {
                Text("Create a Personal Access Token in YNAB → Account Settings → Developer Settings. "
                     + "It's stored encrypted and never shown again.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("YNAB")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if vm.busy { ProgressView().padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10)) } }
        .task { await vm.loadStatus(token: authToken) }
        .alert("Error", isPresented: .init(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK") {}
        } message: { Text(vm.error ?? "") }
        .alert("Sync complete", isPresented: .init(get: { vm.syncMessage != nil }, set: { if !$0 { vm.syncMessage = nil } })) {
            Button("OK") {}
        } message: { Text(vm.syncMessage ?? "") }
    }

    private func connectedSection(_ status: YNABStatus) -> some View {
        Section("Connected") {
            HStack {
                Text("Budget"); Spacer()
                Text(status.budgetName.isEmpty ? "—" : status.budgetName).foregroundStyle(.secondary)
            }
            if let last = status.lastSyncedAt {
                HStack {
                    Text("Last sync"); Spacer()
                    Text(LoanFormatters.fullDate(String(last.prefix(10)))).foregroundStyle(.secondary)
                }
            }
            if !status.lastSyncStatus.isEmpty {
                Text(status.lastSyncStatus).font(.caption).foregroundStyle(.secondary)
            }
            Button {
                Task { await vm.syncNow(authToken: authToken) }
            } label: {
                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(vm.busy)
        }
    }

    private var connectSection: some View {
        Section(vm.status?.connected == true ? "Reconnect / Change Budget" : "Connect YNAB") {
            SecureField("Personal Access Token", text: $tokenInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Load Budgets") {
                Task {
                    if await vm.loadBudgets(ynabToken: tokenInput, authToken: authToken),
                       let first = vm.budgets.first {
                        selectedBudgetId = first.id
                    }
                }
            }
            .disabled(tokenInput.isEmpty || vm.busy)

            if !vm.budgets.isEmpty {
                Picker("Budget", selection: $selectedBudgetId) {
                    Text("Select…").tag(String?.none)
                    ForEach(vm.budgets) { Text($0.name).tag(String?.some($0.id)) }
                }
                Button("Save Connection") {
                    let budget = vm.budgets.first { $0.id == selectedBudgetId }
                    Task {
                        if await vm.save(ynabToken: tokenInput, budget: budget, authToken: authToken) {
                            tokenInput = ""
                            vm.budgets = []
                        }
                    }
                }
                .disabled(selectedBudgetId == nil || vm.busy)
            }
        }
    }
}
