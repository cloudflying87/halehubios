import SwiftUI

@MainActor
final class InvestmentsViewModel: ObservableObject {
    @Published var investments: [InvestmentHolding] = []
    @Published var brokerageAccounts: [BrokerageAccountSummary] = []
    @Published var isLoading = false
    @Published var error: String?

    func load(token: String) async {
        isLoading = true
        error = nil
        async let inv: [InvestmentHolding] = APIClient.shared.get("/finance/investments/", token: token)
        async let brok: [BrokerageAccountSummary] = APIClient.shared.get("/finance/brokerage/", token: token)
        do {
            (investments, brokerageAccounts) = try await (inv, brok)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func add(_ req: InvestmentRequest, token: String) async -> Bool {
        do {
            let _: InvestmentHolding = try await APIClient.shared.post("/finance/investments/", body: req, token: token)
            await load(token: token)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func update(id: Int, req: InvestmentRequest, token: String) async -> Bool {
        do {
            let _: InvestmentHolding = try await APIClient.shared.patch("/finance/investments/\(id)/", body: req, token: token)
            await load(token: token)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func delete(_ inv: InvestmentHolding, token: String) async {
        do {
            try await APIClient.shared.delete("/finance/investments/\(inv.id)/", token: token)
            await load(token: token)
        } catch {
            self.error = error.localizedDescription
        }
    }

    var brokerageTotal: Double { brokerageAccounts.compactMap(\.latestBalance).reduce(0, +) }
    var manualTotal: Double { investments.filter { $0.isActive }.reduce(0) { $0 + $1.currentValue } }
    var grandTotal: Double { brokerageTotal + manualTotal }
}

let investmentTypes: [(String, String)] = [
    ("stocks", "Stocks"), ("bonds", "Bonds"), ("mutual_funds", "Mutual Funds"),
    ("etf", "ETF"), ("real_estate", "Real Estate"), ("crypto", "Crypto"),
    ("commodities", "Commodities"), ("cd", "CD"), ("savings", "Savings"), ("other", "Other"),
]

struct InvestmentsView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = InvestmentsViewModel()
    @State private var showAdd = false
    @State private var editing: InvestmentHolding?

    private var token: String { auth.accessToken ?? "" }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                totalCard
                if !vm.brokerageAccounts.isEmpty {
                    brokerageSection
                }
                manualSection
            }
            .padding(16)
        }
        .navigationTitle("Investments")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) {
            InvestmentFormSheet(title: "Add Investment") { req in await vm.add(req, token: token) }
        }
        .sheet(item: $editing) { inv in
            InvestmentFormSheet(title: "Edit Investment", existing: inv) { req in
                await vm.update(id: inv.id, req: req, token: token)
            } onDelete: {
                await vm.delete(inv, token: token)
            }
        }
        .task { await vm.load(token: token) }
        .refreshable { await vm.load(token: token) }
        .alert("Error", isPresented: .init(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK") {}
        } message: { Text(vm.error ?? "") }
    }

    private var totalCard: some View {
        VStack(spacing: 4) {
            Text("Total Portfolio").font(.caption).foregroundStyle(.secondary)
            Text(LoanFormatters.money(vm.grandTotal, fractionDigits: 0))
                .font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(.green)
            if vm.brokerageTotal > 0 && vm.manualTotal > 0 {
                HStack(spacing: 12) {
                    Label(LoanFormatters.money(vm.brokerageTotal, fractionDigits: 0), systemImage: "building.columns")
                        .font(.caption2).foregroundStyle(.secondary)
                    Label(LoanFormatters.money(vm.manualTotal, fractionDigits: 0), systemImage: "list.bullet")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(18).frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var brokerageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Brokerage Accounts", systemImage: "building.columns")
                    .font(.subheadline).fontWeight(.semibold)
                Spacer()
                Text(LoanFormatters.money(vm.brokerageTotal, fractionDigits: 0))
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(.green)
            }
            .padding(.horizontal, 4)

            ForEach(vm.brokerageAccounts) { account in
                brokerageRow(account)
            }

            Text("Import CSVs from the web to update balances.")
                .font(.caption2).foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
        }
    }

    private func brokerageRow(_ account: BrokerageAccountSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name).font(.subheadline).fontWeight(.medium)
                    Text([account.institution, accountTypeLabel(account.accountType)]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if let bal = account.latestBalance {
                        Text(LoanFormatters.money(bal, fractionDigits: 0))
                            .font(.subheadline).fontWeight(.semibold)
                    } else {
                        Text("No data").font(.caption).foregroundStyle(.tertiary)
                    }
                    if let d = account.latestImportDate {
                        Text(d, style: .date).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }

            if !account.topHoldings.isEmpty {
                VStack(spacing: 4) {
                    ForEach(account.topHoldings, id: \.description) { h in
                        HStack {
                            Text(h.description).font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1f%%", h.percentOfAccount))
                                .font(.caption2).foregroundStyle(.tertiary)
                            Text(LoanFormatters.money(h.currentValue, fractionDigits: 0))
                                .font(.caption2).fontWeight(.medium)
                        }
                    }
                }
                .padding(8)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var manualSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !vm.brokerageAccounts.isEmpty {
                HStack {
                    Label("Manual Holdings", systemImage: "list.bullet")
                        .font(.subheadline).fontWeight(.semibold)
                    Spacer()
                    if vm.manualTotal > 0 {
                        Text(LoanFormatters.money(vm.manualTotal, fractionDigits: 0))
                            .font(.subheadline).fontWeight(.semibold).foregroundStyle(.green)
                    }
                }
                .padding(.horizontal, 4)
            }

            if vm.investments.isEmpty && !vm.isLoading {
                ContentUnavailableView(
                    "No Manual Investments",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Tap + to add an investment. Retirement is tracked separately.")
                )
                .frame(minHeight: 120)
            } else {
                ForEach(vm.investments) { inv in
                    Button { editing = inv } label: { manualRow(inv) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func manualRow(_ inv: InvestmentHolding) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(inv.name).font(.subheadline).fontWeight(.medium)
                Text("\(typeLabel(inv.investmentType))\(inv.symbol.isEmpty ? "" : " · \(inv.symbol)")")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(LoanFormatters.money(inv.currentValue, fractionDigits: 0)).font(.subheadline).fontWeight(.semibold)
                if inv.gainLoss != 0 {
                    Text("\(inv.gainLoss >= 0 ? "+" : "")\(LoanFormatters.money(inv.gainLoss, fractionDigits: 0))")
                        .font(.caption2).foregroundStyle(inv.gainLoss >= 0 ? .green : .red)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func typeLabel(_ t: String) -> String {
        investmentTypes.first { $0.0 == t }?.1 ?? t
    }

    private func accountTypeLabel(_ t: String) -> String {
        switch t {
        case "brokerage": return "Brokerage"
        case "ira": return "IRA"
        case "roth_ira": return "Roth IRA"
        case "401k": return "401(k)"
        case "hsa": return "HSA"
        default: return t
        }
    }
}

struct InvestmentFormSheet: View {
    let title: String
    var existing: InvestmentHolding?
    let onSave: (InvestmentRequest) async -> Bool
    var onDelete: (() async -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type = "stocks"
    @State private var symbol = ""
    @State private var value: Double = 0
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Apple)", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(investmentTypes, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    TextField("Symbol (optional)", text: $symbol)
                        .textInputAutocapitalization(.characters)
                    HStack {
                        Text("Current value")
                        Spacer()
                        Text("$").foregroundStyle(.secondary)
                        TextField("0", value: $value, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                }
                if existing != nil, let onDelete {
                    Section {
                        Button(role: .destructive) {
                            Task { await onDelete(); dismiss() }
                        } label: { Text("Delete Investment").frame(maxWidth: .infinity) }
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
                            let ok = await onSave(InvestmentRequest(
                                name: name, investmentType: type,
                                symbol: symbol.isEmpty ? nil : symbol,
                                currentValue: value, purchaseDate: nil
                            ))
                            saving = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty || value <= 0)
                }
            }
            .onAppear {
                if let e = existing {
                    name = e.name; type = e.investmentType; symbol = e.symbol; value = e.currentValue
                }
            }
        }
    }
}
