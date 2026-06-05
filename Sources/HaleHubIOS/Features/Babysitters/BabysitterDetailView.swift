import SwiftUI

@MainActor
class BabysitterDetailViewModel: ObservableObject {
    @Published var sessions: [BabysittingSession] = []
    @Published var report: SitterReport?
    @Published var isLoading = false
    @Published var error: String?
    @Published var banner: String?

    func load(babysitterId: String, token: String) async {
        isLoading = true
        error = nil
        do {
            async let sessionsResp: PaginatedResponse<BabysittingSession> =
                APIClient.shared.get("/babysitters/sessions/?babysitter=\(babysitterId)", token: token)
            async let reportResp: SitterReport =
                APIClient.shared.get("/babysitters/\(babysitterId)/report/", token: token)
            sessions = try await sessionsResp.results
            report = try await reportResp
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func togglePaid(_ session: BabysittingSession, token: String, babysitterId: String) async {
        do {
            let _: BabysittingSession = try await APIClient.shared.patch(
                "/babysitters/sessions/\(session.id)/",
                body: PaidUpdateRequest(isPaid: !session.isPaid),
                token: token
            )
            await load(babysitterId: babysitterId, token: token)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func delete(_ session: BabysittingSession, token: String, babysitterId: String) async {
        do {
            try await APIClient.shared.delete("/babysitters/sessions/\(session.id)/", token: token)
            await load(babysitterId: babysitterId, token: token)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func sendReport(babysitterId: String, token: String) async {
        do {
            let resp: SendReportResponse = try await APIClient.shared.postEmpty(
                "/babysitters/\(babysitterId)/send-report/", token: token
            )
            banner = "Report emailed to \(resp.to ?? "sitter")."
        } catch {
            banner = "Couldn't send: \(error.localizedDescription)"
        }
    }
}

struct BabysitterDetailView: View {
    @EnvironmentObject var auth: AuthManager
    let babysitter: Babysitter

    @StateObject private var vm = BabysitterDetailViewModel()
    @State private var showLog = false
    @State private var showEdit = false
    @State private var editingSession: BabysittingSession?

    private var canEdit: Bool { auth.currentUser?.can("babysitters", edit: true) ?? false }
    private var token: String { auth.accessToken ?? "" }

    var body: some View {
        List {
            // Summary
            Section {
                LabeledContent("Rate", value: babysitter.rateDisplay)
                if let r = vm.report {
                    LabeledContent("This week", value: BabysitterFormat.money(r.totalOwed))
                    LabeledContent("Unpaid this week", value: BabysitterFormat.money(r.unpaidOwed))
                }
                LabeledContent("Unpaid total", value: babysitter.unpaidDisplay)
            }

            // Actions
            Section {
                if canEdit {
                    Button { showLog = true } label: {
                        Label("Log Session", systemImage: "clock.badge.plus")
                    }
                }
                if let text = vm.report?.reportText, !text.isEmpty {
                    ShareLink(item: text) {
                        Label("Share Report", systemImage: "square.and.arrow.up")
                    }
                }
                if canEdit, babysitter.hasEmail {
                    Button {
                        Task { await vm.sendReport(babysitterId: babysitter.id, token: token) }
                    } label: {
                        Label("Email Report to Sitter", systemImage: "envelope")
                    }
                }
            }

            // Sessions
            Section("Sessions") {
                if vm.sessions.isEmpty {
                    Text("No sessions logged yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(vm.sessions) { session in
                        SessionRow(session: session)
                            .contentShape(Rectangle())
                            .onTapGesture { if canEdit { editingSession = session } }
                            .swipeActions(edge: .trailing) {
                                if canEdit {
                                    Button(role: .destructive) {
                                        Task { await vm.delete(session, token: token, babysitterId: babysitter.id) }
                                    } label: { Label("Delete", systemImage: "trash") }
                                    Button {
                                        Task { await vm.togglePaid(session, token: token, babysitterId: babysitter.id) }
                                    } label: {
                                        Label(session.isPaid ? "Unpay" : "Paid",
                                              systemImage: session.isPaid ? "xmark.circle" : "checkmark.circle")
                                    }
                                    .tint(session.isPaid ? .gray : .green)
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle(babysitter.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { showEdit = true }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let banner = vm.banner {
                Text(banner)
                    .font(.subheadline)
                    .padding()
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 8)
                    .task {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        vm.banner = nil
                    }
            }
        }
        .sheet(isPresented: $showLog) {
            SessionFormSheet(session: nil, defaultBabysitterId: babysitter.id) {
                Task { await vm.load(babysitterId: babysitter.id, token: token) }
            }
            .environmentObject(auth)
        }
        .sheet(isPresented: $showEdit) {
            BabysitterFormSheet(babysitter: babysitter) { }
                .environmentObject(auth)
        }
        .sheet(item: $editingSession) { session in
            SessionFormSheet(session: session, defaultBabysitterId: babysitter.id) {
                Task { await vm.load(babysitterId: babysitter.id, token: token) }
            }
            .environmentObject(auth)
        }
        .task { await vm.load(babysitterId: babysitter.id, token: token) }
        .refreshable { await vm.load(babysitterId: babysitter.id, token: token) }
    }
}

private struct SessionRow: View {
    let session: BabysittingSession

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.dateDisplay).font(.headline)
                Text("\(session.startDisplay)–\(session.endDisplay) · \(session.durationDisplay ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(session.amountDisplay).font(.headline)
                Text(session.isPaid ? "Paid" : "Unpaid")
                    .font(.caption2)
                    .foregroundStyle(session.isPaid ? .green : .orange)
            }
        }
    }
}
