import SwiftUI

@MainActor
final class BudgetViewModel: ObservableObject {
    @Published var data: BudgetMonthData?
    @Published var isLoading = false
    @Published var error: String?
    @Published var year: Int
    @Published var month: Int

    init() {
        let comps = Calendar.current.dateComponents([.year, .month], from: Date())
        year = comps.year ?? 2026
        month = comps.month ?? 1
    }

    func load(token: String) async {
        isLoading = true
        error = nil
        do {
            let m = String(format: "%04d-%02d", year, month)
            data = try await APIClient.shared.get("/finance/budget/?month=\(m)", token: token)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func step(_ delta: Int) {
        var m = month + delta
        var y = year
        while m > 12 { m -= 12; y += 1 }
        while m < 1 { m += 12; y -= 1 }
        month = m; year = y
    }

    var monthLabel: String {
        var comps = DateComponents(); comps.year = year; comps.month = month; comps.day = 1
        guard let d = Calendar.current.date(from: comps) else { return "\(year)-\(month)" }
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return f.string(from: d)
    }
}

struct BudgetView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = BudgetViewModel()
    @State private var showPicker = false

    private var token: String { auth.accessToken ?? "" }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                monthSelector
                if let data = vm.data {
                    if data.groups.isEmpty {
                        ContentUnavailableView(
                            "No Budget Data",
                            systemImage: "chart.pie",
                            description: Text("Nothing imported for this month yet. Connect YNAB and sync.")
                        )
                        .frame(minHeight: 160)
                    } else {
                        totalsCard(data.totals)
                        ForEach(data.groups) { group in
                            groupCard(group)
                        }
                    }
                } else if vm.isLoading {
                    ProgressView("Loading…").frame(maxWidth: .infinity, minHeight: 160)
                }
            }
            .padding(16)
        }
        .navigationTitle("Budget")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: YNABSettingsView()) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
            }
        }
        .task { await vm.load(token: token) }
        .onChange(of: vm.year) { Task { await vm.load(token: token) } }
        .onChange(of: vm.month) { Task { await vm.load(token: token) } }
        .refreshable { await vm.load(token: token) }
        .sheet(isPresented: $showPicker) {
            MonthYearPickerSheet(year: $vm.year, month: $vm.month)
                .presentationDetents([.height(280)])
        }
        .alert("Error", isPresented: .init(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK") {}
        } message: { Text(vm.error ?? "") }
    }

    private var monthSelector: some View {
        HStack {
            Button { vm.step(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Button { showPicker = true } label: {
                HStack(spacing: 4) {
                    Text(vm.monthLabel).font(.headline)
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .foregroundStyle(.primary)
            }
            Spacer()
            Button { vm.step(1) } label: { Image(systemName: "chevron.right") }
        }
        .padding(.horizontal, 4)
    }

    private func totalsCard(_ t: BudgetTotals) -> some View {
        HStack {
            totalPillar("Budgeted", t.budgeted)
            Spacer()
            totalPillar("Activity", t.activity)
            Spacer()
            totalPillar("Available", t.available)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func totalPillar(_ label: String, _ value: Double) -> some View {
        VStack(spacing: 4) {
            Text(LoanFormatters.money(value, fractionDigits: 0))
                .font(.headline)
                .foregroundStyle(label == "Available" ? (value < 0 ? .red : .green) : .primary)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func groupCard(_ group: BudgetGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(group.group).font(.headline)
                Spacer()
                Text(LoanFormatters.money(group.available, fractionDigits: 0))
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(group.available < 0 ? .red : .secondary)
            }
            ForEach(group.categories) { cat in
                HStack {
                    Text(cat.category).font(.subheadline)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(LoanFormatters.money(cat.available, fractionDigits: 0))
                            .font(.subheadline)
                            .foregroundStyle(cat.available < 0 ? .red : .primary)
                        Text("of \(LoanFormatters.money(cat.budgeted, fractionDigits: 0))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
                Divider()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Reusable month/year picker

struct MonthYearPickerSheet: View {
    @Binding var year: Int
    @Binding var month: Int
    @Environment(\.dismiss) private var dismiss

    private let monthNames = DateFormatter().monthSymbols ?? [
        "January","February","March","April","May","June",
        "July","August","September","October","November","December",
    ]
    private var years: [Int] {
        let cur = Calendar.current.component(.year, from: Date())
        return Array(((cur - 15)...(cur + 1))).reversed()
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                Picker("Month", selection: $month) {
                    ForEach(1...12, id: \.self) { Text(monthNames[$0 - 1]).tag($0) }
                }
                .pickerStyle(.wheel)
                Picker("Year", selection: $year) {
                    ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                }
                .pickerStyle(.wheel)
            }
            .navigationTitle("Jump to month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
