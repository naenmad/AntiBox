import SwiftUI

/// Single account row displaying quota metrics and health status
public struct AccountRowView: View {
    public let account: Account
    public let onToggleStatus: () -> Void
    public let onDelete: () -> Void

    public init(
        account: Account,
        onToggleStatus: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.account = account
        self.onToggleStatus = onToggleStatus
        self.onDelete = onDelete
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header Row: Provider Icon, Account Name, Tier, and Status Badge
            HStack(spacing: 8) {
                Image(systemName: account.provider.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(account.provider.brandColor)
                    .frame(width: 20, height: 20)
                    .background(account.provider.brandColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(account.name)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)

                        Text(account.tier)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Capsule())
                    }

                    Text("Reset in \(account.daysUntilReset) \(account.daysUntilReset == 1 ? "day" : "days")")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Percentage Badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(account.status.color)
                        .frame(width: 6, height: 6)

                    Text("\(String(format: "%.0f", account.remainingPercentage))%")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(account.status.color)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(account.status.color.opacity(0.1))
                .clipShape(Capsule())
            }

            // Quota Progress Bar
            QuotaGaugeView(percentage: account.remainingPercentage, status: account.status)

            // Bottom Metric Row
            HStack {
                Text("\(Account.formatTokens(account.remainingTokens)) remaining")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.secondary)

                Spacer()

                Text("Cap: \(Account.formatTokens(account.totalQuotaTokens))")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .contextMenu {
            Button(account.isActive ? "Pause Monitoring" : "Resume Monitoring") {
                onToggleStatus()
            }
            Divider()
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Account", systemImage: "trash")
            }
        }
    }
}
