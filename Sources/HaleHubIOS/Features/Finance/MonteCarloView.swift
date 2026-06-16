import SwiftUI
import Charts

@MainActor
final class MonteCarloViewModel: ObservableObject {
    @Published var result: MonteCarloSimulation?
    @Published var running = false
    @Published var error: String?

    // Inputs
    @Published var initialInvestment: Double = 10000
    @Published var monthlyContribution: Double = 500
    @Published var years: Int = 20
    @Published var expectedReturn: Double = 7
    @Published var volatility: Double = 15
    @Published var numSimulations: Int = 1000

    func applySeed(_ seed: MonteCarloSeed) {
        initialInvestment = seed.initialInvestment
        monthlyContribution = seed.monthlyContribution
        expectedReturn = seed.expectedAnnualReturn
        volatility = seed.volatility
    }

    func run(token: String) async {
        running = true
        error = nil
        do {
            let req = MonteCarloRequest(
                name: "Simulation",
                initialInvestment: initialInvestment,
                monthlyContribution: monthlyContribution,
                years: years,
                expectedAnnualReturn: expectedReturn,
                volatility: volatility,
                numSimulations: numSimulations
            )
            result = try await APIClient.shared.post("/finance/monte-carlo/", body: req, token: token)
        } catch {
            self.error = error.localizedDescription
        }
        running = false
    }
}

struct MonteCarloView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = MonteCarloViewModel()
    private var token: String { auth.accessToken ?? "" }

    /// Optional pre-fill from the user's own retirement history.
    var seed: MonteCarloSeed? = nil

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if seed != nil { seededBanner }
                inputsCard
                if vm.running {
                    ProgressView("Running \(vm.numSimulations) simulations…")
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else if let r = vm.result, let res = r.results {
                    resultsCard(r, res)
                    percentileChart(res)
                    spreadCard(res)
                }
            }
            .padding(16)
        }
        .navigationTitle("Monte Carlo")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if let seed { vm.applySeed(seed) } }
        .alert("Error", isPresented: .init(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK") {}
        } message: { Text(vm.error ?? "") }
    }

    private var seededBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.stars")
            Text("Pre-filled from your retirement history — adjust anything below.")
                .font(.caption)
            Spacer()
        }
        .foregroundStyle(.blue)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var inputsCard: some View {
        VStack(spacing: 14) {
            sliderRow("Initial investment", value: $vm.initialInvestment, range: 0...3_000_000, step: 1000, money: true)
            sliderRow("Monthly contribution", value: $vm.monthlyContribution, range: 0...20000, step: 50, money: true)
            stepperRow("Years", value: $vm.years, range: 1...50, suffix: "yr")
            sliderRow("Expected return", value: $vm.expectedReturn, range: 1...15, step: 0.5, percent: true)
            sliderRow("Volatility", value: $vm.volatility, range: 1...40, step: 1, percent: true)
            Picker("Simulations", selection: $vm.numSimulations) {
                ForEach([500, 1000, 5000, 10000], id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.segmented)
            Button {
                Task { await vm.run(token: token) }
            } label: {
                Label("Run Simulation", systemImage: "dice.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.running)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func resultsCard(_ r: MonteCarloSimulation, _ res: MonteCarloResults) -> some View {
        VStack(spacing: 6) {
            Text("Median outcome in \(r.years) years").font(.caption).foregroundStyle(.secondary)
            Text(LoanFormatters.money(res.finalValues.p50, fractionDigits: 0))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.green)
            Text("\(Int(res.probabilityOfGain.rounded()))% chance of finishing above what you put in")
                .font(.caption2).foregroundStyle(.tertiary).multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func percentileChart(_ res: MonteCarloResults) -> some View {
        let points: [(String, Double)] = [
            ("5th", res.finalValues.p5), ("10th", res.finalValues.p10), ("25th", res.finalValues.p25),
            ("50th", res.finalValues.p50), ("75th", res.finalValues.p75), ("90th", res.finalValues.p90),
            ("95th", res.finalValues.p95),
        ]
        return VStack(alignment: .leading, spacing: 10) {
            Text("Range of outcomes").font(.headline)
            Chart {
                ForEach(points, id: \.0) { label, value in
                    BarMark(x: .value("Percentile", label), y: .value("Value", value))
                        .foregroundStyle(label == "50th" ? Color.green : Color.green.opacity(0.4))
                }
            }
            .chartYAxis {
                AxisMarks { v in
                    AxisValueLabel { if let d = v.as(Double.self) { Text(compact(d)) } }
                }
            }
            .frame(height: 200)
            Text("Each bar is a percentile of \(vm.numSimulations) simulated futures — 90% of outcomes land between the 5th and 95th.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func spreadCard(_ res: MonteCarloResults) -> some View {
        VStack(spacing: 8) {
            spreadRow("Pessimistic (10th)", res.finalValues.p10, .orange)
            spreadRow("Median (50th)", res.finalValues.p50, .green)
            spreadRow("Optimistic (90th)", res.finalValues.p90, .blue)
            Divider()
            spreadRow("Average", res.mean, .secondary)
            spreadRow("Worst case", res.min, .red)
            spreadRow("Best case", res.max, .secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func spreadRow(_ label: String, _ value: Double, _ color: Color) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(LoanFormatters.money(value, fractionDigits: 0)).font(.subheadline).fontWeight(.semibold).foregroundStyle(color)
        }
    }

    private func sliderRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, money: Bool = false, percent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Text(percent ? String(format: "%.1f%%", value.wrappedValue) : LoanFormatters.money(value.wrappedValue, fractionDigits: 0))
                    .font(.subheadline).fontWeight(.semibold)
            }
            Slider(value: value, in: range, step: step)
        }
    }

    private func stepperRow(_ label: String, value: Binding<Int>, range: ClosedRange<Int>, suffix: String) -> some View {
        Stepper(value: value, in: range) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Text("\(value.wrappedValue) \(suffix)").font(.subheadline).fontWeight(.semibold)
            }
        }
    }

    private func compact(_ value: Double) -> String {
        if abs(value) >= 1_000_000 { return String(format: "$%.1fM", value / 1_000_000) }
        if abs(value) >= 1_000 { return String(format: "$%.0fK", value / 1_000) }
        return String(format: "$%.0f", value)
    }
}
