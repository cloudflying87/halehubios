import SwiftUI

@MainActor
final class OtherAccountsViewModel: ObservableObject {
    @Published var accounts: [OtherAccount] = []
    @Published var isLoading = false
    @Published var error: String?

    var assets: [OtherAccount] { accounts.filter { $0.kind == "asset" } }
    var liabilities: [OtherAccount] { accounts.filter { $0.kind == "liability" } }

    func load(token: String) async {
        isLoading = true
        error = nil
        do {
            accounts = try await APIClient.shared.get("/finance/other-accounts/", token: token)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func add(_ req: OtherAccountRequest, token: String) async -> Bool {
        do {
            let _: OtherAccount = try await APIClient.shared.post("/finance/other-accounts/", body: req, token: token)
            await load(token: token)
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func delete(_ a: OtherAccount, token: String) async {
        do {
            try await APIClient.shared.delete("/finance/other-accounts/\(a.id)/", token: token)
            await load(token: token)
        } catch { self.error = error.localizedDescription }
    }
}

struct OtherAccountsView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = OtherAccountsViewModel()
    @State private var showAdd = false
    private var token: String { auth.accessToken ?? "" }

    var body: some View {
        List {
            Section {
                Text("Assets and debts beyond cash, investments, and loans — your home value, vehicles, and credit cards (cards sync from YNAB).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            section("Assets", vm.assets, .green)
            section("Liabilities", vm.liabilities, .red)
        }
        .navigationTitle("Assets & Debts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddOtherAccountSheet { req in await vm.add(req, token: token) }
        }
        .task { await vm.load(token: token) }
        .refreshable { await vm.load(token: token) }
        .alert("Error", isPresented: .init(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK") {}
        } message: { Text(vm.error ?? "") }
    }

    @ViewBuilder private func section(_ title: String, _ items: [OtherAccount], _ color: Color) -> some View {
        Section(title) {
            if items.isEmpty {
                Text("None").foregroundStyle(.secondary)
            }
            ForEach(items) { a in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.name).font(.subheadline)
                        Text(a.category.replacingOccurrences(of: "_", with: " ").capitalized
                             + (a.source == "ynab" ? " · YNAB" : ""))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text((title == "Liabilities" ? "−" : "") + LoanFormatters.money(a.value, fractionDigits: 0))
                        .font(.subheadline).fontWeight(.medium).foregroundStyle(color)
                }
                .swipeActions {
                    if a.source != "ynab" {
                        Button(role: .destructive) { Task { await vm.delete(a, token: token) } } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }
}

struct AddOtherAccountSheet: View {
    let onSave: (OtherAccountRequest) async -> Bool
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kind = "asset"
    @State private var category = "real_estate"
    @State private var value: Double = 0
    @State private var saving = false

    private let assetCats = [("real_estate", "Real Estate"), ("vehicle", "Vehicle"), ("cash", "Cash"), ("other", "Other")]
    private let liabilityCats = [("mortgage", "Mortgage"), ("credit_card", "Credit Card"), ("other", "Other")]
    private var cats: [(String, String)] { kind == "asset" ? assetCats : liabilityCats }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name (e.g. House)", text: $name)
                Picker("Type", selection: $kind) {
                    Text("Asset").tag("asset")
                    Text("Liability").tag("liability")
                }
                .pickerStyle(.segmented)
                Picker("Category", selection: $category) {
                    ForEach(cats, id: \.0) { Text($0.1).tag($0.0) }
                }
                HStack {
                    Text("Value")
                    Spacer()
                    TextField("Value", value: $value, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
            }
            .navigationTitle("Add Asset / Debt")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: kind) { category = cats.first?.0 ?? "other" }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            saving = true
                            let req = OtherAccountRequest(
                                name: name.isEmpty ? "Untitled" : name,
                                kind: kind, category: category, value: value
                            )
                            let ok = await onSave(req)
                            saving = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(saving || value <= 0)
                }
            }
        }
    }
}
