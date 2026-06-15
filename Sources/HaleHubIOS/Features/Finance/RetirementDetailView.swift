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
                    if s.accounts.isEmpty {
                        ContentUnavailableView(
                            "No Retirement Accounts",
                            systemImage: "chart.line.uptrend.xyaxis",
                            description: Text("Retirement balances are imported from Fidelity reports.")
                        )
                        .frame(minHeight: 160)
                    } else {
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
