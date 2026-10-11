import Foundation

/// Core algorithmic engine that calculates sustainable AI consumption quotas across multi-account pools
public final class SmartBudgetAdvisor: Sendable {
    public static let shared = SmartBudgetAdvisor()

    private init() {}

    /// Calculates aggregate budget recommendations based on active accounts and upcoming reset dates
    public func calculateRecommendation(
        accounts: [Account],
        referenceDate: Date = Date()
    ) -> BudgetRecommendation {
        let activeAccounts = accounts.filter { $0.isActive }

        guard !activeAccounts.isEmpty else {
            return BudgetRecommendation(
                totalRemainingTokens: 0,
                recommendedDailyBudget: 0,
                recommendedWeeklyBudget: 0,
                daysUntilReset: 0,
                burnRateStatus: .sustainable,
                actionableSummary: "No active accounts configured. Add an account to compute usage limits."
            )
        }

        let totalRemaining = activeAccounts.reduce(0) { $0 + $1.remainingTokens }
        let totalCapacity = activeAccounts.reduce(0) { $0 + $1.totalQuotaTokens }

        // Find the earliest upcoming reset date among active accounts
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)

        let minimumDaysUntilReset: Int = activeAccounts.map { account -> Int in
            let resetStart = calendar.startOfDay(for: account.resetDate)
            let diff = calendar.dateComponents([.day], from: today, to: resetStart).day ?? 1
            return max(1, diff)
        }.min() ?? 1

        guard totalRemaining > 0 else {
            return BudgetRecommendation(
                totalRemainingTokens: 0,
                recommendedDailyBudget: 0,
                recommendedWeeklyBudget: 0,
                daysUntilReset: minimumDaysUntilReset,
                burnRateStatus: .aggressive,
                actionableSummary: "All allocated quotas are depleted. Workloads will be rate-limited until next cycle reset."
            )
        }

        // Calculate smoothed daily ceiling
        let dailyBudget = max(0, totalRemaining / Int64(minimumDaysUntilReset))

        // Weekly ceiling is either 7 days of daily budget or bounded by cycle window
        let daysInWeekHorizon = min(minimumDaysUntilReset, 7)
        let weeklyBudget = dailyBudget * Int64(daysInWeekHorizon)

        // Assess overall system health
        let aggregatePercentage: Double = totalCapacity > 0
            ? (Double(totalRemaining) / Double(totalCapacity)) * 100.0
            : 0.0

        let burnRate: BurnRateStatus
        if aggregatePercentage <= 20.0 {
            burnRate = .aggressive
        } else if aggregatePercentage <= 40.0 {
            burnRate = .elevated
        } else {
            burnRate = .sustainable
        }

        let formattedDaily = Account.formatTokens(dailyBudget)
        let formattedWeekly = Account.formatTokens(weeklyBudget)
        let dayPlural = minimumDaysUntilReset == 1 ? "day" : "days"

        let summaryText: String
        switch burnRate {
        case .sustainable:
            summaryText = "Safe budget: ~\(formattedDaily) tokens/day (\(formattedWeekly)/week) across \(activeAccounts.count) accounts. Next reset in \(minimumDaysUntilReset) \(dayPlural)."
        case .elevated:
            summaryText = "Moderate quota remaining. Cap high-volume prompts to ~\(formattedDaily) tokens/day to reach reset in \(minimumDaysUntilReset) \(dayPlural)."
        case .aggressive:
            summaryText = "Low pool reserve (\(String(format: "%.0f", aggregatePercentage))%). Throttle automated background tasks to ~\(formattedDaily) tokens/day."
        }

        return BudgetRecommendation(
            totalRemainingTokens: totalRemaining,
            recommendedDailyBudget: dailyBudget,
            recommendedWeeklyBudget: weeklyBudget,
            daysUntilReset: minimumDaysUntilReset,
            burnRateStatus: burnRate,
            actionableSummary: summaryText
        )
    }
}
