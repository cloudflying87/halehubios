import SwiftUI
import Charts

@MainActor
final class RetirementViewModel: ObservableObject {
    @Published var summary: RetirementSummary?
    @Published var isLoading = false
    @Published var error: String?

    func load(token: String) async {
        isLoading = true
        error = nil
        do {
            summary = try await APIClient.shared.get("/finance/retirement/", token: token)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

struct RetirementDetailView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = RetirementViewModel()

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedMonth: RetirementHistoryPoint? = nil

    private var token: String { auth.accessToken ?? "" }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if let s = vm.summary {
                    totalCard(s)
                    if let a = s.analysis {
                        performanceCard(a.metrics)
                        yearlyCard(a)
                        projectButton(a.monteCarloSeed)
                    }
                    if s.accounts.isEmpty {
                        ContentUnavailableView(
                            "No Retirement Accounts",
                            systemImage: "chart.line.uptrend.xyaxis",
                            description: Text("Retirement balances are imported from Fidelity reports.")
                        )
                        .frame(minHeight: 160)
                    } else {
                        Text("Accounts").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(s.accounts) { accountCard($0) }
                    }
                } else if vm.isLoading {
                    ProgressView("Loading…").frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(16)
        }
        .navigationTitle("Retirement")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load(token: token) }
        .refreshable { await vm.load(token: token) }
        .alert("Error", isPresented: .init(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK") {}
        } message: { Text(vm.error ?? "") }
    }

    private func totalCard(_ s: RetirementSummary) -> some View {
        VStack(spacing: 6) {
            Text("Total Retirement").font(.caption).foregroundStyle(.secondary)
            Text(LoanFormatters.money(s.total, fractionDigits: 0))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.green)
            Text("\(s.accounts.count) account\(s.accounts.count == 1 ? "" : "s") · from Fidelity reports")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Performance summary

    private func performanceCard(_ m: RetirementMetrics) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Performance").font(.headline)
            HStack {
                bigStat("Annualized return", String(format: "%.1f%%", m.annualizedReturnPct),
                        m.annualizedReturnPct >= 0 ? .green : .red)
                Spacer()
                bigStat("Net gain", LoanFormatters.money(m.netGain, fractionDigits: 0),
                        m.netGain >= 0 ? .green : .red)
            }
            Divider()
            grid([
                ("Total contributed", LoanFormatters.money(m.totalContributions, fractionDigits: 0), Color.primary),
                ("Total earnings", LoanFormatters.money(m.totalEarnings, fractionDigits: 0), .green),
                ("Return on contributions", String(format: "%.0f%%", m.roiPct), .blue),
                ("Fees paid", LoanFormatters.money(m.totalFees, fractionDigits: 0), m.totalFees > 0 ? .orange : .secondary),
                ("Years tracked", String(format: "%.1f yrs", m.yearsTracked), .secondary),
                ("Current balance", LoanFormatters.money(m.currentBalance, fractionDigits: 0), .primary),
            ])
            Text("Annualized return is the median of full calendar years; the first partial year is excluded.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func bigStat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func grid(_ rows: [(String, String, Color)]) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                HStack {
                    Text(r.0).font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text(r.1).font(.subheadline).fontWeight(.semibold).foregroundStyle(r.2)
                }
            }
        }
    }

    // MARK: Year over year

    private func yearlyCard(_ a: RetirementAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Year over Year").font(.headline)

            Chart(a.yearly) { y in
                BarMark(
                    x: .value("Year", String(y.year)),
                    y: .value("Return", y.returnPct)
                )
                .foregroundStyle(y.returnPct >= 0 ? Color.green : Color.red)
                .opacity(y.isPartial ? 0.45 : 1)
            }
            .chartYAxis {
                AxisMarks { v in
                    AxisGridLine()
                    AxisValueLabel { if let d = v.as(Double.self) { Text("\(Int(d))%") } }
                }
            }
            .frame(height: 160)

            VStack(spacing: 6) {
                HStack {
                    Text("Year").font(.caption2).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
                    Text("Return").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Contrib").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Balance").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing)
                }
                ForEach(a.yearly.reversed()) { y in
                    HStack {
                        HStack(spacing: 3) {
                            Text(String(y.year)).font(.caption).fontWeight(.medium)
                            if y.isPartial { Text("partial").font(.system(size: 8)).foregroundStyle(.tertiary) }
                        }.frame(width: 52, alignment: .leading)
                        Text(String(format: "%+.1f%%", y.returnPct))
                            .font(.caption).fontWeight(.semibold)
                            .foregroundStyle(y.returnPct >= 0 ? .green : .red)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(compact(y.contributions)).font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(compact(y.endBalance)).font(.caption).fontWeight(.medium)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Projection

    private func projectButton(_ seed: MonteCarloSeed) -> some View {
        NavigationLink {
            MonteCarloView(seed: seed)
        } label: {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Project with Monte Carlo").fontWeight(.semibold)
                    Text("Seeded with \(String(format: "%.0f%%", seed.expectedAnnualReturn)) return · \(LoanFormatters.money(seed.monthlyContribution, fractionDigits: 0))/mo")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: Account card (redesigned)

    private func accountCard(_ a: RetirementAccount) -> some View {
        let yearMonths = a.history
            .filter { historyYear($0.date) == selectedYear }
            .reversed() as [RetirementHistoryPoint]
        let ytd = a.ytdByYear[String(selectedYear)]

        return VStack(alignment: .leading, spacing: 16) {

            // Section 1 — Header + year picker
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.name).font(.headline)
                        Text("As of \(LoanFormatters.fullDate(a.latestDate)) · \(a.reportCount) reports")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(LoanFormatters.money(a.latestBalance, fractionDigits: 0))
                        .font(.headline).foregroundStyle(.green)
                }

                if !a.availableYears.isEmpty {
                    Picker("Year", selection: $selectedYear) {
                        ForEach(a.availableYears, id: \.self) { Text(String($0)).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onAppear {
                        if let first = a.availableYears.first { selectedYear = first }
                    }
                }
            }

            Divider()

            // Section 2 — YTD summary
            if let ytd {
                VStack(alignment: .leading, spacing: 10) {
                    Text("YTD \(selectedYear)").font(.subheadline).fontWeight(.semibold)

                    ytdRow("YTD Return",
                           String(format: "%+.2f%%", ytd.performancePct),
                           ytd.performancePct >= 0 ? .green : .red)
                    Divider()

                    if let emp = ytd.employeeContribution {
                        ytdRow("Your Contributions",
                               LoanFormatters.money(emp, fractionDigits: 0),
                               .primary)
                        Divider()
                    }
                    if let employer = ytd.employerContribution {
                        ytdRow("Company Match",
                               LoanFormatters.money(employer, fractionDigits: 0),
                               .primary)
                        Divider()
                    }
                    if ytd.employeeContribution == nil && ytd.employerContribution == nil {
                        ytdRow("Contributions",
                               LoanFormatters.money(ytd.contributions, fractionDigits: 0),
                               .primary)
                        Divider()
                    }

                    ytdRow("Earnings",
                           LoanFormatters.money(ytd.earnings, fractionDigits: 0),
                           .green)
                    Divider()

                    ytdRow("Fees",
                           LoanFormatters.money(ytd.fees, fractionDigits: 0),
                           ytd.fees > 0 ? .orange : .secondary)
                    Divider()

                    ytdRow("Start Balance",
                           LoanFormatters.money(ytd.startBalance, fractionDigits: 0),
                           .secondary)
                    Divider()

                    ytdRow("End Balance",
                           LoanFormatters.money(ytd.endBalance, fractionDigits: 0),
                           .primary)
                }
            } else {
                Text("No data for \(selectedYear)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Section 3 — Selected month detail
            if let month = selectedMonth {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(shortMonthYear(month.date))
                            .font(.subheadline).fontWeight(.semibold)
                        Spacer()
                        Button {
                            selectedMonth = nil
                        } label: {
                            Text("✕ Clear").font(.caption).foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }

                    monthDetailRow("Balance",
                                   LoanFormatters.money(month.balance, fractionDigits: 0),
                                   .primary)
                    Divider()

                    let returnLabel = String(format: "%+.2f%%", month.performancePct)
                    monthDetailRow("Earnings",
                                   "\(LoanFormatters.money(month.earnings, fractionDigits: 0)) (\(returnLabel))",
                                   month.earnings >= 0 ? .green : .red)
                    Divider()

                    if let emp = month.employeeContribution {
                        monthDetailRow("Your Contributions",
                                       LoanFormatters.money(emp, fractionDigits: 0),
                                       .primary)
                        Divider()
                    }
                    if let employer = month.employerContribution {
                        monthDetailRow("Company Match",
                                       LoanFormatters.money(employer, fractionDigits: 0),
                                       .primary)
                        Divider()
                    }

                    monthDetailRow("Total Contributions",
                                   LoanFormatters.money(month.contributions, fractionDigits: 0),
                                   .primary)
                    Divider()

                    monthDetailRow("Fees",
                                   LoanFormatters.money(month.fees, fractionDigits: 0),
                                   month.fees > 0 ? .orange : .secondary)
                }
            }

            // Section 4 — Monthly history list for selected year
            if !yearMonths.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    Text("Monthly History").font(.subheadline).fontWeight(.semibold)
                        .padding(.bottom, 8)

                    ForEach(yearMonths) { point in
                        Button {
                            selectedMonth = (selectedMonth?.id == point.id) ? nil : point
                        } label: {
                            HStack {
                                Text(shortMonthYear(point.date))
                                    .font(.subheadline)
                                    .foregroundStyle(selectedMonth?.id == point.id ? .blue : .primary)
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(LoanFormatters.money(point.balance, fractionDigits: 0))
                                        .font(.subheadline).fontWeight(.semibold)
                                    if point.performancePct != 0 {
                                        Text(String(format: "%+.2f%%", point.performancePct))
                                            .font(.caption2)
                                            .foregroundStyle(point.performancePct >= 0 ? .green : .red)
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }

            // Section 5 — Balance chart for selected year
            if yearMonths.count > 1 {
                Divider()
                let chartPoints = Array(yearMonths.reversed())
                Chart(chartPoints) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Balance", point.balance)
                    )
                    .foregroundStyle(.green.opacity(0.15))
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Balance", point.balance)
                    )
                    .foregroundStyle(.green)
                    .interpolationMethod(.monotone)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisValueLabel {
                            if let s = value.as(String.self) { Text(shortDate(s)) }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let d = value.as(Double.self) { Text(compact(d)) }
                        }
                    }
                }
                .frame(height: 160)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Account card helpers

    private func ytdRow(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline).fontWeight(.semibold).foregroundStyle(color)
        }
    }

    private func monthDetailRow(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline).fontWeight(.semibold).foregroundStyle(color)
        }
    }

    private func shortMonthYear(_ ymd: String) -> String {
        let parts = ymd.split(separator: "-")
        guard parts.count >= 2,
              let m = Int(parts[1]), (1...12).contains(m) else { return ymd }
        let symbols = Calendar.current.monthSymbols
        return "\(symbols[m - 1]) \(parts[0])"
    }

    private func historyYear(_ ymd: String) -> Int {
        let parts = ymd.split(separator: "-")
        guard let y = Int(parts.first ?? "") else { return 0 }
        return y
    }

    // MARK: - Shared helpers

    private func metric(_ label: String, _ value: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(LoanFormatters.money(value, fractionDigits: 0)).font(.subheadline).fontWeight(.semibold).foregroundStyle(color)
        }
    }

    private func shortDate(_ ymd: String) -> String {
        let parts = ymd.split(separator: "-")
        guard parts.count >= 2 else { return ymd }
        let symbols = DateFormatter().shortMonthSymbols ?? []
        if let m = Int(parts[1]), (1...12).contains(m) {
            let yy = parts[0].suffix(2)
            return "\(symbols[m - 1]) '\(yy)"
        }
        return ymd
    }

    private func compact(_ value: Double) -> String {
        if abs(value) >= 1_000_000 { return String(format: "$%.1fM", value / 1_000_000) }
        if abs(value) >= 1_000 { return String(format: "$%.0fK", value / 1_000) }
        return String(format: "$%.0f", value)
    }
}
