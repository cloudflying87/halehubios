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
    let other: Double?
}

// MARK: - Paycheck year summary (grouped by type)

struct PaycheckTotals: Codable, Sendable {
    let gross: Double
    let net: Double
    let income: Double
    let deduction: Double
    let tax: Double
    let savings: Double
}

struct PaycheckLineTotal: Codable, Sendable, Identifiable {
    var id: String { name }
    let name: String
    let amount: Double
}

struct PaycheckByType: Codable, Sendable {
    let income: [PaycheckLineTotal]
    let deduction: [PaycheckLineTotal]
    let tax: [PaycheckLineTotal]
    let savings: [PaycheckLineTotal]
}

struct PaycheckRowTypes: Codable, Sendable {
    let income: Double
    let deduction: Double
    let tax: Double
    let savings: Double
}

struct PaycheckSummaryRow: Codable, Sendable, Identifiable {
    let id: Int
    let date: String
    let employer: String
    let user: String
    let gross: Double
    let net: Double
    let byType: PaycheckRowTypes
}

struct PaycheckYearSummary: Codable, Sendable {
    let year: Int
    let scope: String
    let checkCount: Int
    let totals: PaycheckTotals
    let byType: PaycheckByType
    let checks: [PaycheckSummaryRow]
}

// MARK: - Other accounts (manual assets / liabilities, synced credit cards)

struct OtherAccount: Codable, Sendable, Identifiable {
    let id: Int
    let name: String
    let kind: String        // asset | liability
    let category: String    // real_estate | credit_card | vehicle | mortgage | cash | other
    let value: Double
    let source: String      // manual | ynab
    let isActive: Bool
    let notes: String
}

struct OtherAccountRequest: Codable, Sendable {
    let name: String
    let kind: String
    let category: String
    let value: Double
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

struct LoanCheckpoint: Identifiable, Codable, Sendable {
    let id: Int
    let checkpointDate: String   // "YYYY-MM-DD"
    let balance: Double
    let notes: String
}

struct LoanCheckpointRequest: Codable, Sendable {
    let checkpointDate: String
    let balance: Double
    let notes: String
}

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
    let ynabCategory: String?
    let totalInterest: Double?
    let remainingPayments: Int?
    let payments: [LoanPayment]?
    let checkpoints: [LoanCheckpoint]?
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
    let ynabCategory: String?
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
    let years: [TitheYearPoint]?
}

struct TitheYearPoint: Codable, Sendable, Identifiable {
    var id: Int { year }
    let year: Int
    let gross: Double
    let target: Double
    let given: Double
    let remaining: Double
    let pctGiven: Double
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

struct PayTripEditRequest: Codable, Sendable {
    let hours: Double
    let tripType: String
    let label: String
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

// MARK: - keep-logging (ALV / pay rate / paycheck split)

struct KeepLoggingStatus: Codable, Sendable {
    let connected: Bool
    let username: String
    let lastSyncedAt: String?
}

struct KLConnectRequest: Codable, Sendable {
    let username: String
    let password: String
}

struct KLBlock: Codable, Sendable {
    let connected: Bool
    let error: String?
    let alv: Double?
    let alvRange: String?
    let reserveGuarantee: Double?
    let category: String?
    let position: String?
    let aircraft: String?
    let payRate: Double?
    let payRateEffectiveDate: String?
    let tripCount: Int?
    let totalTafbHours: Double?
    let creditAvailable: Bool
    let monthlyCredit: Double?
}

struct PaycheckSplit: Codable, Sendable {
    let rate: Double?
    let fullPay: Double?
    let advance: Double?
    let remainder: Double?
}

struct PayMonthDetail: Codable, Sendable {
    let year: Int
    let month: Int
    let halehubCredit: Double
    let halehubRate: Double?
    let keeplogging: KLBlock
    let paycheck: PaycheckSplit
}

struct PayCompareRow: Codable, Sendable, Identifiable {
    var id: Int { monthNum }
    let monthNum: Int
    let month: String
    let credit: Double
    let alv: Double?
    let overUnder: Double?
    let rate: Double?
}

struct PayCompareData: Codable, Sendable {
    let year: Int
    let klConnected: Bool
    let months: [PayCompareRow]
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

/// Editable line item used by the in-app review step. `id` is local-only (not
/// sent to / received from the server); the wire shape is name/amount/ytdAmount/type.
struct ReviewLineItem: Identifiable, Codable, Sendable, Hashable {
    var id = UUID()
    var name: String
    var amount: Double
    var ytdAmount: Double
    var type: String   // INCOME | DEDUCTION | TAX | SAVINGS

