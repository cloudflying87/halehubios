import SwiftUI

// MARK: - Shared helpers

enum LoanType: String, CaseIterable, Identifiable {
    case mortgage, auto, personal, student
    case creditCard = "credit_card"
    case business, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .mortgage: return "Mortgage"
        case .auto: return "Auto Loan"
        case .personal: return "Personal Loan"
        case .student: return "Student Loan"
        case .creditCard: return "Credit Card"
        case .business: return "Business Loan"
        case .other: return "Other"
        }
    }
}

enum LoanFormatters {
    static let currency: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 2
        return f
    }()

    static func money(_ value: Double, fractionDigits: Int = 2) -> String {
        currency.maximumFractionDigits = fractionDigits
        return currency.string(from: NSNumber(value: value)) ?? "$\(value)"
    }

    /// "2030-06-01" → "Jun 2030"
    static func monthYear(_ ymd: String?) -> String {
        guard let ymd else { return "—" }
        let inF = DateFormatter()
        inF.locale = Locale(identifier: "en_US_POSIX")
        inF.dateFormat = "yyyy-MM-dd"
        guard let d = inF.date(from: ymd) else { return ymd }
        let out = DateFormatter()
        out.dateFormat = "MMM yyyy"
        return out.string(from: d)
    }

    /// "2025-02-01" → "Feb 1, 2025"
    static func fullDate(_ ymd: String) -> String {
        let inF = DateFormatter()
        inF.locale = Locale(identifier: "en_US_POSIX")
        inF.dateFormat = "yyyy-MM-dd"
        guard let d = inF.date(from: ymd) else { return ymd }
        let out = DateFormatter()
        out.dateStyle = .medium
        return out.string(from: d)
    }

    static func ymd(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func parseYMD(_ ymd: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: ymd)
    }
}

// MARK: - View Models

@MainActor
final class LoansViewModel: ObservableObject {
    @Published var loans: [FinanceLoan] = []
    @Published var isLoading = false
    @Published var error: String?

