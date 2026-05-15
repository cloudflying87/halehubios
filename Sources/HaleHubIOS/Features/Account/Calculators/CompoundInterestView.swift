import SwiftUI

struct CompoundInterestView: View {
    @State private var principal = ""
    @State private var monthlyContribution = ""
    @State private var annualRate = ""
    @State private var years = ""
    @State private var frequency = CompoundFrequency.monthly
    @State private var result: CompoundResult?

    var body: some View {
        Form {
            Section("Investment Details") {
                CurrencyField(label: "Initial Investment", text: $principal)
                CurrencyField(label: "Monthly Contribution", text: $monthlyContribution)
                PercentField(label: "Annual Interest Rate", text: $annualRate)
                LabeledContent("Time Period") {
                    HStack {
                        TextField("Years", text: $years)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        Text("years").foregroundStyle(.secondary)
                    }
                }
                Picker("Compounding", selection: $frequency) {
                    ForEach(CompoundFrequency.allCases) { f in
                        Text(f.label).tag(f)
                    }
                }
            }

            Section {
                Button("Calculate") { calculate() }
                    .frame(maxWidth: .infinity)
                    .disabled(annualRate.isEmpty || years.isEmpty)
            }

            if let r = result {
                Section("Results") {
                    ResultRow(label: "Final Balance", value: r.finalBalance.currency(), highlight: true)
                    ResultRow(label: "Total Contributions", value: r.totalContributions.currency())
                    ResultRow(label: "Interest Earned", value: r.interestEarned.currency())
                }

                Section("Growth Over Time") {
                    CompoundChart(milestones: r.milestones)
                }
            }
        }
        .navigationTitle("Compound Interest")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: principal) { _, _ in result = nil }
        .onChange(of: monthlyContribution) { _, _ in result = nil }
        .onChange(of: annualRate) { _, _ in result = nil }
        .onChange(of: years) { _, _ in result = nil }
        .onChange(of: frequency) { _, _ in result = nil }
    }

    private func calculate() {
        guard
            let rate = Double(annualRate),
            let t = Double(years),
            t > 0, rate >= 0
        else { return }

        let P = Double(principal.replacingOccurrences(of: ",", with: "")) ?? 0
        let PMT = Double(monthlyContribution.replacingOccurrences(of: ",", with: "")) ?? 0
        let n = Double(frequency.timesPerYear)
        let rn = rate / 100 / n

        let principalGrowth = rn == 0 ? P : P * pow(1 + rn, n * t)

        let monthlyRate = rate / 100 / 12
        let months = t * 12
        let contributionsGrowth: Double
        if monthlyRate == 0 {
            contributionsGrowth = PMT * months
        } else {
            contributionsGrowth = PMT * ((pow(1 + monthlyRate, months) - 1) / monthlyRate)
        }

        let finalBalance = principalGrowth + contributionsGrowth
        let totalContributions = P + PMT * months
        let interestEarned = finalBalance - totalContributions

        // Build year-by-year milestones for the chart
        var milestones: [(year: Int, balance: Double)] = []
        let totalYears = Int(t)
        let step = max(1, totalYears / 10)
        for y in stride(from: step, through: totalYears, by: step) {
            let yt = Double(y)
            let pg = rn == 0 ? P : P * pow(1 + rn, n * yt)
            let months_y = yt * 12
            let cg: Double = monthlyRate == 0 ? PMT * months_y : PMT * ((pow(1 + monthlyRate, months_y) - 1) / monthlyRate)
            milestones.append((year: y, balance: pg + cg))
        }

        result = CompoundResult(
            finalBalance: finalBalance,
            totalContributions: totalContributions,
            interestEarned: interestEarned,
            milestones: milestones
        )
    }
}

enum CompoundFrequency: String, CaseIterable, Identifiable {
    case monthly, quarterly, semiAnnually, annually, daily
    var id: String { rawValue }
    var label: String {
        switch self {
        case .monthly: return "Monthly"
        case .quarterly: return "Quarterly"
        case .semiAnnually: return "Semi-Annually"
        case .annually: return "Annually"
        case .daily: return "Daily"
        }
    }
    var timesPerYear: Int {
        switch self {
        case .monthly: return 12
        case .quarterly: return 4
        case .semiAnnually: return 2
        case .annually: return 1
        case .daily: return 365
        }
    }
}

struct CompoundResult {
    let finalBalance: Double
    let totalContributions: Double
    let interestEarned: Double
    let milestones: [(year: Int, balance: Double)]
}

struct CompoundChart: View {
    let milestones: [(year: Int, balance: Double)]

    var maxBalance: Double { milestones.map { $0.balance }.max() ?? 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(milestones, id: \.year) { m in
                        VStack(spacing: 2) {
                            Spacer()
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.accentColor)
                                .frame(height: max(4, geo.size.height * 0.85 * (m.balance / maxBalance)))
                            Text("Y\(m.year)")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: 120)

            if let last = milestones.last {
                Text("Year \(last.year): \(last.balance.currency())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
