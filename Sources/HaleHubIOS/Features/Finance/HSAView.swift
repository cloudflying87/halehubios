import SwiftUI

@MainActor
final class HSAViewModel: ObservableObject {
    @Published var accounts: [HSAAccount] = []
    @Published var isLoading = false
    @Published var error: String?

    func load(token: String) async {
        isLoading = true; error = nil
        do { accounts = try await APIClient.shared.get("/finance/hsa/", token: token) }
        catch { self.error = error.localizedDescription }
        isLoading = false
    }

    func add(_ req: HSARequest, token: String) async -> Bool {
        do {
            let _: HSAAccount = try await APIClient.shared.post("/finance/hsa/", body: req, token: token)
            await load(token: token); return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func update(id: Int, req: HSARequest, token: String) async -> Bool {
        do {
            let _: HSAAccount = try await APIClient.shared.patch("/finance/hsa/\(id)/", body: req, token: token)
            await load(token: token); return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func delete(_ h: HSAAccount, token: String) async {
        do { try await APIClient.shared.delete("/finance/hsa/\(h.id)/", token: token); await load(token: token) }
        catch { self.error = error.localizedDescription }
    }

    var totalBalance: Double { accounts.reduce(0) { $0 + $1.currentBalance } }
    var totalRoom: Double { accounts.reduce(0) { $0 + $1.remainingRoom } }
}

let hsaCoverageTypes: [(String, String)] = [("self_only", "Self-only"), ("family", "Family")]

struct HSAView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = HSAViewModel()
    @State private var showAdd = false
    @State private var editing: HSAAccount?
    private var token: String { auth.accessToken ?? "" }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                totalsCard
                if vm.accounts.isEmpty && !vm.isLoading {
                    ContentUnavailableView("No HSA Accounts", systemImage: "cross.case.fill",
                        description: Text("Tap + to add an HSA. The account number is encrypted."))
                    .frame(minHeight: 140)
                } else {
                    ForEach(vm.accounts) { h in
                        Button { editing = h } label: { row(h) }.buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("HSA")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showAdd) {
            HSAFormSheet(title: "Add HSA") { req in await vm.add(req, token: token) }
        }
        .sheet(item: $editing) { h in
            HSAFormSheet(title: "Edit HSA", existing: h) { req in
                await vm.update(id: h.id, req: req, token: token)
            } onDelete: { await vm.delete(h, token: token) }
        }
        .task { await vm.load(token: token) }
        .refreshable { await vm.load(token: token) }
        .alert("Error", isPresented: .init(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK") {}
        } message: { Text(vm.error ?? "") }
    }

    private var totalsCard: some View {
        HStack {
            VStack(spacing: 2) {
                Text("Balance").font(.caption2).foregroundStyle(.secondary)
                Text(LoanFormatters.money(vm.totalBalance, fractionDigits: 0)).font(.headline).foregroundStyle(.green)
            }.frame(maxWidth: .infinity)
            Divider()
            VStack(spacing: 2) {
                Text("Contribution Room").font(.caption2).foregroundStyle(.secondary)
                Text(LoanFormatters.money(vm.totalRoom, fractionDigits: 0)).font(.headline).foregroundStyle(.blue)
            }.frame(maxWidth: .infinity)
        }
        .padding(16).background(Color(.secondarySystemGroupedBackground)).clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func row(_ h: HSAAccount) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(h.provider).font(.subheadline).fontWeight(.semibold)
                Spacer()
                Text(LoanFormatters.money(h.currentBalance, fractionDigits: 0)).font(.subheadline).fontWeight(.semibold).foregroundStyle(.green)
            }
            HStack {
                Text("\(coverageLabel(h.coverageType)) · \(h.accountHolder)").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if h.contributionLimit > 0 {
                    Text("\(LoanFormatters.money(h.remainingRoom, fractionDigits: 0)) room").font(.caption2).foregroundStyle(.blue)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func coverageLabel(_ t: String) -> String { hsaCoverageTypes.first { $0.0 == t }?.1 ?? t }
}

struct HSAFormSheet: View {
    let title: String
    var existing: HSAAccount?
    let onSave: (HSARequest) async -> Bool
    var onDelete: (() async -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var provider = ""
    @State private var holder = ""
    @State private var accountNumber = ""
    @State private var coverage = "family"
    @State private var balance: Double = 0
    @State private var invested: Double = 0
    @State private var ytd: Double = 0
    @State private var employerYtd: Double = 0
    @State private var limit: Double = 0
    @State private var notes = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Provider (e.g. Fidelity HSA)", text: $provider)
                    TextField("Account holder", text: $holder)
                    Picker("Coverage", selection: $coverage) { ForEach(hsaCoverageTypes, id: \.0) { Text($0.1).tag($0.0) } }
                    TextField("Account number (optional)", text: $accountNumber)
                }
                Section("Balance") {
                    money("Current balance", $balance)
                    money("Invested portion", $invested)
                }
                Section("Contributions") {
                    money("Annual limit (IRS)", $limit)
                    money("Your YTD", $ytd)
                    money("Employer YTD", $employerYtd)
                }
                Section("Notes") { TextField("Notes (optional)", text: $notes) }
                if existing != nil, let onDelete {
                    Section {
                        Button(role: .destructive) { Task { await onDelete(); dismiss() } } label: {
                            Text("Delete HSA").frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") {
                        Task {
                            saving = true
                            let ok = await onSave(HSARequest(
                                provider: provider, accountHolder: holder,
                                accountNumber: accountNumber.isEmpty ? nil : accountNumber,
                                coverageType: coverage, currentBalance: balance, investedBalance: invested,
                                ytdContribution: ytd, ytdEmployerContribution: employerYtd,
                                contributionLimit: limit, notes: notes.isEmpty ? nil : notes
                            ))
                            saving = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(saving || provider.trimmingCharacters(in: .whitespaces).isEmpty || holder.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let e = existing {
                    provider = e.provider; holder = e.accountHolder; accountNumber = e.accountNumber
                    coverage = e.coverageType; balance = e.currentBalance; invested = e.investedBalance
                    ytd = e.ytdContribution; employerYtd = e.ytdEmployerContribution; limit = e.contributionLimit; notes = e.notes
                }
            }
        }
    }

    private func money(_ label: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("$").foregroundStyle(.secondary)
            TextField("0", value: value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
        }
    }
}
