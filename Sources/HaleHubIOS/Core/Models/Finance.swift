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

// MARK: - Loan detail / management

struct LoanDetail: Identifiable, Codable, Sendable {
    let id: Int
    let name: String
    let loanType: String
    let principalAmount: Double
    let currentBalance: Double
    let interestRate: Double
    let termMonths: Int
    let monthlyPayment: Double
    let startDate: String          // "YYYY-MM-DD"
    let isActive: Bool
    let isInvestment: Bool
    let progressPct: Double
    let payoffDate: String?
    let totalInterest: Double?
    let remainingPayments: Int?
    let payments: [LoanPayment]?
    let amortization: [AmortizationRow]?
}

struct AmortizationRow: Identifiable, Codable, Sendable {
    var id: Int { paymentNumber }
    let paymentNumber: Int
    let beginningBalance: Double
    let monthlyPayment: Double
    let principalPayment: Double
    let interestPayment: Double
    let endingBalance: Double
}

struct LoanPayment: Identifiable, Codable, Sendable {
    let id: Int
    let paymentDate: String        // "YYYY-MM-DD"
    let amount: Double
    let principalPortion: Double
    let interestPortion: Double
    let extraPayment: Double
    let paymentMethod: String
    let notes: String
}

/// Create/update payload. Nil optionals are omitted by JSONEncoder, so a nil
/// currentBalance lets the backend default it to the principal amount.
struct LoanRequest: Codable, Sendable {
    let name: String
    let loanType: String
    let principalAmount: Double
    let currentBalance: Double?
    let interestRate: Double
    let termMonths: Int
    let monthlyPayment: Double
    let startDate: String
    let isActive: Bool
    let isInvestment: Bool
}

struct PaymentRequest: Codable, Sendable {
    let amount: Double
    let paymentDate: String
    let paymentMethod: String
    let notes: String?
}

/// Response from POST .../payments/ — the new payment plus the updated loan.
struct PaymentResponse: Codable, Sendable {
    let payment: LoanPayment
    let loan: LoanDetail
}

// MARK: - Tithe

struct TitheSummary: Codable, Sendable {
    let month: String            // "YYYY-MM"
    let configured: Bool
    let percentage: Double
    let givingCategory: String
    let gross: Double
    let target: Double
    let given: Double
    let remaining: Double
    let pctGiven: Double
    let history: [TitheMonthPoint]
}

struct TitheMonthPoint: Codable, Sendable, Identifiable {
    var id: String { month }
    let month: String
    let gross: Double
    let target: Double
    let given: Double
    let remaining: Double
}

struct TitheSettingsData: Codable, Sendable {
    let percentage: Double
    let givingCategory: String
    let availableCategories: [String]
}

struct TitheSettingsRequest: Codable, Sendable {
    let percentage: Double
    let givingCategory: String
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

// MARK: - Pay Hours (pilot trips + rates)

struct PaySummaryTotals: Codable, Sendable {
    let creditHours: Double
    let estimatedPay: Double
}

struct PayMonthRow: Codable, Sendable, Identifiable {
    var id: Int { monthNum }
    let month: String
    let monthNum: Int
    let regular: Double
    let green: Double
    let sick: Double
    let `override`: Double
    let totalCredit: Double
    let rate: Double?
    let estimatedPay: Double?
}

struct PaySummary: Codable, Sendable {
    let year: Int
    let months: [PayMonthRow]
    let totals: PaySummaryTotals
    let averages: PaySummaryTotals
}

struct PayTrip: Codable, Sendable, Identifiable {
    let id: Int
    let month: String
    let tripDate: String?
    let hours: Double
    let tripType: String
    let multiplier: Double
    let creditHours: Double
    let label: String
    let source: String
}

struct PayTripRequest: Codable, Sendable {
    let month: String
    let hours: Double
    let tripType: String
    let label: String?
}

struct PayTripPatch: Codable, Sendable {
    let tripType: String
}

struct PayRate: Codable, Sendable, Identifiable {
    let id: Int
    let effectiveDate: String
    let hourlyRate: Double
    let note: String
}

struct PayRateRequest: Codable, Sendable {
    let effectiveDate: String
    let hourlyRate: Double
    let note: String?
}

struct PayImportSummary: Codable, Sendable {
    let monthsImported: Int
    let tripsCreated: Int
    let greenSlips: Int
    let years: [Int]
}

// MARK: - Paychecks (upload + detail)

struct Employer: Identifiable, Codable, Sendable {
    let id: Int
    let name: String
    let isActive: Bool
}

struct PaycheckLineItemValue: Codable, Sendable, Identifiable {
    var id: String { name }
    let name: String
    let amount: Double
    let ytdAmount: Double
    let itemType: String
}

struct PaycheckDetail: Identifiable, Codable, Sendable {
    let id: Int
    let payDate: String            // "YYYY-MM-DD"
    let employerId: Int
    let employerName: String
    let grossPay: Double
    let netPay: Double
    let payPeriodStart: String
    let payPeriodEnd: String
    let checkNumber: String
    let notes: String
    let pdfUrl: String?
    let lineItems: [PaycheckLineItemValue]?
}

struct PaycheckUploadResponse: Codable, Sendable {
    let paycheck: PaycheckDetail
    let parsedOk: Bool
}

struct PaycheckEditRequest: Codable, Sendable {
    let grossPay: Double
    let netPay: Double
    let payDate: String
    let notes: String
}

struct BrokerageAccountSummary: Identifiable, Codable, Sendable {
    let id: Int
    let name: String
    let accountType: String
    let institution: String?
    let latestBalance: Double?
    let latestImportDate: Date?
}

// MARK: - YNAB + Budget

struct YNABStatus: Codable, Sendable {
    let connected: Bool
    let budgetId: String
    let budgetName: String
    let syncEnabled: Bool
    let lastSyncedAt: String?
    let lastSyncStatus: String
    let hasToken: Bool
}

struct YNABBudgetOption: Identifiable, Codable, Sendable {
    let id: String
    let name: String
}

struct YNABBudgetsResponse: Codable, Sendable {
    let budgets: [YNABBudgetOption]
}

struct YNABSettingsRequest: Codable, Sendable {
    let token: String?
    let budgetId: String?
    let budgetName: String?
    let syncEnabled: Bool?
}

struct SyncCounts: Codable, Sendable {
    let created: Int
    let updated: Int
}

struct YNABSyncSummary: Codable, Sendable {
    let months: [String]
    let budgets: SyncCounts
    let transactions: SyncCounts
}

struct BudgetCategoryRow: Codable, Sendable, Identifiable {
    var id: String { category }
    let category: String
    let budgeted: Double
    let activity: Double
    let available: Double
}

struct BudgetGroup: Codable, Sendable, Identifiable {
    var id: String { group }
    let group: String
    let budgeted: Double
    let activity: Double
    let available: Double
    let categories: [BudgetCategoryRow]
}

struct BudgetTotals: Codable, Sendable {
    let budgeted: Double
    let activity: Double
    let available: Double
}

struct BudgetMonthData: Codable, Sendable {
    let month: String
    let groups: [BudgetGroup]
    let totals: BudgetTotals
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
