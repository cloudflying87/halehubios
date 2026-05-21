import SwiftUI

// MARK: - ViewModel

@MainActor
class ReadingCalendarViewModel: ObservableObject {
    @Published var response: ChunkedDaysResponse?
    @Published var isLoading = false
    @Published var error: String?
    @Published var currentChunk = 0

    let planId: String
    let currentDayNumber: Int?

    init(planId: String, currentDayNumber: Int?) {
        self.planId = planId
        self.currentDayNumber = currentDayNumber
        // Start on the chunk containing today
        if let day = currentDayNumber {
            currentChunk = max(0, (day - 1) / 20)
        }
    }

    func load(token: String) async {
        isLoading = true
        error = nil
        do {
            let r: ChunkedDaysResponse = try await APIClient.shared.get(
                "/reading/plans/\(planId)/days/?chunk=\(currentChunk)", token: token
            )
            response = r
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func goToPrevChunk(token: String) async {
        guard currentChunk > 0 else { return }
        currentChunk -= 1
        await load(token: token)
    }

    func goToNextChunk(token: String) async {
        guard let r = response, currentChunk < r.totalChunks - 1 else { return }
        currentChunk += 1
        await load(token: token)
    }

    func jumpToTodayChunk(token: String) async {
        guard let day = currentDayNumber else { return }
        let todayChunk = max(0, (day - 1) / 20)
        guard todayChunk != currentChunk else { return }
        currentChunk = todayChunk
        await load(token: token)
    }

    /// Range label e.g. "Days 1–20 of 365"
    func chunkRangeLabel(r: ChunkedDaysResponse) -> String {
        let start = currentChunk * r.daysPerChunk + 1
        let end = min(start + r.daysPerChunk - 1, r.totalDays)
        return "Days \(start)–\(end) of \(r.totalDays)"
    }
}

// MARK: - View

struct ReadingCalendarView: View {
    @EnvironmentObject var auth: AuthManager
    let plan: ReadingPlanSummary
    @StateObject private var vm: ReadingCalendarViewModel

    init(plan: ReadingPlanSummary) {
        self.plan = plan
        _vm = StateObject(wrappedValue: ReadingCalendarViewModel(
            planId: plan.id, currentDayNumber: plan.currentDayNumber
        ))
    }

    var body: some View {
        Group {
            if vm.isLoading && vm.response == nil {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let r = vm.response {
                calendarContent(r)
            } else if let err = vm.error {
                Text(err)
                    .foregroundStyle(.red)
                    .padding()
            }
        }
        .navigationTitle("All Days")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load(token: auth.accessToken ?? "") }
    }

    // MARK: - Calendar Content

    @ViewBuilder
    private func calendarContent(_ r: ChunkedDaysResponse) -> some View {
        VStack(spacing: 0) {
            // Chunk navigation bar
            chunkNavBar(r: r)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground))

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(r.days, id: \.dayNumber) { day in
                        NavigationLink(destination:
                            ReadingDayDetailView(
                                planId: plan.id,
                                dayNumber: day.dayNumber,
                                dateString: day.date
                            )
                            .environmentObject(auth)
                        ) {
                            CalendarDayRow(
                                day: day,
                                isToday: day.dayNumber == plan.currentDayNumber
                            )
                        }
                        .buttonStyle(.plain)

                        Divider()
                            .padding(.leading, 72)
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .overlay {
            if vm.isLoading {
                Color.black.opacity(0.15).ignoresSafeArea()
                ProgressView()
                    .padding(20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Chunk Nav Bar

    @ViewBuilder
    private func chunkNavBar(r: ChunkedDaysResponse) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await vm.goToPrevChunk(token: auth.accessToken ?? "") }
            } label: {
                Label("Prev", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.bordered)
            .disabled(vm.currentChunk == 0)

            Spacer()

            VStack(spacing: 2) {
                Text(vm.chunkRangeLabel(r: r))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .monospacedDigit()

                if let _ = plan.currentDayNumber {
                    Button("Today") {
                        Task { await vm.jumpToTodayChunk(token: auth.accessToken ?? "") }
                    }
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            Button {
                Task { await vm.goToNextChunk(token: auth.accessToken ?? "") }
            } label: {
                Label("Next", systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.bordered)
            .disabled(vm.currentChunk >= r.totalChunks - 1)
        }
    }
}

// MARK: - Calendar Day Row

private struct CalendarDayRow: View {
    let day: ReadingDay
    let isToday: Bool

    private var circleColor: Color {
        if day.isCompleted { return .green }
        if isToday { return .blue }
        if isOverdue { return .orange }
        return Color(.systemGray5)
    }

    private var isOverdue: Bool {
        guard !day.isCompleted, !isToday else { return false }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: day.date) else { return false }
        return date < Calendar.current.startOfDay(for: Date())
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: day.date) else { return day.date }
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }

    private var firstReference: String? {
        day.entries.first?.reference
    }

    var body: some View {
        HStack(spacing: 14) {
            // Day number circle
            ZStack {
                Circle()
                    .fill(circleColor)
                    .frame(width: 44, height: 44)

                if day.isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(day.dayNumber)")
                        .font(.system(size: 13, weight: isToday ? .bold : .regular))
                        .foregroundStyle(isToday ? .white : (isOverdue ? .white : .secondary))
                }
            }

            // Date + reference
            VStack(alignment: .leading, spacing: 3) {
                Text(formattedDate)
                    .font(.subheadline)
                    .fontWeight(isToday ? .semibold : .regular)
                    .foregroundStyle(.primary)

                if let ref = firstReference {
                    Text(ref)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Entry count badge
            if !day.entries.isEmpty {
                Text("\(day.entries.count) reading\(day.entries.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
