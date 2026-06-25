import SwiftUI
import Charts

@MainActor
final class CashflowViewModel: ObservableObject {
    @Published var summary: CashflowSummary?
    @Published var isLoading = false
    @Published var error: String?

    func load(token: String) async {
        isLoading = true
        error = nil
        do {
            summary = try await APIClient.shared.get("/finance/cashflow/", token: token)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

struct CashflowView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = CashflowViewModel()

    private var token: String { auth.accessToken ?? "" }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if let s = vm.summary {
                    if !s.largeExpenses.isEmpty {
                        largeExpensesCard(s.largeExpenses)
                    }
                    if !s.years.isEmpty {
                        chartCard(s.years)
                        inOutCard(s.years)
                    }
                    spendingCard(s.spending)
                } else if vm.isLoading {
                    ProgressView("Loading…").frame(maxWidth: .infinity, minHeight: 160)
                }
            }
            .padding(16)
        }
        .navigationTitle("Cash Flow")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load(token: token) }
        .refreshable { await vm.load(token: token) }
        .alert("Error", isPresented: .init(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK") {}
        } message: { Text(vm.error ?? "") }
    }

    // MARK: - Large purchases

    private func largeExpensesCard(_ items: [LargeExpense]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Large Purchases").font(.headline)
            Text("Categories over $4,000 in a single month (last 12 months), biggest first. A high multiple of the monthly average is likely a one-off worth a look.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(items) { e in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(e.category).font(.subheadline).fontWeight(.medium)
                            if e.abnormal {
                                Text("abnormal").font(.caption2)
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.orange))
                                    .foregroundStyle(.orange)
                            }
                        }
                        Text("\(monthLabel(e.month)) · avg \(LoanFormatters.money(e.avgMonthly, fractionDigits: 0))/mo"
                             + (e.ratio.map { " · \(String(format: "%.1f", $0))× avg" } ?? ""))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(LoanFormatters.money(e.amount, fractionDigits: 0))
                        .font(.subheadline).fontWeight(.bold)
                        .foregroundStyle(e.abnormal ? .orange : .primary)
                }
                .padding(.vertical, 3)
                Divider()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func monthLabel(_ ym: String) -> String {
        let parts = ym.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) else { return ym }
        var c = DateComponents(); c.year = y; c.month = m; c.day = 1
        guard let d = Calendar.current.date(from: c) else { return ym }
        let f = DateFormatter(); f.dateFormat = "MMM yyyy"
        return f.string(from: d)
    }

    // MARK: - Chart

    private func chartCard(_ years: [CashflowYear]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("In vs Out").font(.headline)
            Chart {
                ForEach(years.sorted { $0.year < $1.year }) { y in
                    BarMark(x: .value("Year", String(y.year)), y: .value("In", y.income), width: .ratio(0.5))
                        .foregroundStyle(.green)
                        .position(by: .value("Type", "In"))
                    BarMark(x: .value("Year", String(y.year)), y: .value("Out", y.spending), width: .ratio(0.5))
                        .foregroundStyle(.orange)
                        .position(by: .value("Type", "Out"))
                }
            }
            .chartLegend(position: .bottom)
            .frame(height: 220)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - In / Out / Net table

    private func inOutCard(_ years: [CashflowYear]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("By Year").font(.headline)
            HStack {
                Text("Year").font(.caption).foregroundStyle(.secondary).frame(width: 50, alignment: .leading)
                Spacer()
                Text("In").font(.caption).foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                Text("Out").font(.caption).foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                Text("Net").font(.caption).foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
            }
            Divider()
            ForEach(years) { y in
                HStack {
                    Text(String(y.year)).font(.subheadline).fontWeight(.medium).frame(width: 50, alignment: .leading)
                    Spacer()
                    Text(LoanFormatters.money(y.income, fractionDigits: 0))
                        .font(.subheadline).foregroundStyle(.green).frame(width: 80, alignment: .trailing)
                    Text(LoanFormatters.money(y.spending, fractionDigits: 0))
                        .font(.subheadline).frame(width: 80, alignment: .trailing)
                    Text(LoanFormatters.money(y.net, fractionDigits: 0))
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(y.net >= 0 ? .green : .red)
                        .frame(width: 80, alignment: .trailing)
                }
                .padding(.vertical, 2)
                Divider()
            }
            Text("In is take-home pay from recorded paychecks; years before paychecks were tracked show $0 in.")
                .font(.caption2).foregroundStyle(.secondary).padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Spending by category

    private func spendingCard(_ spending: CashflowSpending) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Spending by Category").font(.headline)
            Text("Top categories by total spend, compared across years.")
                .font(.caption).foregroundStyle(.secondary)
            if spending.categories.isEmpty {
                Text("No spending data yet.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                let recentYears = Array(spending.years.prefix(3))
                ForEach(spending.categories) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(c.name).font(.subheadline).fontWeight(.medium)
                            Spacer()
                            Text(LoanFormatters.money(c.total, fractionDigits: 0))
                                .font(.subheadline).fontWeight(.semibold)
                        }
                        Text(recentYears.map { y in
                            "\(y): \(LoanFormatters.money(c.byYear[String(y)] ?? 0, fractionDigits: 0))"
                        }.joined(separator: "  ·  "))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                    Divider()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
