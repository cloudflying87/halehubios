import SwiftUI

// MARK: - ViewModel

@MainActor
class ReadingViewModel: ObservableObject {
    @Published var plans: [ReadingPlanSummary] = []
    @Published var primaryPlanDetail: ReadingPlanDetail?
    @Published var isLoading = false
    @Published var error: String?

    func load(token: String) async {
        isLoading = true
        error = nil
        do {
            let fetched: [ReadingPlanSummary] = try await APIClient.shared.get(
                "/reading/plans/", token: token
            )
            plans = fetched

            if let primary = fetched.first(where: { $0.isPrimary }) ?? fetched.first {
                let detail: ReadingPlanDetail = try await APIClient.shared.get(
                    "/reading/plans/\(primary.id)/", token: token
                )
                primaryPlanDetail = detail
            } else {
                primaryPlanDetail = nil
            }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func toggleDay(planId: String, dayNum: Int, token: String) async {
        // Optimistic UI update before the network call
        if let detail = primaryPlanDetail, let today = detail.todayDay, today.dayNumber == dayNum {
            let nowCompleted = !today.isCompleted
            let updatedDay = ReadingDay(
                dayNumber: today.dayNumber,
                date: today.date,
                isCompleted: nowCompleted,
                entries: today.entries,
                notes: today.notes
            )
            primaryPlanDetail = ReadingPlanDetail(
                id: detail.id,
                name: detail.name,
                startDate: detail.startDate,
                endDate: detail.endDate,
                totalDays: detail.totalDays,
                daysCompleted: detail.daysCompleted + (nowCompleted ? 1 : -1),
                completionPercentage: detail.completionPercentage,
                currentDayNumber: detail.currentDayNumber,
                daysBehind: detail.daysBehind,
                isPrimary: detail.isPrimary,
                isActive: detail.isActive,
                todayDay: updatedDay,
                recentDays: detail.recentDays
            )
        }

        do {
            let response: ReadingToggleResponse = try await APIClient.shared.postEmpty(
                "/reading/plans/\(planId)/days/\(dayNum)/toggle/", token: token
            )
            // Apply authoritative server response
            if let detail = primaryPlanDetail {
                let updatedToday: ReadingDay?
                if let today = detail.todayDay {
                    updatedToday = ReadingDay(
                        dayNumber: today.dayNumber,
                        date: today.date,
                        isCompleted: response.isCompleted,
                        entries: today.entries,
                        notes: today.notes
                    )
                } else {
                    updatedToday = nil
                }
                primaryPlanDetail = ReadingPlanDetail(
                    id: detail.id,
                    name: detail.name,
                    startDate: detail.startDate,
                    endDate: detail.endDate,
                    totalDays: detail.totalDays,
                    daysCompleted: response.daysCompleted,
                    completionPercentage: response.completionPercentage,
                    currentDayNumber: response.currentDayNumber,
                    daysBehind: response.daysBehind,
                    isPrimary: detail.isPrimary,
                    isActive: detail.isActive,
                    todayDay: updatedToday,
                    recentDays: detail.recentDays
                )
            }
        } catch {
            // Revert on failure by reloading
            await load(token: token)
        }
    }
}

// MARK: - Main View

struct ReadingView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = ReadingViewModel()
    @State private var showAddEntry = false

    var body: some View {
        NavigationStack {
            ScrollView {
                contentBody
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .navigationTitle("Reading Plan")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if let detail = vm.primaryPlanDetail {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showAddEntry = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddEntry) {
                if let detail = vm.primaryPlanDetail,
                   let dayNum = detail.currentDayNumber {
                    AddReadingEntrySheet(
                        isPresented: $showAddEntry,
                        planId: detail.id,
                        dayNumber: dayNum
                    ) { entries in
                        Task { await vm.load(token: auth.accessToken ?? "") }
                    }
                    .environmentObject(auth)
                }
            }
            .task { await vm.load(token: auth.accessToken ?? "") }
            .refreshable { await vm.load(token: auth.accessToken ?? "") }
        }
    }

    @ViewBuilder
    private var contentBody: some View {
        if vm.isLoading && vm.plans.isEmpty {
            loadingView
        } else if let errorMsg = vm.error {
            errorView(errorMsg)
        } else if vm.plans.isEmpty {
            emptyStateView
        } else {
            LazyVStack(spacing: 20) {
                // Section 1: Today's Reading
                if let detail = vm.primaryPlanDetail, let today = detail.todayDay {
                    TodayReadingCard(
                        detail: detail,
                        today: today,
                        onToggle: {
                            Task {
                                await vm.toggleDay(
                                    planId: detail.id,
                                    dayNum: today.dayNumber,
                                    token: auth.accessToken ?? ""
                                )
                            }
                        }
                    )
                }

                // Section 2: Progress Stats
                if let detail = vm.primaryPlanDetail {
                    ProgressStatsRow(detail: detail)
                }

                // Section 3: Recent Days Strip
                if let detail = vm.primaryPlanDetail, !detail.recentDays.isEmpty {
                    RecentDaysStrip(days: detail.recentDays, currentDayNumber: detail.currentDayNumber)
                }

                // Section 3b: View All Days button + Bible Progress
                if let detail = vm.primaryPlanDetail,
                   let summary = vm.plans.first(where: { $0.id == detail.id }) ?? vm.plans.first {
                    NavigationLink(destination: ReadingCalendarView(plan: summary).environmentObject(auth)) {
                        Label("View All \(detail.totalDays) Days", systemImage: "calendar")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                }

                if let detail = vm.primaryPlanDetail {
                    NavigationLink(destination: BibleProgressView(planId: detail.id).environmentObject(auth)) {
                        Label("Bible Progress", systemImage: "books.vertical")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                }

                // Section 4: All Plans (when more than 1)
                if vm.plans.count > 1 {
                    AllPlansSection(
                        plans: vm.plans,
                        primaryId: vm.primaryPlanDetail?.id
                    )
                }
            }
        }
    }

    // MARK: - State Views

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading your reading plan…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("Something went wrong")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await vm.load(token: auth.accessToken ?? "") }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding()
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "book.closed")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                Text("No Reading Plan Yet")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Visit the HaleHub web app to create a reading plan, then come back here to track your progress.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .padding(.horizontal, 24)
    }
}

// MARK: - Today's Reading Card

struct TodayReadingCard: View {
    let detail: ReadingPlanDetail
    let today: ReadingDay
    let onToggle: () -> Void

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: today.date) {
            formatter.dateStyle = .long
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
        return today.date
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Day \(today.dayNumber)")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text(formattedDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                PlanNameBadge(name: detail.name)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            // Passage List
            if today.entries.isEmpty {
                Text("No passages listed for today.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(today.entries) { entry in
                        ReadingEntryRow(entry: entry)
                        if entry.id != today.entries.last?.id {
                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                }
            }

            Divider()

            // Toggle Button
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Image(systemName: today.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                    Text(today.isCompleted ? "Marked Complete" : "Mark as Complete")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(today.isCompleted ? .white : Color.accentColor)
                .background(today.isCompleted ? Color.green : Color.accentColor.opacity(0.12))
            }
            .clipShape(UnevenRoundedRectangle(
                bottomLeadingRadius: 14,
                bottomTrailingRadius: 14
            ))
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    today.isCompleted ? Color.green.opacity(0.4) : Color.clear,
                    lineWidth: 1.5
                )
        )
    }
}

