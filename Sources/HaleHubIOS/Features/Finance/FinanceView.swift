import SwiftUI
import Charts
import LocalAuthentication

struct FinanceView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = FinanceViewModel()

    @State private var isUnlocked = false
    @State private var authError: String?
    @State private var biometryType: LABiometryType = .none
    @State private var hasTriggeredAuth = false

    private let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        return f
    }()

    private let pctFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .percent
        f.maximumFractionDigits = 1
        return f
    }()

    var body: some View {
        Group {
            if isUnlocked {
                unlockedContent
            } else {
                lockScreen
            }
        }
        .navigationTitle("Finance")
        .onAppear {
            detectBiometryType()
            if !hasTriggeredAuth {
                hasTriggeredAuth = true
                authenticate()
            }
        }
        .onDisappear {
            isUnlocked = false
            hasTriggeredAuth = false
        }
        .alert("Error", isPresented: .init(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK") { }
        } message: { Text(vm.error ?? "") }
    }

    // MARK: - Lock Screen

    private var lockScreen: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                Text("Finance")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Your financial data is protected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let errMsg = authError {
                Text(errMsg)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Button(action: authenticate) {
                Label(biometryButtonLabel, systemImage: biometryIcon)
                    .frame(maxWidth: 280)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var biometryButtonLabel: String {
        switch biometryType {
        case .faceID: return "Unlock with Face ID"
        case .touchID: return "Unlock with Touch ID"
        case .opticID: return "Unlock with Optic ID"
        default: return "Unlock"
        }
    }

    private var biometryIcon: String {
        switch biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        default: return "lock.open.fill"
        }
    }

    // MARK: - Authentication

    private func detectBiometryType() {
        let ctx = LAContext()
        var error: NSError?
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        biometryType = ctx.biometryType
    }

    private func authenticate() {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            isUnlocked = true
            Task { await vm.load(token: auth.accessToken ?? "") }
            return
        }
        ctx.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Unlock your financial data"
        ) { success, evalError in
            Task { @MainActor in
                if success {
                    authError = nil
                    isUnlocked = true
                    await vm.load(token: auth.accessToken ?? "")
                } else {
                    authError = evalError?.localizedDescription ?? "Authentication failed"
                }
            }
        }
    }

    // MARK: - Unlocked Dashboard

    private var unlockedContent: some View {
        VStack(spacing: 0) {
            quickJumpBar
            ScrollView {
                if vm.isLoading && vm.summary == nil {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    LazyVStack(spacing: 16) {
                        if let s = vm.summary {
                            netWorthCard(s)
                            thisMonthSection(s.currentMonth)
                        }
                        if !vm.loans.isEmpty {
                            loansSection
                        }
                        if !vm.brokerageAccounts.isEmpty {
                            investmentsSection
                        }
                        if !vm.paychecks.isEmpty {
                            recentPaychecksSection
                        }
                        if let t = vm.trends, !t.months.isEmpty {
                            trendsSection(t)
                        }
                    }
                    .padding(16)
                }
            }
            .refreshable { await vm.load(token: auth.accessToken ?? "") }
        }
    }

    // MARK: - Quick-jump bar

    /// Pinned horizontal chip bar — one tap to every finance sub-section, so the
    /// dashboard below stays a quick glance instead of a long scroll of links.
    private var quickJumpBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                jumpChip("Budget", "chart.pie.fill", AnyView(BudgetView()))
                jumpChip("Pay Hours", "clock.badge.checkmark.fill", AnyView(PayHoursView()))
                jumpChip("Family Year", "person.2.fill", AnyView(FamilyIncomeView()))
                jumpChip("Paychecks", "doc.text.fill", AnyView(PaychecksView()))
                jumpChip("Loans", "creditcard.fill", AnyView(FinanceLoansView()))
                jumpChip("Tithe", "hands.sparkles.fill", AnyView(TitheView()))
                jumpChip("Assets & Debts", "house.fill", AnyView(OtherAccountsView()))
                jumpChip("Insurance", "shield.lefthalf.filled", AnyView(LifeInsuranceView()))
                jumpChip("Monte Carlo", "dice.fill", AnyView(MonteCarloView()))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func jumpChip(_ title: String, _ icon: String, _ destination: AnyView) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.caption)
                Text(title).font(.subheadline).fontWeight(.medium)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Net Worth Card

    private func netWorthCard(_ s: FinanceSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Net Worth")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(format(s.netWorth))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(s.netWorth >= 0 ? .green : .red)
            Divider()
            HStack {
                assetPillar(label: "Cash", value: s.assetsBreakdown.cash)
                Spacer()
                NavigationLink(destination: InvestmentsView()) {
                    assetPillar(label: "Investments", value: s.assetsBreakdown.investments)
                }
                .buttonStyle(.plain)
                Spacer()
                NavigationLink(destination: RetirementDetailView()) {
                    assetPillar(label: "Retirement", value: s.assetsBreakdown.retirement)
                }
                .buttonStyle(.plain)
                if let other = s.assetsBreakdown.other, other > 0 {
                    Spacer()
                    assetPillar(label: "Other", value: other)
                }
            }
            NavigationLink(destination: OtherAccountsView()) {
                HStack {
                    Text("Assets & Debts")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func assetPillar(label: String, value: Double) -> some View {
        VStack(spacing: 4) {
            Text(formatCompact(value))
                .font(.headline)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - This Month

    private func thisMonthSection(_ m: MonthlySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This Month")
                .font(.headline)
            HStack(spacing: 12) {
                incomeCard(m)
                spendingCard(m)
            }
        }
    }

    private func incomeCard(_ m: MonthlySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Income")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fontWeight(.semibold)
            incomeRow(label: "Gross", value: m.grossIncome)
            incomeRow(label: "Taxes", value: m.taxes, isNegative: true)
            incomeRow(label: "Deductions", value: m.deductions, isNegative: true)
            Divider()
            incomeRow(label: "Net", value: m.netIncome, isBold: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func incomeRow(label: String, value: Double?, isNegative: Bool = false, isBold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(isBold ? .caption.bold() : .caption)
                .foregroundStyle(isBold ? .primary : .secondary)
            Spacer()
            if let v = value {
                Text((isNegative ? "-" : "") + formatCompact(abs(v)))
                    .font(isBold ? .caption.bold() : .caption)
                    .foregroundStyle(isNegative ? .red : (isBold ? .primary : .secondary))
            } else {
                Text("—").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private func spendingCard(_ m: MonthlySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Spending")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fontWeight(.semibold)
            spendingRow(label: "Spent", value: m.totalSpending)
            spendingRow(label: "Saved", value: m.saved, highlight: .green)
            if let rate = m.savingsRate {
                HStack {
                    Text("Rate").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(formatPct(rate))
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func spendingRow(label: String, value: Double?, highlight: Color? = nil) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            if let v = value {
                Text(formatCompact(v))
                    .font(.caption.bold())
                    .foregroundStyle(highlight ?? .primary)
            } else {
                Text("—").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Tithe

    private var titheNavCard: some View {
        NavigationLink(destination: TitheView()) {
            HStack(spacing: 12) {
                Image(systemName: "hands.sparkles.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tithe").font(.subheadline).fontWeight(.medium)
                    Text("Giving vs monthly goal").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Budget (YNAB)

    private var budgetNavCard: some View {
        NavigationLink(destination: BudgetView()) {
            HStack(spacing: 12) {
                Image(systemName: "chart.pie.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Budget").font(.subheadline).fontWeight(.medium)
                    Text("YNAB categories & spending").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pay Hours

    private var payHoursNavCard: some View {
        NavigationLink(destination: PayHoursView()) {
            HStack(spacing: 12) {
                Image(systemName: "clock.badge.checkmark.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pay Hours").font(.subheadline).fontWeight(.medium)
                    Text("Trips, green slips & estimated pay").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Loans

    private var loansSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Loans")
                    .font(.headline)
                Spacer()
                NavigationLink(destination: FinanceLoansView()) {
                    Text("Manage")
                        .font(.subheadline)
                }
            }
            ForEach(vm.loans) { loan in
                NavigationLink(destination: LoanDetailView(loanId: loan.id)) {
                    loanRow(loan)
                }
                .buttonStyle(.plain)
            }
            HStack {
                Text("Total Debt")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                if let s = vm.summary {
                    Text(format(s.totalDebt))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.red)
                }
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func loanRow(_ loan: FinanceLoan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(loan.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(loan.loanType.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(format(loan.currentBalance))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("\(String(format: "%.2f", loan.interestRate))% · \(format(loan.monthlyPayment))/mo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: max(0, min(1, loan.progressPct / 100.0)))
                .tint(.blue)
            if let payoff = loan.payoffDate, !payoff.isEmpty {
                Text("Payoff: \(formatPayoff(payoff))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Investments

    private var investmentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Investments")
                .font(.headline)
            ForEach(vm.brokerageAccounts) { account in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(account.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        HStack(spacing: 6) {
                            Text(account.accountType.capitalized)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .clipShape(Capsule())
                            if let inst = account.institution {
                                Text(inst)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        if let bal = account.latestBalance {
                            Text(format(bal))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        } else {
                            Text("—").foregroundStyle(.tertiary)
                        }
                        if let date = account.latestImportDate {
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.bottom, 6)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Recent Paychecks

    private var recentPaychecksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent Paychecks")
                    .font(.headline)
                Spacer()
                NavigationLink(destination: PaychecksView()) {
                    Text("Manage")
                        .font(.subheadline)
                }
            }
            ForEach(vm.paychecks.prefix(5)) { check in
                NavigationLink(destination: PaycheckDetailView(paycheckId: check.id)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(check.payDate.formatted(date: .abbreviated, time: .omitted))
                                .font(.subheadline)
                                .fontWeight(.medium)
                            if let employer = check.employerName {
                                Text(employer)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(format(check.grossPay))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Net: \(format(check.netPay))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.bottom, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Trends Chart

    private func trendsSection(_ trends: FinanceTrends) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Income vs Spending").font(.headline)
                Spacer()
                Button { Task { await vm.stepTrendsYear(-1, token: auth.accessToken ?? "") } } label: { Image(systemName: "chevron.left") }
                Text(String(vm.trendsYear)).font(.subheadline).fontWeight(.medium).frame(minWidth: 44)
                Button { Task { await vm.stepTrendsYear(1, token: auth.accessToken ?? "") } } label: { Image(systemName: "chevron.right") }
            }
            let points = trends.months.filter { ($0.income ?? 0) > 0 || ($0.spending ?? 0) > 0 }
            Chart {
                ForEach(points, id: \.month) { point in
                    if let income = point.income {
                        BarMark(
                            x: .value("Month", point.month),
                            y: .value("Income", income),
                            width: .ratio(0.4)
                        )
                        .foregroundStyle(Color.accentColor)
                        .position(by: .value("Type", "Income"))
                    }
                    if let spending = point.spending {
                        BarMark(
                            x: .value("Month", point.month),
                            y: .value("Spending", spending),
                            width: .ratio(0.4)
                        )
                        .foregroundStyle(Color.orange)
                        .position(by: .value("Type", "Spending"))
                    }
                }
            }
            .chartLegend(position: .bottom, alignment: .center)
            .frame(height: 200)
            HStack(spacing: 16) {
                Label("Income", systemImage: "circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.caption)
                Label("Spending", systemImage: "circle.fill")
                    .foregroundStyle(Color.orange)
                    .font(.caption)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Formatters

    private func format(_ value: Double) -> String {
        currencyFormatter.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }

    private func formatCompact(_ value: Double) -> String {
        if abs(value) >= 1_000_000 {
            return String(format: "$%.1fM", value / 1_000_000)
        } else if abs(value) >= 1_000 {
            return String(format: "$%.0fK", value / 1_000)
        }
        return format(value)
    }

    private func formatPct(_ value: Double) -> String {
        // API may return 0–100 or 0–1; normalise to 0–1 for percent formatter
        let normalized = value > 1 ? value / 100 : value
        return pctFormatter.string(from: NSNumber(value: normalized)) ?? "\(Int(value * 100))%"
    }

    /// "2030-06-01" → "Jun 2030"
    private func formatPayoff(_ ymd: String) -> String {
        let inF = DateFormatter()
        inF.locale = Locale(identifier: "en_US_POSIX")
        inF.dateFormat = "yyyy-MM-dd"
        guard let d = inF.date(from: ymd) else { return ymd }
        let out = DateFormatter()
        out.dateFormat = "MMM yyyy"
        return out.string(from: d)
    }
}

