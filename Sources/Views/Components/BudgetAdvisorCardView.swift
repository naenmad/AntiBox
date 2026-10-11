import SwiftUI

/// Compact and restrained smart budget advisor banner following Apple HIG
public struct BudgetAdvisorCardView: View {
    public let recommendation: BudgetRecommendation

    public init(recommendation: BudgetRecommendation) {
        self.recommendation = recommendation
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text("Daily Safe Limit:")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.secondary)

                    Text(Account.formatTokens(recommendation.recommendedDailyBudget))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)

                    Text("tokens")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Text(recommendation.actionableSummary)
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // Minimalist Status Tag
            Text(recommendation.burnRateStatus.title)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundColor(recommendation.burnRateStatus.badgeColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(recommendation.burnRateStatus.badgeColor.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}
