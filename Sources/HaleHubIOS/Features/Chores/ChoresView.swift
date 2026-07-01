import SwiftUI

@MainActor
final class ChoresViewModel: ObservableObject {
    @Published var dashboard: ChoreDashboard?
    @Published var isLoading = false
    @Published var error: String?

    private var token = ""
    func configure(token: String) { self.token = token }

    func load() async {
        isLoading = true
        error = nil
        do {
            dashboard = try await APIClient.shared.get("/chores/dashboard/", token: token)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func toggle(choreId: String, date: String, done: Bool) async {
        do {
            let _: ChoreCompleteResponse = try await APIClient.shared.post(
                "/chores/\(choreId)/complete/",
                body: ChoreCompleteRequest(date: date, done: done),
                token: token
            )
            await load()  // refresh counts + summaries
        } catch {
            self.error = error.localizedDescription
            await load()
        }
    }
}

private struct ChoreCompleteResponse: Codable, Sendable {
    let choreId: String
    let date: String
    let done: Bool
}

struct ChoresView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = ChoresViewModel()
    private var token: String { auth.accessToken ?? "" }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let dash = vm.dashboard {
                    if dash.children.isEmpty {
                        ContentUnavailableView("No Chores", systemImage: "checklist",
                                               description: Text("No chores assigned yet."))
                            .frame(minHeight: 200)
                    } else {
                        ForEach(dash.children) { child in
                            childCard(child)
                        }
                    }
                } else if vm.isLoading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(16)
        }
        .navigationTitle("Chores")
        .navigationBarTitleDisplayMode(.inline)
        .task { vm.configure(token: token); await vm.load() }
        .refreshable { await vm.load() }
        .alert("Error", isPresented: .init(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK") {}
        } message: { Text(vm.error ?? "") }
    }

    private func childCard(_ child: ChoreChild) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(child.childName).font(.headline)
                Spacer()
                Text("\(child.week.perfectDays)/\(child.week.daysWithChores) all-done days")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if child.today.items.isEmpty {
                Text("No chores today 🎉").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(child.today.items) { item in
                    Button {
                        Task { await vm.toggle(choreId: item.choreId, date: child.today.date, done: !item.done) }
                    } label: {
                        HStack {
                            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.done ? .green : .secondary)
                            Text(item.name)
                                .strikethrough(item.done)
                                .foregroundStyle(item.done ? .secondary : .primary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                    Divider()
                }
                HStack {
                    Text("Today: \(child.today.done)/\(child.today.required)")
                        .font(.caption).foregroundStyle(child.today.allDone ? .green : .secondary)
                    Spacer()
                    Text("Week: \(child.week.totalDone)/\(child.week.totalRequired) done")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