    func load(token: String) async {
        isLoading = true
        error = nil
        do {
            loans = try await APIClient.shared.get("/finance/loans/", token: token)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func create(_ req: LoanRequest, token: String) async -> Bool {
        do {
            let _: LoanDetail = try await APIClient.shared.post("/finance/loans/", body: req, token: token)
            await load(token: token)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}

@MainActor
final class LoanDetailViewModel: ObservableObject {
    @Published var loan: LoanDetail?
    @Published var isLoading = false
    @Published var saving = false
    @Published var error: String?

    func load(id: Int, token: String) async {
        isLoading = true
        error = nil
        do {
            loan = try await APIClient.shared.get("/finance/loans/\(id)/", token: token)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func recordPayment(id: Int, req: PaymentRequest, token: String) async -> Bool {
        saving = true
        defer { saving = false }
        do {
            let resp: PaymentResponse = try await APIClient.shared.post("/finance/loans/\(id)/payments/", body: req, token: token)
            loan = resp.loan
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func update(id: Int, req: LoanRequest, token: String) async -> Bool {
        saving = true
        defer { saving = false }
        do {
            loan = try await APIClient.shared.patch("/finance/loans/\(id)/", body: req, token: token)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func delete(id: Int, token: String) async -> Bool {
        do {
            try await APIClient.shared.delete("/finance/loans/\(id)/", token: token)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func addCheckpoint(loanId: Int, req: LoanCheckpointRequest, token: String) async -> Bool {
        saving = true
        defer { saving = false }
        do {
            let _: LoanCheckpoint = try await APIClient.shared.post(
                "/finance/loans/\(loanId)/checkpoints/", body: req, token: token
            )
            await load(id: loanId, token: token)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func deleteCheckpoint(loanId: Int, checkpointId: Int, token: String) async {
        do {
            try await APIClient.shared.delete(
                "/finance/loans/\(loanId)/checkpoints/\(checkpointId)/", token: token
            )
            await load(id: loanId, token: token)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Loans List

struct FinanceLoansView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = LoansViewModel()
    @State private var showAdd = false

    var body: some View {
        Group {
            if vm.isLoading && vm.loans.isEmpty {
                ProgressView("Loading…").frame(maxWidth: .infinity, minHeight: 200)
            } else if vm.loans.isEmpty {
                ContentUnavailableView("No Loans", systemImage: "creditcard", description: Text("Tap + to add a loan."))
            } else {
                List {
                    ForEach(vm.loans) { loan in
                        NavigationLink(destination: LoanDetailView(loanId: loan.id)) {
                            LoanRowContent(loan: loan)
                        }
                    }
                }
            }
        }
        .navigationTitle("Loans")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) {
            LoanFormSheet(existing: nil) { req in
                await vm.create(req, token: auth.accessToken ?? "")
            }
        }
        .task { await vm.load(token: auth.accessToken ?? "") }
        .refreshable { await vm.load(token: auth.accessToken ?? "") }
        .alert("Error", isPresented: .init(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK") {}
        } message: { Text(vm.error ?? "") }
    }
}

struct LoanRowContent: View {
    let loan: FinanceLoan
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(loan.name).font(.subheadline).fontWeight(.medium)
                    Text(loan.loanType.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(LoanFormatters.money(loan.currentBalance, fractionDigits: 0))
                        .font(.subheadline).fontWeight(.semibold)
                    Text("\(String(format: "%.2f", loan.interestRate))% · \(LoanFormatters.money(loan.monthlyPayment, fractionDigits: 0))/mo")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ProgressView(value: max(0, min(1, loan.progressPct / 100.0))).tint(.blue)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Loan Detail

struct LoanDetailView: View {
    let loanId: Int
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = LoanDetailViewModel()
    @State private var showEdit = false
    @State private var showPayment = false
    @State private var showAmortization = false
    @State private var confirmDelete = false
    @State private var showAddCheckpoint = false

    var body: some View {
        Group {
            if let loan = vm.loan {
                content(loan)
            } else if vm.isLoading {
                ProgressView("Loading…").frame(maxWidth: .infinity, minHeight: 200)
            } else {
                ContentUnavailableView("Couldn’t load loan", systemImage: "exclamationmark.triangle",
                                       description: Text(vm.error ?? "Try again."))
            }
        }
        .navigationTitle(vm.loan?.name ?? "Loan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if vm.loan != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showEdit = true } label: { Label("Edit", systemImage: "pencil") }
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Archive Loan", systemImage: "archivebox") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            if let loan = vm.loan {
                LoanFormSheet(existing: loan) { req in
                    await vm.update(id: loanId, req: req, token: auth.accessToken ?? "")
                }
            }
        }
        .sheet(isPresented: $showPayment) {
            RecordPaymentSheet(suggestedAmount: vm.loan?.monthlyPayment ?? 0, saving: vm.saving) { req in
                await vm.recordPayment(id: loanId, req: req, token: auth.accessToken ?? "")
            }
        }
        .alert("Archive this loan?", isPresented: $confirmDelete) {
            Button("Archive", role: .destructive) {
                Task {
                    if await vm.delete(id: loanId, token: auth.accessToken ?? "") { dismiss() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("It will be removed from your active loans. Payment history is kept.") }
        .alert("Error", isPresented: .init(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK") {}
        } message: { Text(vm.error ?? "") }
        .task { await vm.load(id: loanId, token: auth.accessToken ?? "") }
        .refreshable { await vm.load(id: loanId, token: auth.accessToken ?? "") }
    }

    private func content(_ loan: LoanDetail) -> some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                balanceCard(loan)
                detailsGrid(loan)
                Button { showPayment = true } label: {
                    Label("Record Payment", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 2)

                amortizationCard(loan)
                if let payments = loan.payments, !payments.isEmpty {
                    paymentsCard(payments)
                }
                checkpointsCard(loan)
                if loan.matchedTransactions != nil {
                    matchedTransactionsCard(loan)
                }
            }
            .padding(16)
        }
        .sheet(isPresented: $showAddCheckpoint) {
            AddCheckpointSheet(saving: vm.saving) { req in
                await vm.addCheckpoint(loanId: loanId, req: req, token: auth.accessToken ?? "")
            }
        }
    }

    private func balanceCard(_ loan: LoanDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Current Balance").font(.subheadline).foregroundStyle(.secondary)
            Text(LoanFormatters.money(loan.currentBalance))
                .font(.system(size: 32, weight: .bold, design: .rounded))
            ProgressView(value: max(0, min(1, loan.progressPct / 100.0))).tint(.blue)
            HStack {
                Text("\(String(format: "%.1f", loan.progressPct))% paid off")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("of \(LoanFormatters.money(loan.principalAmount, fractionDigits: 0))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func detailsGrid(_ loan: LoanDetail) -> some View {
        VStack(spacing: 0) {
            statRow("Type", loan.loanType.replacingOccurrences(of: "_", with: " ").capitalized)
            Divider()
            statRow("Interest Rate", "\(String(format: "%.3f", loan.interestRate))%")
            Divider()
            statRow("P&I Payment", LoanFormatters.money(loan.monthlyPayment))
            if loan.loanType == "mortgage", let total = loan.totalMonthlyHousingCost, total > loan.monthlyPayment {
                if let pmi = loan.effectivePmi, pmi > 0 {
                    Divider()
                    statRow("PMI", LoanFormatters.money(pmi))
                }
                if let escrow = loan.effectiveEscrow, escrow > 0 {
                    Divider()
                    statRow("Taxes & Insurance", LoanFormatters.money(escrow))
                }
                Divider()
                HStack {
                    Text("Total (PITI)").font(.subheadline).fontWeight(.semibold)
                    Spacer()
                    Text(LoanFormatters.money(total)).font(.subheadline).fontWeight(.semibold)
                }
                .padding(.vertical, 12)
            }
            Divider()
            statRow("Payoff Date", LoanFormatters.monthYear(loan.payoffDate))
            if let rem = loan.remainingPayments {
                Divider()
                statRow("Payments Left", rem >= 9999 ? "—" : "\(rem)")
            }
            if let interest = loan.totalInterest {
                Divider()
                statRow("Total Interest", LoanFormatters.money(interest))
            }
            Divider()
            statRow("Start Date", LoanFormatters.fullDate(loan.startDate))
        }
        .padding(.horizontal, 16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline).fontWeight(.medium)
        }
        .padding(.vertical, 12)
    }

    private func amortizationCard(_ loan: LoanDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { showAmortization.toggle() } label: {
                HStack {
                    Text("Amortization Schedule").font(.headline).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: showAmortization ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if showAmortization, let rows = loan.amortization {
                HStack {
                    Text("#").frame(width: 28, alignment: .leading)
                    Text("Principal").frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Interest").frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Balance").frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.caption2).foregroundStyle(.secondary)
                ForEach(rows) { row in
                    HStack {
                        Text("\(row.paymentNumber)").frame(width: 28, alignment: .leading)
                        Text(LoanFormatters.money(row.principalPayment, fractionDigits: 0)).frame(maxWidth: .infinity, alignment: .trailing)
                        Text(LoanFormatters.money(row.interestPayment, fractionDigits: 0)).frame(maxWidth: .infinity, alignment: .trailing)
                        Text(LoanFormatters.money(row.endingBalance, fractionDigits: 0)).frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.caption)
                }
                Text("Next \(rows.count) payments").font(.caption2).foregroundStyle(.tertiary).padding(.top, 2)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func paymentsCard(_ payments: [LoanPayment]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Payment History").font(.headline)
            ForEach(payments) { p in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LoanFormatters.fullDate(p.paymentDate)).font(.subheadline).fontWeight(.medium)
                        Text("P: \(LoanFormatters.money(p.principalPortion, fractionDigits: 0)) · I: \(LoanFormatters.money(p.interestPortion, fractionDigits: 0))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(LoanFormatters.money(p.amount)).font(.subheadline).fontWeight(.semibold)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func checkpointsCard(_ loan: LoanDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Balance Checkpoints").font(.headline)
                Spacer()
                Button { showAddCheckpoint = true } label: {
                    Image(systemName: "plus.circle").foregroundStyle(.blue)
                }
            }
            Text("Anchors the YNAB backfill to a verified statement balance.")
                .font(.caption).foregroundStyle(.secondary)
            if let checkpoints = loan.checkpoints, !checkpoints.isEmpty {
                ForEach(checkpoints) { cp in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LoanFormatters.fullDate(cp.checkpointDate))
                                .font(.subheadline).fontWeight(.medium)
                            if !cp.notes.isEmpty {
                                Text(cp.notes).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(LoanFormatters.money(cp.balance)).font(.subheadline).fontWeight(.semibold)
                        Button {
                            Task {
                                await vm.deleteCheckpoint(loanId: loanId, checkpointId: cp.id, token: auth.accessToken ?? "")
                            }
                        } label: {
                            Image(systemName: "trash").foregroundStyle(.red).font(.caption)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 8)
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Text("No checkpoints yet.")
                    .font(.subheadline).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    private func matchedTransactionsCard(_ loan: LoanDetail) -> some View {
        let transactions = loan.matchedTransactions ?? []
        let importedCount = transactions.filter { $0.imported }.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("YNAB Transactions").font(.headline)
                Spacer()
                if !transactions.isEmpty {
                    Text("\(transactions.count) matched · \(importedCount) imported")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if transactions.isEmpty {
                Text("No matching transactions found. Check your YNAB filter settings.")
                    .font(.subheadline).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ForEach(transactions) { tx in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(tx.imported ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tx.payee).font(.subheadline).fontWeight(.medium)
                                .lineLimit(1)
                            Text(tx.account).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(LoanFormatters.money(tx.amount)).font(.subheadline).fontWeight(.semibold)
                            Text(LoanFormatters.fullDate(tx.date)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Add Checkpoint Sheet

struct AddCheckpointSheet: View {
    let saving: Bool
    let onSave: (LoanCheckpointRequest) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var balance: Double = 0
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Checkpoint") {
                    DatePicker("Statement Date", selection: $date, displayedComponents: .date)
                    HStack {
                        Text("Verified Balance")
                        Spacer()
                        TextField("0.00", value: $balance, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    TextField("Notes (e.g. March statement)", text: $notes)
                }
                Section {
                    Text("After saving, run the backfill command on the server to reconstruct payment history from this checkpoint.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Checkpoint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            let req = LoanCheckpointRequest(
                                checkpointDate: LoanFormatters.ymd(date),
                                balance: balance,
                                notes: notes
                            )
                            if await onSave(req) { dismiss() }
                        }
                    }
                    .disabled(saving || balance <= 0)
                }
            }
        }
    }
}

// MARK: - Record Payment Sheet

struct RecordPaymentSheet: View {
    let suggestedAmount: Double
    let saving: Bool
    let onSave: (PaymentRequest) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var amount: Double
    @State private var date = Date()
    @State private var method = "online"

    private let methods: [(String, String)] = [
        ("online", "Online"), ("auto", "Automatic"), ("check", "Check"),
        ("cash", "Cash"), ("money_order", "Money Order"), ("other", "Other"),
    ]

    init(suggestedAmount: Double, saving: Bool, onSave: @escaping (PaymentRequest) async -> Bool) {
        self.suggestedAmount = suggestedAmount
        self.saving = saving
        self.onSave = onSave
        _amount = State(initialValue: suggestedAmount)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Payment") {
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("Amount", value: $amount, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Method", selection: $method) {
                        ForEach(methods, id: \.0) { Text($0.1).tag($0.0) }
                    }
                }
                Section {
                    Text("Principal and interest are split automatically from your current balance and rate.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Record Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            let req = PaymentRequest(amount: amount, paymentDate: LoanFormatters.ymd(date), paymentMethod: method, notes: nil)
                            if await onSave(req) { dismiss() }
                        }
                    }
                    .disabled(saving || amount <= 0)
                }
            }
        }
    }
}

// MARK: - Add / Edit Sheet

struct LoanFormSheet: View {
    let existing: LoanDetail?
    let onSave: (LoanRequest) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var loanType: LoanType = .other
    @State private var principal: Double = 0
    @State private var balance: Double = 0
    @State private var useBalance = false
    @State private var rate: Double = 0
    @State private var termMonths = 360
    @State private var monthlyPayment: Double = 0
    @State private var startDate = Date()
    @State private var isInvestment = false
    @State private var ynabCategory = ""
    @State private var saving = false

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && principal > 0 && rate > 0 && termMonths >= 1 && monthlyPayment > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Loan") {
                    TextField("Name (e.g. Home Mortgage)", text: $name)
                    Picker("Type", selection: $loanType) {
                        ForEach(LoanType.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section("Amounts") {
                    currencyField("Principal", value: $principal)
                    Toggle("Different current balance", isOn: $useBalance)
                    if useBalance {
                        currencyField("Current Balance", value: $balance)
                    }
                    currencyField("Monthly Payment", value: $monthlyPayment)
                }
                Section("Terms") {
                    HStack {
                        Text("Interest Rate")
                        Spacer()
                        TextField("APR", value: $rate, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        Text("%").foregroundStyle(.secondary)
                    }
                    Stepper("Term: \(termMonths) months", value: $termMonths, in: 1...600)
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                }
                Section {
                    Toggle("Investment loan", isOn: $isInvestment)
                    Text("Investment loans are excluded from net-worth liabilities.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Auto-record payments") {
                    TextField("YNAB category (e.g. Mortgage Payment)", text: $ynabCategory)
                    Text("Transactions in this YNAB category are recorded as payments and lower the balance on each sync.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(existing == nil ? "Add Loan" : "Edit Loan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            saving = true
                            let req = LoanRequest(
                                name: name, loanType: loanType.rawValue,
                                principalAmount: principal,
                                currentBalance: useBalance ? balance : nil,
                                interestRate: rate, termMonths: termMonths,
                                monthlyPayment: monthlyPayment,
                                startDate: LoanFormatters.ymd(startDate),
                                isActive: true, isInvestment: isInvestment,
                                ynabCategory: ynabCategory.trimmingCharacters(in: .whitespaces)
                            )
                            let ok = await onSave(req)
                            saving = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(!isValid || saving)
                }
            }
            .onAppear { populate() }
        }
    }

    private func currencyField(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(label, value: value, format: .currency(code: "USD"))
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
        }
    }

    private func populate() {
        guard let loan = existing else { return }
        name = loan.name
        loanType = LoanType(rawValue: loan.loanType) ?? .other
        principal = loan.principalAmount
        balance = loan.currentBalance
        useBalance = abs(loan.currentBalance - loan.principalAmount) > 0.001
        rate = loan.interestRate
        termMonths = loan.termMonths
        monthlyPayment = loan.monthlyPayment
        isInvestment = loan.isInvestment
        ynabCategory = loan.ynabCategory ?? ""
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        if let d = f.date(from: loan.startDate) { startDate = d }
    }
}
