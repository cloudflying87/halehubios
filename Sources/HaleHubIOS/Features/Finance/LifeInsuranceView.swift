import SwiftUI

@MainActor
final class LifeInsuranceViewModel: ObservableObject {
    @Published var policies: [LifeInsurancePolicy] = []
    @Published var isLoading = false
    @Published var error: String?

    func load(token: String) async {
        isLoading = true; error = nil
        do { policies = try await APIClient.shared.get("/finance/life-insurance/", token: token) }
        catch { self.error = error.localizedDescription }
        isLoading = false
    }

    func add(_ req: LifeInsuranceRequest, token: String) async -> Bool {
        do {
            let _: LifeInsurancePolicy = try await APIClient.shared.post("/finance/life-insurance/", body: req, token: token)
            await load(token: token); return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func update(id: Int, req: LifeInsuranceRequest, token: String) async -> Bool {
        do {
            let _: LifeInsurancePolicy = try await APIClient.shared.patch("/finance/life-insurance/\(id)/", body: req, token: token)
            await load(token: token); return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func delete(_ p: LifeInsurancePolicy, token: String) async {
        do { try await APIClient.shared.delete("/finance/life-insurance/\(p.id)/", token: token); await load(token: token) }
        catch { self.error = error.localizedDescription }
    }

    var totalCoverage: Double { policies.reduce(0) { $0 + $1.coverageAmount } }
    var totalAnnualPremium: Double { policies.reduce(0) { $0 + $1.annualPremium } }
}

let lifePolicyTypes: [(String, String)] = [
    ("term", "Term"), ("whole", "Whole Life"), ("universal", "Universal Life"),
    ("variable", "Variable Life"), ("group", "Group / Employer"), ("other", "Other"),
]
let lifePremiumFrequencies: [(String, String)] = [
    ("monthly", "Monthly"), ("quarterly", "Quarterly"), ("semiannual", "Semi-annual"), ("annual", "Annual"),
]

struct LifeInsuranceView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = LifeInsuranceViewModel()
    @State private var showAdd = false
    @State private var editing: LifeInsurancePolicy?
    private var token: String { auth.accessToken ?? "" }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                totalsCard
                if vm.policies.isEmpty && !vm.isLoading {
                    ContentUnavailableView("No Policies", systemImage: "shield.lefthalf.filled",
                        description: Text("Tap + to add a life insurance policy. Stored behind the finance lock."))
                    .frame(minHeight: 140)
                } else {
                    ForEach(vm.policies) { p in
                        Button { editing = p } label: { row(p) }.buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("Life Insurance")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showAdd) {
            LifeInsuranceFormSheet(title: "Add Policy") { req in await vm.add(req, token: token) }
        }
        .sheet(item: $editing) { p in
            LifeInsuranceFormSheet(title: "Edit Policy", existing: p) { req in
                await vm.update(id: p.id, req: req, token: token)
            } onDelete: { await vm.delete(p, token: token) }
        }
        .task { await vm.load(token: token) }
        .refreshable { await vm.load(token: token) }
        .alert("Error", isPresented: .init(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK") {}
        } message: { Text(vm.error ?? "") }
    }

    private var totalsCard: some View {
        HStack {
            VStack(spacing: 2) {
                Text("Coverage").font(.caption2).foregroundStyle(.secondary)
                Text(LoanFormatters.money(vm.totalCoverage, fractionDigits: 0)).font(.headline).foregroundStyle(.green)
            }.frame(maxWidth: .infinity)
            Divider()
            VStack(spacing: 2) {
                Text("Annual Premium").font(.caption2).foregroundStyle(.secondary)
                Text(LoanFormatters.money(vm.totalAnnualPremium, fractionDigits: 0)).font(.headline).foregroundStyle(.orange)
            }.frame(maxWidth: .infinity)
        }
        .padding(16).background(Color(.secondarySystemGroupedBackground)).clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func row(_ p: LifeInsurancePolicy) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(p.insurer).font(.subheadline).fontWeight(.semibold)
                Spacer()
                Text(LoanFormatters.money(p.coverageAmount, fractionDigits: 0)).font(.subheadline).fontWeight(.semibold).foregroundStyle(.green)
            }
            Text("\(typeLabel(p.policyType)) · insures \(p.insuredPerson)\(p.beneficiary.isEmpty ? "" : " · to \(p.beneficiary)")")
                .font(.caption2).foregroundStyle(.secondary)
            if let end = endLabel(p) {
                HStack(spacing: 4) {
                    Image(systemName: p.isExpired ? "exclamationmark.triangle.fill" : "calendar")
                        .font(.caption2)
                    Text(p.isExpired ? "Expired \(end)" : "Ends \(end)")
                        .font(.caption2).fontWeight(.medium)
                }
                .foregroundStyle(p.isExpired ? .red : .blue)
            }
        }
        .padding(.vertical, 4)
    }

    /// Formatted calculated end date ("Jun 2042"), or nil for permanent coverage.
    private func endLabel(_ p: LifeInsurancePolicy) -> String? {
        guard let raw = p.effectiveEndDate, let d = LifeInsuranceFormSheet.parseYMD(raw) else { return nil }
        return d.formatted(.dateTime.month(.abbreviated).year())
    }

    private func typeLabel(_ t: String) -> String { lifePolicyTypes.first { $0.0 == t }?.1 ?? t }
}

struct LifeInsuranceFormSheet: View {
    let title: String
    var existing: LifeInsurancePolicy?
    let onSave: (LifeInsuranceRequest) async -> Bool
    var onDelete: (() async -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var insurer = ""
    @State private var insured = ""
    @State private var type = "term"
    @State private var policyNumber = ""
    @State private var coverage: Double = 0
    @State private var premium: Double = 0
    @State private var frequency = "monthly"
    @State private var cashValue: Double = 0
    @State private var beneficiary = ""
    @State private var notes = ""
    @State private var hasStartDate = false
    @State private var startDate = Date()
    @State private var termYears: Int = 0
    @State private var saving = false

    /// Live-calculated coverage end from start date + term length.
    private var computedEnd: Date? {
        guard hasStartDate, termYears > 0 else { return nil }
        return Calendar.current.date(byAdding: .year, value: termYears, to: startDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Policy") {
                    TextField("Insurer", text: $insurer)
                    TextField("Insured person", text: $insured)
                    Picker("Type", selection: $type) { ForEach(lifePolicyTypes, id: \.0) { Text($0.1).tag($0.0) } }
                    TextField("Policy number (optional)", text: $policyNumber)
                }
                Section("Coverage & premium") {
                    money("Coverage (death benefit)", $coverage)
                    money("Premium", $premium)
                    Picker("Frequency", selection: $frequency) { ForEach(lifePremiumFrequencies, id: \.0) { Text($0.1).tag($0.0) } }
                    money("Cash value (optional)", $cashValue)
                }
                Section {
                    Toggle("Has a start date", isOn: $hasStartDate.animation())
                    if hasStartDate {
                        DatePicker("Started", selection: $startDate, displayedComponents: .date)
                        Stepper(value: $termYears, in: 0...100) {
                            HStack {
                                Text("Term length")
                                Spacer()
                                Text(termYears == 0 ? "—" : "\(termYears) yr").foregroundStyle(.secondary)
                            }
                        }
                        if let end = computedEnd {
                            HStack {
                                Text("Policy ends").fontWeight(.semibold)
                                Spacer()
                                Text(end.formatted(date: .abbreviated, time: .omitted))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(end < Date() ? .red : .blue)
                            }
                        } else if termYears == 0 {
                            Text("Add a term length to calculate the end date.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Coverage period")
                } footer: {
                    if hasStartDate && termYears > 0 {
                        Text("End date is calculated from the start date plus the term length.")
                    }
                }
                Section("Other") {
                    TextField("Beneficiary (optional)", text: $beneficiary)
                    TextField("Notes (optional)", text: $notes)
                }
                if existing != nil, let onDelete {
                    Section {
                        Button(role: .destructive) { Task { await onDelete(); dismiss() } } label: {
                            Text("Delete Policy").frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") {
                        Task {
                            saving = true
                            let ok = await onSave(LifeInsuranceRequest(
                                insurer: insurer, insuredPerson: insured, policyType: type,
                                policyNumber: policyNumber.isEmpty ? nil : policyNumber,
                                coverageAmount: coverage, premium: premium, premiumFrequency: frequency,
                                cashValue: cashValue, beneficiary: beneficiary.isEmpty ? nil : beneficiary,
                                startDate: hasStartDate ? Self.ymd(startDate) : nil,
                                termYears: (hasStartDate && termYears > 0) ? termYears : nil,
                                // Let the backend calculate the end from start + term.
                                endDate: nil,
                                notes: notes.isEmpty ? nil : notes
                            ))
                            saving = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(saving || insurer.trimmingCharacters(in: .whitespaces).isEmpty || insured.trimmingCharacters(in: .whitespaces).isEmpty || coverage <= 0)
                }
            }
            .onAppear {
                if let e = existing {
                    insurer = e.insurer; insured = e.insuredPerson; type = e.policyType
                    policyNumber = e.policyNumber; coverage = e.coverageAmount; premium = e.premium
                    frequency = e.premiumFrequency; cashValue = e.cashValue; beneficiary = e.beneficiary; notes = e.notes
                    if let s = e.startDate, let d = Self.parseYMD(s) {
                        hasStartDate = true
                        startDate = d
                    }
                    termYears = e.termYears ?? 0
                }
            }
        }
    }

    private func money(_ label: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("$").foregroundStyle(.secondary)
            TextField("0", value: value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
        }
    }

    /// Date → "yyyy-MM-dd" (the API's date format).
    static func ymd(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    /// "yyyy-MM-dd" → Date.
    static func parseYMD(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(s.prefix(10)))
    }
}
