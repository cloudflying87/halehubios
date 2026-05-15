import SwiftUI

struct LoanCalculatorView: View {
    @State private var principal = ""
    @State private var annualRate = ""
    @State private var termYears = ""
    @State private var result: LoanResult?

    var body: some View {
        Form {
            Section("Loan Details") {
                CurrencyField(label: "Loan Amount", text: $principal)
                PercentField(label: "Annual Interest Rate", text: $annualRate)
                LabeledContent("Loan Term") {
                    HStack {
                        TextField("Years", text: $termYears)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        Text("years").foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button("Calculate") { calculate() }
                    .frame(maxWidth: .infinity)
                    .disabled(principal.isEmpty || annualRate.isEmpty || termYears.isEmpty)
            }

            if let r = result {
                Section("Results") {
                    ResultRow(label: "Monthly Payment", value: r.monthlyPayment.currency())
                    ResultRow(label: "Total Paid", value: r.totalPaid.currency())
                    ResultRow(label: "Total Interest", value: r.totalInterest.currency(), highlight: true)
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        let principalPct = r.principal / r.totalPaid
                        let interestPct = 1 - principalPct
                        GeometryReader { geo in
                            HStack(spacing: 0) {
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(width: geo.size.width * principalPct)
                                Rectangle()
                                    .fill(Color.orange.opacity(0.7))
                            }
                        }
                        .frame(height: 10)
                        .clipShape(Capsule())

                        HStack {
                            Label(String(format: "Principal %.0f%%", principalPct * 100), systemImage: "square.fill")
                                .foregroundStyle(Color.accentColor)
                            Spacer()
                            Label(String(format: "Interest %.0f%%", interestPct * 100), systemImage: "square.fill")
                                .foregroundStyle(.orange)
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Loan Calculator")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: principal) { _, _ in result = nil }
        .onChange(of: annualRate) { _, _ in result = nil }
        .onChange(of: termYears) { _, _ in result = nil }
    }

    private func calculate() {
        guard
            let P = Double(principal.replacingOccurrences(of: ",", with: "")),
            let annualRateVal = Double(annualRate),
            let years = Int(termYears),
            P > 0, annualRateVal >= 0, years > 0
        else { return }

        let r = annualRateVal / 100 / 12
        let n = Double(years * 12)

        let monthly: Double
        if r == 0 {
            monthly = P / n
        } else {
            monthly = P * (r * pow(1 + r, n)) / (pow(1 + r, n) - 1)
        }

        let totalPaid = monthly * n
        result = LoanResult(
            principal: P,
            monthlyPayment: monthly,
            totalPaid: totalPaid,
            totalInterest: totalPaid - P
        )
    }
}

struct LoanResult {
    let principal: Double
    let monthlyPayment: Double
    let totalPaid: Double
    let totalInterest: Double
}

struct ResultRow: View {
    let label: String
    let value: String
    var highlight = false

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .font(highlight ? .body.bold() : .body)
                .foregroundStyle(highlight ? .orange : .primary)
        }
    }
}

struct CurrencyField: View {
    let label: String
    @Binding var text: String
    var body: some View {
        LabeledContent(label) {
            HStack {
                Text("$").foregroundStyle(.secondary)
                TextField("0", text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

struct PercentField: View {
    let label: String
    @Binding var text: String
    var body: some View {
        LabeledContent(label) {
            HStack {
                TextField("0.0", text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                Text("%").foregroundStyle(.secondary)
            }
        }
    }
}

extension Double {
    func currency() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: self)) ?? "$\(self)"
    }
}
