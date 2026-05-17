import Foundation

struct FinanceSummary: Codable, Sendable {
    let netWorth: Double
    let totalAssets: Double
    let totalLiabilities: Double
    let assetsBreakdown: AssetsBreakdown
    let currentMonth: MonthlySnapshot
    let totalDebt: Double
    let monthlyDebtPayments: Double
}

struct AssetsBreakdown: Codable, Sendable {
    let cash: Double
    let investments: Double
    let retirement: Double
}

struct MonthlySnapshot: Codable, Sendable {
    let grossIncome: Double?
    let netIncome: Double?
    let taxes: Double?
    let deductions: Double?
    let totalSpending: Double?
    let saved: Double?
    let savingsRate: Double?
}

struct FinanceLoan: Identifiable, Codable, Sendable {
    let id: Int
    let name: String
    let loanType: String
    let currentBalance: Double
    let interestRate: Double
    let monthlyPayment: Double
    let payoffDate: String?
    let progressPct: Double
}

struct FinancePaycheck: Identifiable, Codable, Sendable {
    let id: Int
    let payDate: Date
    let employerName: String?
    let grossPay: Double
    let netPay: Double
    let payPeriodStart: Date?
    let payPeriodEnd: Date?
}

struct BrokerageAccountSummary: Identifiable, Codable, Sendable {
    let id: Int
    let name: String
    let accountType: String
    let institution: String?
    let latestBalance: Double?
    let latestImportDate: Date?
}

struct MonthlyTrendPoint: Codable, Sendable {
    let month: String
    let income: Double?
    let spending: Double?
    let saved: Double?
}

struct FinanceTrends: Codable, Sendable {
    let months: [MonthlyTrendPoint]
}
