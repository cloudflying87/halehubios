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

    private func accountCard(_ a: RetirementAccount) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(a.name).font(.headline)
                Spacer()
                Text(LoanFormatters.money(a.latestBalance, fractionDigits: 0))
                    .font(.headline).foregroundStyle(.green)
            }
            Text("As of \(LoanFormatters.fullDate(a.latestDate)) · \(a.reportCount) reports")
                .font(.caption).foregroundStyle(.secondary)

            if a.history.count > 1 {
                Chart(a.history) { point in
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

            Divider()
            HStack {
                metric("Earnings", a.earnings, a.earnings >= 0 ? .green : .red)
                Spacer()
                metric("Contributions", a.contributions, .primary)
                Spacer()
                metric("Fees", a.fees, a.fees > 0 ? .orange : .secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

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
