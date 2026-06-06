import SwiftUI

@MainActor
class WeeklyReportViewModel: ObservableObject {
    @Published var report: WeeklyReport?
    @Published var isLoading = false
    @Published var error: String?

    /// Offset in weeks from the current week (0 = this week, -1 = last week).
    @Published var weekOffset = 0

    func load(token: String) async {
        isLoading = true
        error = nil
        let week = weekStartString(offset: weekOffset)
        do {
            let resp: WeeklyReport = try await APIClient.shared.get(
                "/babysitters/report/weekly/?week=\(week)", token: token)
            report = resp
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    /// Sunday of the target week as "YYYY-MM-DD".
    private func weekStartString(offset: Int) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 1 // Sunday
        let today = Date()
        let startOfWeek = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let target = cal.date(byAdding: .weekOfYear, value: offset, to: startOfWeek) ?? startOfWeek
        return BabysitterFormat.ymdString(target)
    }
}

struct WeeklyReportView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = WeeklyReportViewModel()

    private var token: String { auth.accessToken ?? "" }

    var body: some View {
        List {
            Section {
                HStack {
                    Button { Task { vm.weekOffset -= 1; await vm.load(token: token) } } label: {
                        Image(systemName: "chevron.left")
                    }
                    Spacer()
                    Text(vm.report?.weekLabel ?? "…")
                        .font(.headline)
                    Spacer()
                    Button { Task { vm.weekOffset += 1; await vm.load(token: token) } } label: {
                        Image(systemName: "chevron.right")
                    }
                }
                .buttonStyle(.borderless)

                if let r = vm.report {
                    LabeledContent("Total owed", value: BabysitterFormat.money(r.grandTotalOwed))
                    LabeledContent("Unpaid", value: BabysitterFormat.money(r.grandUnpaidOwed))
                }
            }

            if let r = vm.report {
                ForEach(r.perSitter) { bucket in
                    Section(bucket.babysitterName) {
                        ForEach(bucket.sessions) { s in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.dateDisplay).font(.subheadline)
                                    Text("\(s.timeRange) · \(s.durationDisplay)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(s.amountDisplay)
                                    .foregroundStyle(s.isPaid ? .green : .primary)
                            }
                        }
                        HStack {
                            Text("Total").font(.subheadline.bold())
                            Spacer()
                            Text(BabysitterFormat.money(bucket.totalOwed)).font(.subheadline.bold())
                        }
                    }
                }
                if r.perSitter.isEmpty {
                    Section { Text("No sessions this week.").foregroundStyle(.secondary) }
                }
            } else if vm.isLoading {
                Section { ProgressView() }
            } else if let msg = vm.error {
                Section { Text(msg).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Weekly Report")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load(token: token) }
        .refreshable { await vm.load(token: token) }
    }
}
