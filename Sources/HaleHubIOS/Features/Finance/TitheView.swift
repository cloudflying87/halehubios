import SwiftUI
import Charts

@MainActor
final class TitheViewModel: ObservableObject {
    @Published var summary: TitheSummary?
    @Published var settings: TitheSettingsData?
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
            summary = try await APIClient.shared.get("/finance/tithe/?year=\(year)&month=\(month)", token: token)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func loadSettings(token: String) async {
        do {
            settings = try await APIClient.shared.get("/finance/tithe/settings/", token: token)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func saveSettings(percentage: Double, category: String, token: String) async -> Bool {
        do {
            let req = TitheSettingsRequest(percentage: percentage, givingCategory: category)
            let updated: TitheSettingsData = try await APIClient.shared.put("/finance/tithe/settings/", body: req, token: token)
            settings = updated
            await load(token: token)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func step(_ delta: Int) {
        var m = month + delta
        var y = year
        while m > 12 { m -= 12; y += 1 }
        while m < 1 { m += 12; y -= 1 }
        month = m
        year = y
    }

    var monthLabel: String {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        guard let date = Calendar.current.date(from: comps) else { return "\(year)-\(month)" }
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: date)
    }
}

struct TitheView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = TitheViewModel()
    @State private var showSettings = false

    private var token: String { auth.accessToken ?? "" }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                monthSelector
                if let s = vm.summary {
                    if !s.configured {
                        setupPrompt
                    }
                    summaryCard(s)
                    if let years = s.years, !years.isEmpty {
                        yearBreakdown(years)
                    }
                    if !s.history.isEmpty {
                        historyChart(s.history)
                        historyList(s.history)
                    }
                } else if vm.isLoading {
                    ProgressView("Loading…").frame(maxWidth: .infinity, minHeight: 160)
                }
            }
            .padding(16)
        }
        .navigationTitle("Tithe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
        }
        .sheet(isPresented: $showSettings) {
            TitheSettingsSheet(vm: vm)
        }
        .task {
            await vm.load(token: token)
            await vm.loadSettings(token: token)
        }
        .onChange(of: vm.year) { Task { await vm.load(token: token) } }
        .onChange(of: vm.month) { Task { await vm.load(token: token) } }
        .refreshable { await vm.load(token: token) }
        .alert("Error", isPresented: .init(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK") {}
        } message: { Text(vm.error ?? "") }
    }

