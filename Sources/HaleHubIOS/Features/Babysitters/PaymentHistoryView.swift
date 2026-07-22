import SwiftUI

// MARK: - ViewModel

@MainActor
class PaymentHistoryViewModel: ObservableObject {
    @Published var payments: [Payment] = []
    @Published var isLoading = false
    @Published var error: String?

    func load(token: String) async {
        isLoading = true
        error = nil
        do {
            let resp: PaginatedResponse<Payment> = try await APIClient.shared.get("/babysitters/payments/", token: token)
            payments = resp.results
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func void(_ payment: Payment, token: String) async {
        do {
            try await APIClient.shared.delete("/babysitters/payments/\(payment.id)/", token: token)
            await load(token: token)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Family-wide payment history

/// Every check/payment across all sitters — the "which sessions go with each
/// check" report, family-wide (the per-sitter version lives on
/// BabysitterDetailView).
struct PaymentHistoryView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = PaymentHistoryViewModel()
    @State private var editingPayment: Payment?

    private var canEdit: Bool { auth.currentUser?.can("babysitters", edit: true) ?? false }
    private var token: String { auth.accessToken ?? "" }

    var body: some View {
        Group {
            if vm.isLoading && vm.payments.isEmpty {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let msg = vm.error, vm.payments.isEmpty {
                ContentUnavailableView {
                    Label("Couldn't Load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(msg)
                } actions: {
                    Button("Retry") { Task { await vm.load(token: token) } }
                        .buttonStyle(.borderedProminent)
                }
            } else if vm.payments.isEmpty {
                ContentUnavailableView {
                    Label("No Payments", systemImage: "dollarsign.circle")
                } description: {
                    Text("Record a payment from a sitter's detail page to see it here.")
                }
            } else {
                List {
                    ForEach(vm.payments) { payment in
                        PaymentDisclosureRow(
                            payment: payment,
                            showBabysitterName: true,
                            canEdit: canEdit,
                            onEdit: { editingPayment = payment },
                            onVoid: {
                                Task { await vm.void(payment, token: token) }
                            }
                        )
                    }
                }
            }
        }
        .navigationTitle("Payment History")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingPayment) { payment in
            EditPaymentSheet(payment: payment) {
                Task { await vm.load(token: token) }
            }
            .environmentObject(auth)
        }
        .task { await vm.load(token: token) }
        .refreshable { await vm.load(token: token) }
    }
}
