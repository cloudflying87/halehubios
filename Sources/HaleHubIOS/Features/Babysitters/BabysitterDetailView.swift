import SwiftUI

@MainActor
class BabysitterDetailViewModel: ObservableObject {
    @Published var sessions: [BabysittingSession] = []
    @Published var payments: [Payment] = []
    @Published var report: SitterReport?
    @Published var isLoading = false
    @Published var error: String?
    @Published var banner: String?

    /// Payment id → Payment, for looking up "paid via" details per session row.
    var paymentById: [String: Payment] { Dictionary(uniqueKeysWithValues: payments.map { ($0.id, $0) }) }

    func load(babysitterId: String, token: String) async {
        isLoading = true
        error = nil
        do {
            async let sessionsResp: PaginatedResponse<BabysittingSession> =
                APIClient.shared.get("/babysitters/sessions/?babysitter=\(babysitterId)", token: token)
            async let paymentsResp: PaginatedResponse<Payment> =
                APIClient.shared.get("/babysitters/payments/?babysitter=\(babysitterId)", token: token)
            async let reportResp: SitterReport =
                APIClient.shared.get("/babysitters/\(babysitterId)/report/", token: token)
            sessions = try await sessionsResp.results
            payments = try await paymentsResp.results
            report = try await reportResp
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func voidPayment(_ payment: Payment, token: String, babysitterId: String) async {
        do {
            try await APIClient.shared.delete("/babysitters/payments/\(payment.id)/", token: token)
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

    func recalculateUnpaid(babysitterId: String, token: String) async {
        do {
            let resp: RecalculateResponse = try await APIClient.shared.postEmpty(
                "/babysitters/\(babysitterId)/recalculate/", token: token
            )
            await load(babysitterId: babysitterId, token: token)
            banner = "Recalculated \(resp.updated) unpaid session\(resp.updated == 1 ? "" : "s") at \(BabysitterFormat.money(resp.newRate))/hr."
        } catch {
            banner = "Couldn't recalculate: \(error.localizedDescription)"
        }
    }
}

struct BabysitterDetailView: View {
    @EnvironmentObject var auth: AuthManager
    let babysitter: Babysitter

    @StateObject private var vm = BabysitterDetailViewModel()
    @State private var showLog = false
    @State private var showEdit = false
    @State private var showRecordPayment = false
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
                    if vm.sessions.contains(where: { !$0.isPaid }) {
                        Button { showRecordPayment = true } label: {
                            Label("Record Payment", systemImage: "dollarsign.circle")
                        }
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
                if canEdit {
                    Button {
                        Task { await vm.recalculateUnpaid(babysitterId: babysitter.id, token: token) }
                    } label: {
                        Label("Recalculate Unpaid Sessions", systemImage: "arrow.clockwise.circle")
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
                        SessionRow(session: session, payment: session.payment.flatMap { vm.paymentById[$0] })
                            .contentShape(Rectangle())
                            .onTapGesture { if canEdit { editingSession = session } }
                            .swipeActions(edge: .trailing) {
                                if canEdit {
                                    Button(role: .destructive) {
                                        Task { await vm.delete(session, token: token, babysitterId: babysitter.id) }
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                            }
                    }
                }
            }

            // Payments
            if !vm.payments.isEmpty {
                Section("Payments") {
                    ForEach(vm.payments) { payment in
                        PaymentDisclosureRow(payment: payment, canEdit: canEdit) {
                            Task { await vm.voidPayment(payment, token: token, babysitterId: babysitter.id) }
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
        .sheet(isPresented: $showRecordPayment) {
            RecordPaymentSheet(babysitter: babysitter, unpaidSessions: vm.sessions.filter { !$0.isPaid }) {
                Task { await vm.load(babysitterId: babysitter.id, token: token) }
            }
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
    let payment: Payment?

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
                if let payment {
                    Text("\(payment.methodDisplay)\(payment.checkNumber.isEmpty ? "" : " #\(payment.checkNumber)") · \(payment.dateDisplay)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

/// One payment, expandable to show which sessions it covers — answers
/// "how much is each check, and which sessions go with it."
struct PaymentDisclosureRow: View {
    let payment: Payment
    var showBabysitterName = false
    var canEdit = false
    var onVoid: (() -> Void)? = nil

    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(payment.sessions) { s in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.dateDisplay).font(.subheadline)
                            Text("\(s.timeRange) · \(s.durationDisplay)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(s.amountDisplay).font(.subheadline)
                    }
                }
                if !payment.notes.isEmpty {
                    Text(payment.notes).font(.caption).foregroundStyle(.secondary)
                }
                if canEdit, let onVoid {
                    Button(role: .destructive) { onVoid() } label: {
                        Label("Void Payment", systemImage: "xmark.circle")
                    }
                    .font(.caption)
                }
            }
            .padding(.top, 4)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if showBabysitterName, let name = payment.babysitterName {
                        Text(name).font(.subheadline.weight(.medium))
                    }
                    Text(payment.dateDisplay).font(.caption).foregroundStyle(.secondary)
                    Text("\(payment.methodDisplay)\(payment.checkNumber.isEmpty ? "" : " #\(payment.checkNumber)") · \(payment.sessionCount) session\(payment.sessionCount == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text(payment.amountDisplay).font(.headline)
            }
        }
    }
}