    private var monthSelector: some View {
        HStack {
            Button { vm.step(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(vm.monthLabel).font(.headline)
            Spacer()
            Button { vm.step(1) } label: { Image(systemName: "chevron.right") }
        }
        .padding(.horizontal, 4)
    }

    private var setupPrompt: some View {
        Button { showSettings = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                Text("Set your tithe % and giving category to track giving.")
                    .font(.subheadline).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func summaryCard(_ s: TitheSummary) -> some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 20) {
                Gauge(value: max(0, min(1, s.target > 0 ? s.given / s.target : 0))) {
                    EmptyView()
                } currentValueLabel: {
                    Text("\(Int(s.pctGiven.rounded()))%")
                        .font(.headline)
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(s.remaining <= 0 ? .green : .accentColor)

                VStack(alignment: .leading, spacing: 6) {
                    titheStat("Given", LoanFormatters.money(s.given, fractionDigits: 0), .green)
                    titheStat("Goal", LoanFormatters.money(s.target, fractionDigits: 0), .secondary)
                    titheStat(s.remaining <= 0 ? "Surplus" : "Remaining",
                              LoanFormatters.money(abs(s.remaining), fractionDigits: 0),
                              s.remaining <= 0 ? .green : .orange)
                }
                Spacer()
            }
            Divider()
            HStack {
                Text("\(String(format: "%.1f", s.percentage))% of \(LoanFormatters.money(s.gross, fractionDigits: 0)) gross")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !s.givingCategory.isEmpty {
                    Text(s.givingCategory).font(.caption2)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.15)).clipShape(Capsule())
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func titheStat(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 78, alignment: .leading)
            Text(value).font(.subheadline).fontWeight(.semibold).foregroundStyle(color)
        }
    }

    private func yearBreakdown(_ years: [TitheYearPoint]) -> some View {
        let totalGiven = years.reduce(0) { $0 + $1.given }
        let totalTarget = years.reduce(0) { $0 + $1.target }
        let totalRemaining = totalTarget - totalGiven
        return VStack(alignment: .leading, spacing: 10) {
            Text("By Year").font(.headline)
            ForEach(years) { y in
                HStack(alignment: .firstTextBaseline) {
                    Text(String(y.year)).font(.subheadline).fontWeight(.medium)
                        .frame(width: 56, alignment: .leading)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(LoanFormatters.money(y.given, fractionDigits: 0)) / \(LoanFormatters.money(y.target, fractionDigits: 0))")
                            .font(.subheadline)
                        if y.target > 0 {
                            Text(y.remaining <= 0 ? "Met (\(Int(y.pctGiven.rounded()))%)" : "\(LoanFormatters.money(y.remaining, fractionDigits: 0)) to go")
                                .font(.caption2)
                                .foregroundStyle(y.remaining <= 0 ? .green : .orange)
                        } else {
                            Text("no paychecks yet").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 3)
                Divider()
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Total").font(.subheadline).fontWeight(.bold).frame(width: 56, alignment: .leading)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(LoanFormatters.money(totalGiven, fractionDigits: 0)) / \(LoanFormatters.money(totalTarget, fractionDigits: 0))")
                        .font(.subheadline).fontWeight(.bold)
                    if totalTarget > 0 {
                        Text(totalRemaining <= 0 ? "Surplus \(LoanFormatters.money(-totalRemaining, fractionDigits: 0))" : "\(LoanFormatters.money(totalRemaining, fractionDigits: 0)) to go")
                            .font(.caption2)
                            .foregroundStyle(totalRemaining <= 0 ? .green : .orange)
                    }
                }
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func historyChart(_ history: [TitheMonthPoint]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Given vs Goal").font(.headline)
            Chart {
                ForEach(history) { point in
                    BarMark(x: .value("Month", shortMonth(point.month)), y: .value("Given", point.given), width: .ratio(0.5))
                        .foregroundStyle(Color.green)
                        .position(by: .value("Type", "Given"))
                    BarMark(x: .value("Month", shortMonth(point.month)), y: .value("Goal", point.target), width: .ratio(0.5))
                        .foregroundStyle(Color.accentColor.opacity(0.5))
                        .position(by: .value("Type", "Goal"))
                }
            }
            .chartLegend(position: .bottom)
            .frame(height: 200)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func historyList(_ history: [TitheMonthPoint]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Monthly Breakdown").font(.headline)
            ForEach(history.reversed()) { p in
                NavigationLink {
                    monthDetail(for: p.month)
                } label: {
                    HStack {
                        Text(longMonth(p.month)).font(.subheadline).frame(width: 110, alignment: .leading)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(LoanFormatters.money(p.given, fractionDigits: 0)) / \(LoanFormatters.money(p.target, fractionDigits: 0))")
                                .font(.subheadline)
                            if p.target > 0 {
                                Text(p.remaining <= 0 ? "Met" : "\(LoanFormatters.money(p.remaining, fractionDigits: 0)) to go")
                                    .font(.caption2)
                                    .foregroundStyle(p.remaining <= 0 ? .green : .orange)
                            }
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)
                Divider()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func monthDetail(for ym: String) -> some View {
        let parts = ym.split(separator: "-")
        if parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) {
            TitheMonthDetailView(year: y, month: m)
        } else {
            EmptyView()
        }
    }

    private func shortMonth(_ ym: String) -> String {
        // "2025-11" → "Nov" (unique across 12 consecutive months)
        let parts = ym.split(separator: "-")
        guard parts.count == 2, let m = Int(parts[1]) else { return ym }
        let symbols = DateFormatter().shortMonthSymbols ?? []
        return (1...12).contains(m) ? symbols[m - 1] : ym
    }

    private func longMonth(_ ym: String) -> String {
        let parts = ym.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) else { return ym }
        var comps = DateComponents(); comps.year = y; comps.month = m; comps.day = 1
        guard let d = Calendar.current.date(from: comps) else { return ym }
        let f = DateFormatter(); f.dateFormat = "MMM yyyy"
        return f.string(from: d)
    }
}

// MARK: - Settings Sheet

struct TitheSettingsSheet: View {
    @ObservedObject var vm: TitheViewModel
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var percentage: Double = 10
    @State private var category: String = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Tithe Percentage") {
                    HStack {
                        Text("Percentage")
                        Spacer()
                        TextField("10", value: $percentage, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        Text("%").foregroundStyle(.secondary)
                    }
                }
                Section("Giving Category") {
                    if let available = vm.settings?.availableCategories, !available.isEmpty {
                        Picker("Category", selection: $category) {
                            Text("None").tag("")
                            ForEach(available, id: \.self) { Text($0).tag($0) }
                        }
                    } else {
                        TextField("e.g. Give Away", text: $category)
                    }
                    Text("Transactions in this category count toward what you've given.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Tithe Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            saving = true
                            let ok = await vm.saveSettings(percentage: percentage, category: category, token: auth.accessToken ?? "")
                            saving = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(saving)
                }
            }
            .onAppear {
                if let s = vm.settings {
                    percentage = s.percentage
                    category = s.givingCategory
                } else if let sum = vm.summary {
                    percentage = sum.percentage > 0 ? sum.percentage : 10
                    category = sum.givingCategory
                }
            }
        }
    }
}
