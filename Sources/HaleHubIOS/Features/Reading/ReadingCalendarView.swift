import SwiftUI

// MARK: - ViewModel

@MainActor
class ReadingCalendarViewModel: ObservableObject {
    @Published var monthDays: [ReadingDay] = []
    @Published var isLoading = false
    @Published var error: String?

    var year: Int
    var month: Int
    let plan: ReadingPlanSummary

    init(plan: ReadingPlanSummary) {
        self.plan = plan
        let now = Calendar.current.dateComponents([.year, .month], from: Date())
        self.year = now.year ?? Calendar.current.component(.year, from: Date())
        self.month = now.month ?? Calendar.current.component(.month, from: Date())
    }

    func load(token: String) async {
        isLoading = true
        error = nil
        do {
            let r: MonthDaysResponse = try await APIClient.shared.get(
                "/reading/plans/\(plan.id)/days/?year=\(year)&month=\(month)",
                token: token
            )
            monthDays = r.days
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func prevMonth(token: String) async {
        if month == 1 { year -= 1; month = 12 } else { month -= 1 }
        await load(token: token)
    }

    func nextMonth(token: String) async {
        if month == 12 { year += 1; month = 1 } else { month += 1 }
        await load(token: token)
    }

    // Map from "YYYY-MM-DD" string to ReadingDay
    var daysByDate: [String: ReadingDay] {
        Dictionary(uniqueKeysWithValues: monthDays.map { ($0.date, $0) })
    }
}

// MARK: - Calendar Cell Model

private enum CalendarCell {
    case empty
    case outside(dayOfMonth: Int)
    case planDay(dayOfMonth: Int, dayNumber: Int, dateStr: String, isCompleted: Bool, isOverdue: Bool, entryCount: Int)
}

// MARK: - View

struct ReadingCalendarView: View {
    @EnvironmentObject var auth: AuthManager
    let plan: ReadingPlanSummary

    @StateObject private var vm: ReadingCalendarViewModel

    init(plan: ReadingPlanSummary) {
        self.plan = plan
        _vm = StateObject(wrappedValue: ReadingCalendarViewModel(plan: plan))
    }

    // Weekday column headers (Sunday-first Gregorian)
    private let weekdayLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        Group {
            if vm.isLoading && vm.monthDays.isEmpty {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                calendarContent
            }
        }
        .navigationTitle(monthTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load(token: auth.accessToken ?? "") }
        .overlay {
            if vm.isLoading && !vm.monthDays.isEmpty {
                Color.black.opacity(0.15).ignoresSafeArea()
                ProgressView()
                    .padding(20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Month Title

    private var monthTitle: String {
        var comps = DateComponents()
        comps.year = vm.year
        comps.month = vm.month
        comps.day = 1
        guard let date = Calendar.current.date(from: comps) else {
            return "\(vm.month)/\(vm.year)"
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        return fmt.string(from: date)
    }

    // MARK: - Calendar Content

    private var calendarContent: some View {
        VStack(spacing: 0) {
            // Navigation bar
            monthNavBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground))

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    // Weekday header row
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(weekdayLabels, id: \.self) { label in
                            Text(label)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    // Calendar grid
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(Array(buildCalendarCells().enumerated()), id: \.offset) { _, cell in
                            cellView(for: cell)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 20)
                }
            }
        }
    }

    // MARK: - Month Nav Bar

    private var monthNavBar: some View {
        HStack(spacing: 12) {
            Button {
                Task { await vm.prevMonth(token: auth.accessToken ?? "") }
            } label: {
                Label("Prev", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.bordered)
            .disabled(isPrevDisabled)

            Spacer()

            Text(monthTitle)
                .font(.subheadline)
                .fontWeight(.semibold)

            Spacer()

            Button {
                Task { await vm.nextMonth(token: auth.accessToken ?? "") }
            } label: {
                Label("Next", systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.bordered)
            .disabled(isNextDisabled)
        }
    }

    // Disable prev if we're at or before the plan's start month
    private var isPrevDisabled: Bool {
        guard let start = planDate(from: plan.startDate) else { return false }
        let startComps = Calendar.current.dateComponents([.year, .month], from: start)
        if vm.year < (startComps.year ?? 0) { return true }
        if vm.year == (startComps.year ?? 0) && vm.month <= (startComps.month ?? 1) { return true }
        return false
    }

    // Disable next if we're more than 2 years ahead of today
    private var isNextDisabled: Bool {
        let now = Calendar.current.dateComponents([.year, .month], from: Date())
        let maxYear = (now.year ?? vm.year) + 2
        return vm.year >= maxYear
    }

    // MARK: - Cell View

    @ViewBuilder
    private func cellView(for cell: CalendarCell) -> some View {
        switch cell {
        case .empty:
            Color.clear
                .frame(height: 52)

        case .outside(let dayOfMonth):
            VStack(spacing: 2) {
                Text("\(dayOfMonth)")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(.systemGray3))
                Spacer(minLength: 0)
            }
            .frame(height: 52)

        case .planDay(let dayOfMonth, let dayNumber, let dateStr, let isCompleted, let isOverdue, let entryCount):
            let isToday = dateStr == todayString
            NavigationLink(destination:
                ReadingDayDetailView(
                    planId: plan.id,
                    dayNumber: dayNumber,
                    dateString: dateStr
                )
                .environmentObject(auth)
            ) {
                PlanDayCell(
                    dayOfMonth: dayOfMonth,
                    isCompleted: isCompleted,
                    isOverdue: isOverdue,
                    isToday: isToday,
                    entryCount: entryCount
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Grid Builder

    private func buildCalendarCells() -> [CalendarCell] {
        var cells: [CalendarCell] = []
        let calendar = Calendar.current

        let planStartDate = planDate(from: plan.startDate)
        let planEndDate = planDate(from: plan.endDate)

        var comps = DateComponents()
        comps.year = vm.year
        comps.month = vm.month
        comps.day = 1
        guard let firstDay = calendar.date(from: comps) else { return [] }

        let range = calendar.range(of: .day, in: .month, for: firstDay)!
        let daysInMonth = range.count

        // Offset: weekday of first day (1=Sun in Gregorian) → 0-based
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let offset = firstWeekday - 1

        // Padding before month starts
        for _ in 0..<offset { cells.append(.empty) }

        for dayOfMonth in 1...daysInMonth {
            comps.day = dayOfMonth
            guard let cellDate = calendar.date(from: comps) else { continue }

            let dateStr = isoString(from: cellDate)
            let inPlan = planStartDate != nil && planEndDate != nil
                && cellDate >= planStartDate! && cellDate <= planEndDate!

            if inPlan {
                let planDay = vm.daysByDate[dateStr]
                let dayNum = planDayNumber(for: cellDate, startDate: planStartDate!)
                let isPast = cellDate < noonToday
                cells.append(.planDay(
                    dayOfMonth: dayOfMonth,
                    dayNumber: dayNum,
                    dateStr: dateStr,
                    isCompleted: planDay?.isCompleted ?? false,
                    isOverdue: !(planDay?.isCompleted ?? false) && isPast,
                    entryCount: planDay?.entries.count ?? 0
                ))
            } else {
                cells.append(.outside(dayOfMonth: dayOfMonth))
            }
        }

        // Pad end to complete last row
        while cells.count % 7 != 0 { cells.append(.empty) }
        return cells
    }

    // MARK: - Helpers

    private var todayString: String { isoString(from: Date()) }

    private var noonToday: Date {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        return cal.date(byAdding: .hour, value: 12, to: start) ?? Date()
    }

    private func planDate(from str: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: str)
    }

    private func isoString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func planDayNumber(for date: Date, startDate: Date) -> Int {
        let days = Calendar.current.dateComponents([.day], from: startDate, to: date).day ?? 0
        return days + 1
    }
}

// MARK: - Plan Day Cell

private struct PlanDayCell: View {
    let dayOfMonth: Int
    let isCompleted: Bool
    let isOverdue: Bool
    let isToday: Bool
    let entryCount: Int

    private var circleColor: Color {
        if isCompleted { return .green }
        if isToday { return .blue }
        return .clear
    }

    private var borderColor: Color {
        if isCompleted { return .clear }
        if isToday { return .blue }
        if isOverdue { return .orange }
        return Color(.systemGray4)
    }

    private var borderWidth: CGFloat {
        isOverdue ? 2 : 1
    }

    private var textColor: Color {
        if isCompleted { return .white }
        if isToday { return .white }
        if isOverdue { return .orange }
        return .primary
    }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(circleColor)
                    .overlay(
                        Circle().strokeBorder(borderColor, lineWidth: borderWidth)
                    )
                    .frame(width: 34, height: 34)

                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(dayOfMonth)")
                        .font(.system(size: 13, weight: isToday ? .bold : .regular))
                        .foregroundStyle(textColor)
                }
            }

            // Entry count badge
            if entryCount > 0 {
                Text("\(entryCount)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isCompleted ? .green : Color.accentColor)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(isCompleted ? Color.green.opacity(0.12) : Color.accentColor.opacity(0.12))
                    )
            } else {
                Color.clear.frame(height: 14)
            }
        }
        .frame(height: 52)
    }
}
