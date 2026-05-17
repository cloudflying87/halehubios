import Foundation

@MainActor
class FinanceViewModel: ObservableObject {
    @Published var summary: FinanceSummary?
    @Published var loans: [FinanceLoan] = []
    @Published var paychecks: [FinancePaycheck] = []
    @Published var brokerageAccounts: [BrokerageAccountSummary] = []
    @Published var trends: FinanceTrends?
    @Published var isLoading = false
    @Published var error: String?

    func load(token: String) async {
        isLoading = true
        error = nil
        do {
            async let summaryFetch: FinanceSummary = APIClient.shared.get("/finance/summary/", token: token)
            async let loansFetch: [FinanceLoan] = APIClient.shared.get("/finance/loans/", token: token)
            async let paychecksFetch: [FinancePaycheck] = APIClient.shared.get("/finance/paychecks/?limit=10", token: token)
            async let brokerageFetch: [BrokerageAccountSummary] = APIClient.shared.get("/finance/brokerage/", token: token)
            async let trendsFetch: FinanceTrends = APIClient.shared.get("/finance/trends/", token: token)

            let (s, l, p, b, t) = try await (summaryFetch, loansFetch, paychecksFetch, brokerageFetch, trendsFetch)
            summary = s
            loans = l
            paychecks = p
            brokerageAccounts = b
            trends = t
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
