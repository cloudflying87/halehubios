import SwiftUI

// MARK: - ViewModel

@MainActor
class BabysittersViewModel: ObservableObject {
    @Published var babysitters: [Babysitter] = []
    @Published var isLoading = false
    @Published var error: String?

    func load(token: String) async {
        isLoading = true
        error = nil
        do {
            let resp: PaginatedResponse<Babysitter> = try await APIClient.shared.get("/babysitters/", token: token)
            babysitters = resp.results
        } catch is CancellationError {
            // view disappeared — keep data
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - List view

struct BabysittersListView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = BabysittersViewModel()
    @State private var showAdd = false

    private var canEdit: Bool { auth.currentUser?.can("babysitters", edit: true) ?? false }

    var body: some View {
        Group {
            if vm.isLoading && vm.babysitters.isEmpty {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let msg = vm.error, vm.babysitters.isEmpty {
                ContentUnavailableView {
                    Label("Couldn't Load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(msg)
                } actions: {
                    Button("Retry") { Task { await vm.load(token: auth.accessToken ?? "") } }
                        .buttonStyle(.borderedProminent)
                }
            } else if vm.babysitters.isEmpty {
                ContentUnavailableView {
                    Label("No Babysitters", systemImage: "person.2")
                } description: {
                    Text("Add a babysitter to start tracking hours and pay.")
                } actions: {
                    if canEdit {
                        Button("Add Babysitter") { showAdd = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                List {
                    Section {
                        NavigationLink {
                            WeeklyReportView()
                        } label: {
                            Label("Weekly Report", systemImage: "chart.bar.doc.horizontal")
                        }
                        NavigationLink {
                            PaymentHistoryView()
                        } label: {
                            Label("Payment History", systemImage: "dollarsign.circle")
                        }
                    }
                    Section("Babysitters") {
                        ForEach(vm.babysitters) { sitter in
                            NavigationLink {
                                BabysitterDetailView(babysitter: sitter)
                            } label: {
                                BabysitterRow(sitter: sitter)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Babysitters")
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            BabysitterFormSheet(babysitter: nil) {
                Task { await vm.load(token: auth.accessToken ?? "") }
            }
            .environmentObject(auth)
        }
        .task { await vm.load(token: auth.accessToken ?? "") }
        .refreshable { await vm.load(token: auth.accessToken ?? "") }
    }
}

private struct BabysitterRow: View {
    let sitter: Babysitter

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(sitter.name).font(.headline)
                Text(sitter.rateDisplay)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let unpaid = sitter.unpaidTotal, unpaid > 0 {
                Text(sitter.unpaidDisplay)
                    .font(.headline)
                    .foregroundStyle(.orange)
            }
        }
    }
}
