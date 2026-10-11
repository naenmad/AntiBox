import Foundation
import SwiftUI

public enum BurnRateStatus: Sendable {
    case sustainable
    case elevated
    case aggressive

    public var title: String {
        switch self {
        case .sustainable: return "Sustainable Pace"
        case .elevated: return "Elevated Burn"
        case .aggressive: return "High Depletion Risk"
        }
    }

    public var badgeColor: Color {
        switch self {
        case .sustainable: return .green
        case .elevated: return .orange
        case .aggressive: return .red
        }
    }
}

public struct BudgetRecommendation: Sendable {
    public let totalRemainingTokens: Int64
    public let recommendedDailyBudget: Int64
    public let recommendedWeeklyBudget: Int64
    public let daysUntilReset: Int
    public let burnRateStatus: BurnRateStatus
    public let actionableSummary: String

    public init(
        totalRemainingTokens: Int64,
        recommendedDailyBudget: Int64,
        recommendedWeeklyBudget: Int64,
        daysUntilReset: Int,
        burnRateStatus: BurnRateStatus,
        actionableSummary: String
    ) {
        self.totalRemainingTokens = totalRemainingTokens
        self.recommendedDailyBudget = recommendedDailyBudget
        self.recommendedWeeklyBudget = recommendedWeeklyBudget
        self.daysUntilReset = daysUntilReset
        self.burnRateStatus = burnRateStatus
        self.actionableSummary = actionableSummary
    }
}
