import SwiftUI

@MainActor
final class ReconciliationViewModel: ObservableObject {
    @Published var data: ReconciliationResponse?
    @Published var isLoading = false
    @Published var error: String?
    @Published var year: Int = Calendar.current.component(.year, from: Date())

    func load(token: String) async {
        isLoading = true
        error = nil
        do {
            data = try await APIClient.shared.get(
                "/finance/reconciliation/?year=\(year)",
                token: token
            )
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

struct ReconciliationView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = ReconciliationViewModel()

    private var token: String { auth.accessToken ?? "" }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                yearPicker
                if vm.isLoading && vm.data == nil {
                    ProgressView("Loading…").frame(maxWidth: .infinity, minHeight: 200)
                } else if let err = vm.error {
                    ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(err))
                } else if let d = vm.data {
                    summaryCard(d)
                    rowsList(d)
                } else {
                    ContentUnavailableView("No Data", systemImage: "magnifyingglass", description: Text("No reconciliation data for \(vm.year)"))
                }
            }
            .padding(16)
        }
        .navigationTitle("Reconciliation")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load(token: token) }
        .refreshable { await vm.load(token: token) }
    }

    // MARK: - Year picker

    private var yearPicker: some View {
        HStack {
            Text("Year").font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Picker("Year", selection: $vm.year) {
                if let years = vm.data?.availableYears, !years.isEmpty {
                    ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                } else {
                    Text(String(vm.year)).tag(vm.year)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: vm.year) { _, _ in
                Task { await vm.load(token: token) }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Summary card

    private func summaryCard(_ d: ReconciliationResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Summary").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    statTile("Matched", "\(d.matchedCount)", .green)
                    statTile("YNAB Only", "\(d.ynabOnlyCount)", .orange)
                    statTile("PC Only", "\(d.pcOnlyCount)", .red)
                }
                GridRow {
                    statTile("Matched YNAB", fmtDollars(d.totals.matchedYnab), .primary)
                    statTile("Matched PC Net", fmtDollars(d.totals.matchedPcNet), .primary)
                    Spacer()
                }
            }
            let diff = d.totals.matchedYnab - d.totals.matchedPcNet
            HStack {
                Text("Difference")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(fmtDollars(abs(diff)))
                    .font(.subheadline)
                    .foregroundStyle(abs(diff) < 1 ? .green : .orange)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func statTile(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Rows list

    private func rowsList(_ d: ReconciliationResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transactions").font(.headline)
            ForEach(d.rows) { row in
                rowCard(row)
            }
        }
    }

    private func rowCard(_ row: ReconciliationRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                kindBadge(row.kind)
                Spacer()
                Text(formatDate(row.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if row.kind == "matched" {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.pcEmployer ?? "—").font(.subheadline).fontWeight(.medium)
                        if let earner = row.pcEarner, !earner.isEmpty {
                            Text(earner).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("YNAB: \(fmtDollars(row.ynabAmount ?? 0))").font(.subheadline)
                        Text("PC Net: \(fmtDollars(row.pcNet ?? 0))").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let diff = row.amountDiff, abs(diff) > 0.01 {
                    HStack {
                        if let days = row.dateDiff, days != 0 {
                            Text("\(days > 0 ? "+" : "")\(days)d offset")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("Δ \(fmtDollars(abs(diff)))")
                            .font(.caption2)
                            .foregroundStyle(abs(diff) < 50 ? .secondary : .orange)
                    }
                }
            } else if row.kind == "ynab_only" {
                HStack {
                    Text("YNAB deposit — no matching paycheck")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(fmtDollars(row.ynabAmount ?? 0)).font(.subheadline)
                }
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.pcEmployer ?? "—").font(.subheadline).fontWeight(.medium)
                        if let earner = row.pcEarner, !earner.isEmpty {
                            Text(earner).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(fmtDollars(row.pcNet ?? 0)).font(.subheadline)
                        Text("No YNAB deposit").font(.caption).foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func kindBadge(_ kind: String) -> some View {
        let (label, color): (String, Color) = switch kind {
        case "matched":       ("Matched", .green)
        case "ynab_only":     ("YNAB Only", .orange)
        default:              ("PC Only", .red)
        }
        return Text(label)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    // MARK: - Helpers

    private func fmtDollars(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }

    private func formatDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        guard let d = f.date(from: iso) else { return iso }
        let out = DateFormatter()
        out.dateFormat = "MMM d"
        return out.string(from: d)
    }
}
