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
        }
        .padding(.vertical, 4)
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
    @State private var saving = false

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
}