struct ReadingEntryRow: View {
    let entry: ReadingEntry

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 36, height: 36)
                Text((entry.bookAbbrev ?? entry.reference).prefix(3))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.reference)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                if let book = entry.bookName, !book.isEmpty {
                    Text(book)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text("Ch. \(entry.chapterStart ?? 0)–\(entry.chapterEnd ?? 0)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct PlanNameBadge: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.12))
            .foregroundStyle(Color.accentColor)
            .clipShape(Capsule())
            .lineLimit(1)
    }
}

// MARK: - Progress Stats Row

struct ProgressStatsRow: View {
    let detail: ReadingPlanDetail

    var statusLabel: String {
        guard let behind = detail.daysBehind else { return "Not Started" }
        if behind > 0 { return "\(behind) Behind" }
        if behind < 0 { return "\(abs(behind)) Ahead" }
        return "On Track"
    }

    var statusColor: Color {
        guard let behind = detail.daysBehind else { return .secondary }
        if behind > 0 { return .orange }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Progress")
                .font(.headline)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.systemFill))
                        .frame(height: 10)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor, Color.green],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: geo.size.width * CGFloat(detail.completionPercentage / 100.0).clamped(to: 0...1),
                            height: 10
                        )
                }
            }
            .frame(height: 10)

            // Stat chips
            HStack(spacing: 10) {
                StatChip(
                    value: "\(detail.daysCompleted)/\(detail.totalDays)",
                    label: "Days",
                    color: .blue
                )
                StatChip(
                    value: String(format: "%.0f%%", detail.completionPercentage),
                    label: "Complete",
                    color: .green
                )
                StatChip(
                    value: statusLabel,
                    label: "Status",
                    color: statusColor
                )
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct StatChip: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Recent Days Strip

struct RecentDaysStrip: View {
    let days: [ReadingDaySummary]
    let currentDayNumber: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Days")
                .font(.headline)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(days, id: \.dayNumber) { day in
                        DayCircle(day: day, isToday: day.dayNumber == currentDayNumber)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct DayCircle: View {
    let day: ReadingDaySummary
    let isToday: Bool

    private var circleColor: Color {
        if day.isCompleted { return .green }
        if isToday { return Color(.systemGray4) }
        return .clear
    }

    private var borderColor: Color {
        if day.isCompleted { return .clear }
        if day.isOverdue { return .orange }
        if isToday { return .clear }
        return Color(.systemGray4)
    }

    private var textColor: Color {
        if day.isCompleted { return .white }
        if isToday { return .primary }
        if day.isOverdue { return .orange }
        return .secondary
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(circleColor)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle()
                            .strokeBorder(borderColor, lineWidth: day.isOverdue ? 2 : 1)
                    )

                if day.isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(day.dayNumber)")
                        .font(.system(size: 13, weight: isToday ? .bold : .regular))
                        .foregroundStyle(textColor)
                }
            }

            Text(shortDateAbbrev)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 44)
        }
    }

    private var shortDateAbbrev: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: day.date) else { return "" }
        formatter.dateFormat = "EEE"
        let weekday = String(formatter.string(from: date).prefix(3))
        formatter.dateFormat = "d"
        let dom = formatter.string(from: date)
        return "\(weekday)\n\(dom)"
    }
}

// MARK: - All Plans Section

struct AllPlansSection: View {
    let plans: [ReadingPlanSummary]
    let primaryId: String?

    private var otherPlans: [ReadingPlanSummary] {
        plans.filter { $0.id != primaryId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("All Plans")
                .font(.headline)

            ForEach(otherPlans) { plan in
                OtherPlanRow(plan: plan)
                if plan.id != otherPlans.last?.id {
                    Divider()
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct OtherPlanRow: View {
    let plan: ReadingPlanSummary

    private var statusText: String {
        guard let behind = plan.daysBehind else { return "Not started" }
        if behind > 0 { return "\(behind) days behind" }
        if behind < 0 { return "\(abs(behind)) days ahead" }
        return "On track"
    }

    private var statusColor: Color {
        guard let behind = plan.daysBehind else { return .secondary }
        return behind > 0 ? .orange : .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                }
                Spacer()
                Text(String(format: "%.0f%%", plan.completionPercentage))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: plan.completionPercentage / 100.0)
                .tint(
                    plan.daysBehind == nil ? .secondary :
                    plan.daysBehind! > 0 ? .orange : .green
                )

            Text("\(plan.daysCompleted) of \(plan.totalDays) days")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Helpers

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
