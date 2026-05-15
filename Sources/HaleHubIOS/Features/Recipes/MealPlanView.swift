import SwiftUI

struct MealPlanView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = RecipesViewModel()

    var body: some View {
        Group {
            if vm.isLoading {
                ProgressView("Loading meal plan…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let plan = vm.activeMealPlan {
                MealPlanContent(plan: plan, vm: vm)
            } else {
                ContentUnavailableView(
                    "No Meal Plan",
                    systemImage: "fork.knife.circle",
                    description: Text("Set up a meal plan on the website.")
                )
            }
        }
        .navigationTitle("This Week")
        .toolbar {
            NavigationLink(destination: RecipesListView()) {
                Label("All Recipes", systemImage: "book.fill")
            }
        }
        .task { await vm.load(token: auth.accessToken ?? "") }
        .refreshable { await vm.load(token: auth.accessToken ?? "") }
    }
}

// MARK: - Meal Plan Content

struct MealPlanContent: View {
    let plan: MealPlan
    @ObservedObject var vm: RecipesViewModel

    var hasDates: Bool {
        plan.entries?.contains(where: { $0.date != nil }) == true
    }

    var body: some View {
        List {
            // Plan header
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.displayName).font(.headline)
                    if let start = plan.startDate, let end = plan.endDate {
                        Text("\(start, style: .date) – \(end, style: .date)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    let entryCount = plan.entries?.count ?? 0
                    Text("\(entryCount) meal\(entryCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            if hasDates {
                DayGroupedEntries(plan: plan, vm: vm)
            } else {
                MealTypeGroupedEntries(plan: plan, vm: vm)
            }
        }
    }
}

// MARK: - Day-Grouped (when entries have dates)

struct DayGroupedEntries: View {
    let plan: MealPlan
    @ObservedObject var vm: RecipesViewModel

    var days: [(Date, [MealPlanEntry])] {
        guard let entries = plan.entries else { return [] }
        let withDates = entries.filter { $0.date != nil }
        let grouped = Dictionary(grouping: withDates) { entry -> Date in
            Calendar.current.startOfDay(for: entry.date!)
        }
        return grouped.sorted { $0.key < $1.key }
    }

    var body: some View {
        ForEach(days, id: \.0) { date, entries in
            Section {
                ForEach(entries) { entry in
                    MealEntryRow(entry: entry, vm: vm)
                }
            } header: {
                DayHeader(date: date)
            }
        }
    }
}

struct DayHeader: View {
    let date: Date
    var isToday: Bool { Calendar.current.isDateInToday(date) }
    var isTomorrow: Bool { Calendar.current.isDateInTomorrow(date) }

    var label: String {
        if isToday { return "Today" }
        if isTomorrow { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide).month().day())
    }

    var body: some View {
        HStack {
            Text(label)
            if isToday {
                Text("TODAY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor, in: Capsule())
            }
        }
    }
}

// MARK: - Meal-Type Grouped (fallback when no dates)

struct MealTypeGroupedEntries: View {
    let plan: MealPlan
    @ObservedObject var vm: RecipesViewModel

    private let mealOrder = ["breakfast", "lunch", "dinner", "snack", ""]

    var grouped: [(String, [MealPlanEntry])] {
        guard let entries = plan.entries else { return [] }
        return mealOrder.compactMap { type in
            let group = entries.filter { ($0.mealType ?? "") == type }
            guard !group.isEmpty else { return nil }
            return (type.isEmpty ? "Other" : type.capitalized, group)
        }
    }

    var body: some View {
        ForEach(grouped, id: \.0) { label, entries in
            Section(label) {
                ForEach(entries) { entry in
                    MealEntryRow(entry: entry, vm: vm)
                }
            }
        }
    }
}

// MARK: - Meal Entry Row

struct MealEntryRow: View {
    let entry: MealPlanEntry
    @ObservedObject var vm: RecipesViewModel
    @EnvironmentObject var auth: AuthManager
    @State private var cooked = false

    var hasSides: Bool { !(entry.sides?.isEmpty ?? true) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    if let recipe = entry.recipe {
                        NavigationLink(destination: RecipeDetailView(recipe: recipe)) {
                            Text(recipe.title)
                                .font(.body.weight(cooked ? .regular : .medium))
                                .foregroundStyle(cooked ? .secondary : .primary)
                                .strikethrough(cooked)
                        }
                    } else {
                        Text(entry.displayName)
                            .font(.body.weight(.medium))
                            .foregroundStyle(cooked ? .secondary : .primary)
                            .strikethrough(cooked)
                    }

                    // Meal type badge + servings
                    HStack(spacing: 6) {
                        if let mealType = entry.mealType, !mealType.isEmpty {
                            Text(mealType.capitalized)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(.systemGray5), in: Capsule())
                        }
                        if let servings = entry.servingsOverride {
                            Text("Serves \(servings)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                if entry.recipe != nil {
                    Button {
                        withAnimation { cooked.toggle() }
                        if cooked {
                            Task { await vm.markCooked(recipe: entry.recipe!, token: auth.accessToken ?? "") }
                        }
                    } label: {
                        Image(systemName: cooked ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(cooked ? .green : .secondary)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Sides
            if hasSides {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(entry.sides!) { side in
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(side.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.leading, 4)
            }
        }
        .padding(.vertical, 4)
    }
}
