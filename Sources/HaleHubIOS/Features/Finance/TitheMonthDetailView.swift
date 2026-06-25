import SwiftUI

@MainActor
final class TitheMonthDetailViewModel: ObservableObject {
    @Published var detail: TitheMonthDetail?
    @Published var isLoading = false
    @Published var error: String?

    let year: Int
    let month: Int

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    func load(token: String) async {
        isLoading = true
        error = nil
        do {
            detail = try await APIClient.shared.get(
                "/finance/tithe/month/?year=\(year)&month=\(month)", token: token)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

struct TitheMonthDetailView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm: TitheMonthDetailViewModel

    private var token: String { auth.accessToken ?? "" }

    init(year: Int, month: Int) {
        _vm = StateObject(wrappedValue: TitheMonthDetailViewModel(year: year, month: month))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if let d = vm.detail {
                    headerCard(d)
                    givingSection(d)
                    paychecksSection(d)
                } else if vm.isLoading {
                    ProgressView("Loading…").frame(maxWidth: .infinity, minHeight: 160)
                }
            }
            .padding(16)
        }
        .navigationTitle(monthLabel)
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load(token: token) }
        .refreshable { await vm.load(token: token) }
        .alert("Error", isPresented: .init(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK") {}
        } message: { Text(vm.error ?? "") }
    }

    // MARK: - Header

    private func headerCard(_ d: TitheMonthDetail) -> some View {
        VStack(spacing: 10) {
            HStack {
                stat("Given", LoanFormatters.money(d.given, fractionDigits: 0), .green)
                Spacer()
                stat("Goal", LoanFormatters.money(d.target, fractionDigits: 0), .secondary)
                Spacer()
                stat(d.remaining <= 0 ? "Surplus" : "Remaining",
                     LoanFormatters.money(abs(d.remaining), fractionDigits: 0),
                     d.remaining <= 0 ? .green : .orange)
            }
            Divider()
            Text("Your goal is \(String(format: "%.1f", d.percentage))% of \(LoanFormatters.money(d.gross, fractionDigits: 0)) gross pay this month.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).foregroundStyle(color)
        }
    }

    // MARK: - Giving

    private func givingSection(_ d: TitheMonthDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Given", systemImage: "hands.sparkles.fill",
                          subtitle: d.givingCategory.isEmpty
                            ? "Donations that counted toward what you've given."
                            : "Donations in “\(d.givingCategory)” that counted toward what you've given.")
            if d.giving.isEmpty {
                emptyRow("No giving recorded this month.")
            } else {
                ForEach(d.giving) { g in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(g.payee.isEmpty ? "Donation" : g.payee)
                                .font(.subheadline).fontWeight(.medium)
                            Text([prettyDate(g.date), g.recipient].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption2).foregroundStyle(.secondary)
                            if !g.memo.isEmpty {
                                Text(g.memo).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        Text(LoanFormatters.money(g.amount, fractionDigits: 2))
                            .font(.subheadline).fontWeight(.semibold).foregroundStyle(.green)
                    }
                    .padding(.vertical, 2)
                    Divider()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Paychecks

    private func paychecksSection(_ d: TitheMonthDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Paychecks", systemImage: "dollarsign.circle.fill",
                          subtitle: "The income these paychecks add up to is what your goal is based on.")
            if d.paychecks.isEmpty {
                emptyRow("No paychecks recorded this month.")
            } else {
                ForEach(d.paychecks) { p in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text([p.employer, p.recipient].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.subheadline).fontWeight(.medium)
                            Text(prettyDate(p.payDate)).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(LoanFormatters.money(p.grossPay, fractionDigits: 0))
                                .font(.subheadline).fontWeight(.semibold)
                            Text("gross").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                    Divider()
                }
                HStack {
                    Text("Total gross").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                    Spacer()
                    Text(LoanFormatters.money(d.gross, fractionDigits: 0))
                        .font(.subheadline).fontWeight(.bold)
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, systemImage: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
    }

    private var monthLabel: String {
        var comps = DateComponents(); comps.year = vm.year; comps.month = vm.month; comps.day = 1
        guard let d = Calendar.current.date(from: comps) else { return "\(vm.year)-\(vm.month)" }
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return f.string(from: d)
    }

    /// "2026-05-12" → "May 12"
    private func prettyDate(_ iso: String) -> String {
        let parts = iso.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let day = Int(parts[2]) else { return iso }
        var comps = DateComponents(); comps.year = y; comps.month = m; comps.day = day
        guard let d = Calendar.current.date(from: comps) else { return iso }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: d)
    }
}
