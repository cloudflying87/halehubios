import SwiftUI

@MainActor
final class InvestmentsViewModel: ObservableObject {
    @Published var investments: [InvestmentHolding] = []
    @Published var isLoading = false
    @Published var error: String?

    func load(token: String) async {
        isLoading = true
        error = nil
        do {
            investments = try await APIClient.shared.get("/finance/investments/", token: token)
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

    var total: Double { investments.filter { $0.isActive }.reduce(0) { $0 + $1.currentValue } }
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
                if vm.investments.isEmpty && !vm.isLoading {
                    ContentUnavailableView(
                        "No Investments",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Tap + to add an investment. Retirement is tracked separately.")
                    )
                    .frame(minHeight: 140)
                } else {
                    ForEach(vm.investments) { inv in
                        Button { editing = inv } label: { row(inv) }
                            .buttonStyle(.plain)
                    }
                }
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
            Text("Total Investments").font(.caption).foregroundStyle(.secondary)
            Text(LoanFormatters.money(vm.total, fractionDigits: 0))
                .font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(.green)
            Text("Non-retirement holdings").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(18).frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func row(_ inv: InvestmentHolding) -> some View {
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
