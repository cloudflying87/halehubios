import SwiftUI
import Charts

@MainActor
final class FamilyIncomeViewModel: ObservableObject {
    @Published var prediction: FamilyPrediction?
    @Published var recurring: [RecurringIncome] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var year: Int

    init() {
        year = Calendar.current.component(.year, from: Date())
    }

    func load(token: String) async {
        isLoading = true
        error = nil
        do {
            prediction = try await APIClient.shared.get("/finance/family-prediction/?year=\(year)", token: token)
            recurring = try await APIClient.shared.get("/finance/recurring-income/", token: token)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func add(person: String, label: String, amount: Double, frequency: String, token: String) async -> Bool {
        do {
            let req = RecurringIncomeRequest(person: person, label: label.isEmpty ? nil : label, amount: amount, frequency: frequency)
            let _: RecurringIncome = try await APIClient.shared.post("/finance/recurring-income/", body: req, token: token)
            await load(token: token)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func delete(_ income: RecurringIncome, token: String) async {
        do {
            try await APIClient.shared.delete("/finance/recurring-income/\(income.id)/", token: token)
            await load(token: token)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func stepYear(_ delta: Int) { year += delta }
}

struct FamilyIncomeView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = FamilyIncomeViewModel()
    @State private var showAdd = false

    private var token: String { auth.accessToken ?? "" }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                yearSelector
                if let p = vm.prediction {
                    totalCard(p)
                    if !p.monthlyTotals.isEmpty {
                        monthlyChart(p.monthlyTotals)
                    }
                    earnersSection(p.earners)
                } else if vm.isLoading {
                    ProgressView("Loading…").frame(maxWidth: .infinity, minHeight: 160)
                }
                recurringSection
            }
            .padding(16)
        }
        .navigationTitle("Family Year")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddRecurringIncomeSheet(vm: vm)
        }
        .task { await vm.load(token: token) }
        .onChange(of: vm.year) { Task { await vm.load(token: token) } }
        .refreshable { await vm.load(token: token) }
        .alert("Error", isPresented: .init(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK") {}
        } message: { Text(vm.error ?? "") }
    }

    private var yearSelector: some View {
        HStack {
            Button { vm.stepYear(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(String(vm.year)).font(.headline)
            Spacer()
            Button { vm.stepYear(1) } label: { Image(systemName: "chevron.right") }
        }
        .padding(.horizontal, 4)
    }

    private func totalCard(_ p: FamilyPrediction) -> some View {
        VStack(spacing: 6) {
            Text("Projected household income").font(.caption).foregroundStyle(.secondary)
            Text(LoanFormatters.money(p.totalAnnual, fractionDigits: 0))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.green)
            Text("\(vm.year) full-year estimate").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func monthlyChart(_ totals: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("By Month").font(.headline)
            Chart {
                ForEach(Array(totals.enumerated()), id: \.offset) { idx, value in
                    BarMark(x: .value("Month", monthAbbr(idx)), y: .value("Income", value))
                        .foregroundStyle(Color.green.gradient)
                }
            }
            .frame(height: 180)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func earnersSection(_ earners: [FamilyEarner]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Earners").font(.headline)
            if earners.isEmpty {
                Text("No income sources yet. Add a recurring check below, or log pay hours.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(earners) { e in
                    HStack {
                        Image(systemName: e.source == "pay_hours" ? "airplane" : "dollarsign.circle.fill")
                            .foregroundStyle(e.source == "pay_hours" ? Color.accentColor : Color.green)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(e.name).font(.subheadline).fontWeight(.medium)
                            Text(e.source == "pay_hours" ? "From pay hours" : "Recurring check")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(LoanFormatters.money(e.annual, fractionDigits: 0))
                            .font(.subheadline).fontWeight(.semibold)
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

    private var recurringSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recurring Checks").font(.headline)
                Spacer()
                Button { showAdd = true } label: { Image(systemName: "plus.circle.fill") }
            }
            if vm.recurring.isEmpty {
                Text("Add a steady paycheck (e.g. a spouse's salary) to fold it into the family projection.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(vm.recurring) { r in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.person).font(.subheadline).fontWeight(.medium)
                            Text("\(LoanFormatters.money(r.amount, fractionDigits: 0)) \(frequencyLabel(r.frequency)) · \(LoanFormatters.money(r.annual, fractionDigits: 0))/yr")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            Task { await vm.delete(r, token: token) }
                        } label: { Image(systemName: "trash").font(.caption) }
                            .buttonStyle(.borderless)
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

    private func monthAbbr(_ idx: Int) -> String {
        let symbols = DateFormatter().veryShortMonthSymbols ?? []
        return (0..<12).contains(idx) && idx < symbols.count ? symbols[idx] : "\(idx + 1)"
    }

    private func frequencyLabel(_ f: String) -> String {
        switch f {
        case "weekly": return "weekly"
        case "biweekly": return "every 2 wks"
        case "semimonthly": return "twice a month"
        case "monthly": return "monthly"
        case "annual": return "yearly"
        default: return f
        }
    }
}

// MARK: - Add sheet

struct AddRecurringIncomeSheet: View {
    @ObservedObject var vm: FamilyIncomeViewModel
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var person = ""
    @State private var label = ""
    @State private var amount: Double = 0
    @State private var frequency = "biweekly"
    @State private var saving = false

    private let frequencies = [
        ("weekly", "Weekly"),
        ("biweekly", "Every 2 weeks"),
        ("semimonthly", "Twice a month"),
        ("monthly", "Monthly"),
        ("annual", "Once a year"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Who") {
                    TextField("Person (e.g. Rena)", text: $person)
                    TextField("Label (optional, e.g. Mayo Clinic)", text: $label)
                }
                Section("Check") {
                    HStack {
                        Text("Amount per check")
                        Spacer()
                        Text("$").foregroundStyle(.secondary)
                        TextField("0", value: $amount, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    Picker("Frequency", selection: $frequency) {
                        ForEach(frequencies, id: \.0) { Text($0.1).tag($0.0) }
                    }
                }
                Section {
                    Text("Folded into the family year as \(LoanFormatters.money(annual, fractionDigits: 0))/yr.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Recurring Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            saving = true
                            let ok = await vm.add(person: person, label: label, amount: amount, frequency: frequency, token: auth.accessToken ?? "")
                            saving = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(saving || person.trimmingCharacters(in: .whitespaces).isEmpty || amount <= 0)
                }
            }
        }
    }

    private var annual: Double {
        let periods: Double
        switch frequency {
        case "weekly": periods = 52
        case "biweekly": periods = 26
        case "semimonthly": periods = 24
        case "monthly": periods = 12
        case "annual": periods = 1
        default: periods = 26
        }
        return amount * periods
    }
}