    enum CodingKeys: String, CodingKey { case name, amount, ytdAmount, type }

    init(id: UUID = UUID(), name: String, amount: Double, ytdAmount: Double, type: String) {
        self.id = id; self.name = name; self.amount = amount; self.ytdAmount = ytdAmount; self.type = type
    }
}

struct PaycheckUploadResponse: Codable, Sendable {
    let paycheck: PaycheckDetail
    let parsedOk: Bool
    let parsedLineItems: [ReviewLineItem]?
}

struct CommitLineItemsRequest: Codable, Sendable {
    let lineItems: [ReviewLineItem]
}

struct PaycheckEditRequest: Codable, Sendable {
    let grossPay: Double
    let netPay: Double
    let payDate: String
    let notes: String
}

struct BrokerageTopHolding: Codable, Sendable {
    let description: String
    let currentValue: Double
    let percentOfAccount: Double
}

struct BrokerageAccountSummary: Identifiable, Codable, Sendable {
    let id: Int
    let name: String
    let accountType: String
    let institution: String?
    let latestBalance: Double?
    let latestImportDate: Date?
    let topHoldings: [BrokerageTopHolding]
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

// MARK: - Family full-year income prediction

struct RecurringIncome: Codable, Sendable, Identifiable {
    let id: Int
    let person: String
    let label: String
    let amount: Double
    let frequency: String        // weekly|biweekly|semimonthly|monthly|annual
    let periodsPerYear: Int
    let annual: Double
    let isActive: Bool
}

struct RecurringIncomeRequest: Codable, Sendable {
    let person: String
    let label: String?
    let amount: Double
    let frequency: String
}

struct FamilyEarner: Codable, Sendable, Identifiable {
    var id: String { name + "-" + source }
    let name: String
    let source: String           // pay_hours | recurring
    let annual: Double
    let monthly: [Double]
}

struct FamilyPrediction: Codable, Sendable {
    let year: Int
    let earners: [FamilyEarner]
    let recurringSources: [RecurringIncome]
    let monthlyTotals: [Double]
    let totalAnnual: Double
}

// MARK: - Retirement (Fidelity accounts, detailed)

struct RetirementHistoryPoint: Codable, Sendable, Identifiable {
    var id: String { date }
    let date: String       // "YYYY-MM-DD"
    let balance: Double
}

struct RetirementAccount: Codable, Sendable, Identifiable {
    var id: String { name }
    let name: String
    let latestBalance: Double
    let latestDate: String
    let contributions: Double
    let earnings: Double
    let fees: Double
    let valueChange: Double
    let reportCount: Int
    let history: [RetirementHistoryPoint]
}

struct RetirementSummary: Codable, Sendable {
    let total: Double
    let accounts: [RetirementAccount]
    let analysis: RetirementAnalysis?
}

// Year-over-year performance + overall metrics + a Monte Carlo seed,
// computed server-side from the combined Fidelity report history.
struct RetirementAnalysis: Codable, Sendable {
    let metrics: RetirementMetrics
    let yearly: [RetirementYear]
    let monteCarloSeed: MonteCarloSeed
}

struct RetirementMetrics: Codable, Sendable {
    let totalContributions: Double
    let totalEarnings: Double
    let totalFees: Double
    let netGain: Double
    let roiPct: Double
    let annualizedReturnPct: Double
    let yearsTracked: Double
    let currentBalance: Double
    let startBalance: Double
}

struct RetirementYear: Codable, Sendable, Identifiable {
    var id: Int { year }
    let year: Int
    let endBalance: Double
    let contributions: Double
    let earnings: Double
    let fees: Double
    let returnPct: Double
    let isPartial: Bool
}

struct MonteCarloSeed: Codable, Sendable {
    let initialInvestment: Double
    let monthlyContribution: Double
    let expectedAnnualReturn: Double
    let volatility: Double
}

// MARK: - Monte Carlo simulation

struct MonteCarloPercentiles: Codable, Sendable {
    let p5: Double
    let p10: Double
    let p25: Double
    let p50: Double
    let p75: Double
    let p90: Double
    let p95: Double
}

struct MonteCarloResults: Codable, Sendable {
    let finalValues: MonteCarloPercentiles
    let growthOnly: MonteCarloPercentiles
    let mean: Double
    let stdDev: Double
    let min: Double
    let max: Double
    let probabilityOfGain: Double
    let meanGrowth: Double
}

struct MonteCarloSimulation: Codable, Sendable, Identifiable {
    let id: Int
    let name: String
    let initialInvestment: Double
    let monthlyContribution: Double
    let years: Int
    let expectedAnnualReturn: Double
    let volatility: Double
    let numSimulations: Int
    let createdAt: String?
    let results: MonteCarloResults?
}

struct MonteCarloRequest: Codable, Sendable {
    let name: String
    let initialInvestment: Double
    let monthlyContribution: Double
    let years: Int
    let expectedAnnualReturn: Double
    let volatility: Double
    let numSimulations: Int
}

// MARK: - Investments (non-retirement holdings)

struct InvestmentHolding: Codable, Sendable, Identifiable {
    let id: Int
    let name: String
    let investmentType: String
    let symbol: String
    let currentValue: Double
    let initialInvestment: Double
    let sharesQuantity: Double
    let purchasePrice: Double
    let currentPrice: Double
    let purchaseDate: String?
    let gainLoss: Double
    let gainLossPct: Double
    let isActive: Bool
}

struct InvestmentRequest: Codable, Sendable {
    let name: String
    let investmentType: String
    let symbol: String?
    let currentValue: Double
    let purchaseDate: String?
}

// MARK: - Life insurance policies (sensitive, finance-gated)

struct LifeInsurancePolicy: Codable, Sendable, Identifiable {
    let id: Int
    let insurer: String
    let insuredPerson: String
    let policyType: String
    let policyNumber: String
    let coverageAmount: Double
    let premium: Double
    let premiumFrequency: String
    let annualPremium: Double
    let cashValue: Double
    let beneficiary: String
    let startDate: String?
    let termYears: Int?
    let endDate: String?
    /// Calculated coverage end (manual endDate, or startDate + termYears). nil = permanent.
    let effectiveEndDate: String?
    let isExpired: Bool
    let isActive: Bool
    let notes: String
}

struct LifeInsuranceRequest: Codable, Sendable {
    let insurer: String
    let insuredPerson: String
    let policyType: String
    let policyNumber: String?
    let coverageAmount: Double
    let premium: Double
    let premiumFrequency: String
    let cashValue: Double?
    let beneficiary: String?
    let startDate: String?
    let termYears: Int?
    let endDate: String?
    let notes: String?
}

// MARK: - HSA accounts

struct HSAAccount: Codable, Sendable, Identifiable {
    let id: Int
    let provider: String
    let accountHolder: String
    let accountNumber: String
    let coverageType: String
    let currentBalance: Double
    let investedBalance: Double
    let ytdContribution: Double
    let ytdEmployerContribution: Double
    let contributionLimit: Double
    let totalContributed: Double
    let remainingRoom: Double
    let isActive: Bool
    let notes: String
}

struct HSARequest: Codable, Sendable {
    let provider: String
    let accountHolder: String
    let accountNumber: String?
    let coverageType: String
    let currentBalance: Double
    let investedBalance: Double
    let ytdContribution: Double
    let ytdEmployerContribution: Double
    let contributionLimit: Double
    let notes: String?
}
