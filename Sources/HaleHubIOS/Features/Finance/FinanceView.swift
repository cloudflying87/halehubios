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
        .alert("Error", isPresented: .constant(vm.error != nil)) {
            Button("OK") { vm.error = nil }
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
            authError = "Biometrics not available — data shown"
            isUnlocked = true
            Task { await vm.load(token: auth.accessToken ?? "") }
            return
        }
        ctx.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Unlock your financial data"
        ) { success, evalError in
            DispatchQueue.main.async {
                if success {
                    authError = nil
                    isUnlocked = true
                    Task { await vm.load(token: auth.accessToken ?? "") }
                } else {
                    authError = evalError?.localizedDescription ?? "Authentication failed"
                }
            }
        }
    }

    // MARK: - Unlocked Dashboard

    private var unlockedContent: some View {
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
                assetPillar(label: "Investments", value: s.assetsBreakdown.investments)
                Spacer()
                assetPillar(label: "Retirement", value: s.assetsBreakdown.retirement)
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

    // MARK: - Loans

    private var loansSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Loans")
                .font(.headline)
            ForEach(vm.loans) { loan in
                loanRow(loan)
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
            ProgressView(value: loan.progressPct / 100.0)
                .tint(.blue)
            if let payoff = loan.payoffDate {
                Text("Payoff: \(payoff)")
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
            Text("Recent Paychecks")
                .font(.headline)
            ForEach(vm.paychecks.prefix(5)) { check in
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
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Trends Chart

    private func trendsSection(_ trends: FinanceTrends) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Last 6 Months")
                .font(.headline)
            let points = Array(trends.months.suffix(6))
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
}

