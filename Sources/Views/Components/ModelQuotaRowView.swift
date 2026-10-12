import SwiftUI

/// Minimalist, clean Apple HIG indicator row with restrained color accents
public struct ModelQuotaRowView: View {
    public let item: QuotaItem
    public let currentTime: Date

    @State private var isHovered: Bool = false

    public init(item: QuotaItem, currentTime: Date = Date()) {
        self.item = item
        self.currentTime = currentTime
    }

    private var isCritical: Bool {
        item.isDepletedOrCritical
    }

    // Clean Apple accent colors
    private var quotaAccentColor: Color {
        if isCritical {
            return Color(red: 0.96, green: 0.36, blue: 0.40) // Subtle coral red
        } else if item.remainingPercentage <= 25.0 {
            return Color.orange
        } else {
            return Color(red: 0.22, green: 0.82, blue: 0.55) // Clean Apple mint green
        }
    }

    private let timerAccentColor = Color(red: 0.92, green: 0.74, blue: 0.30) // Soft amber

    public var body: some View {
        HStack(spacing: 8) {
            // Model Icon
            HStack(spacing: 6) {
                if isCritical {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(quotaAccentColor)
                }

                switch item.iconKind {
                case .sparkle:
                    Image(systemName: "sparkle")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(Color.cyan.opacity(0.9))
                case .robot:
                    Image(systemName: "cpu")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.secondary)
                case .sunburst:
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(Color.orange.opacity(0.9))
                case .chip:
                    Image(systemName: "bolt.shield.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(Color.cyan)
                }

                Text(item.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            // Live Countdown Timer
            HStack(spacing: 3) {
                Image(systemName: "clock")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(timerAccentColor)

                Text(item.countdownString(at: currentTime))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(timerAccentColor)
            }

            // Quota Percentage Badge
            Text(item.displayPercentageString)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundColor(quotaAccentColor)
                .frame(minWidth: 42, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.06) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isCritical ? quotaAccentColor.opacity(0.3) : Color.primary.opacity(0.05), lineWidth: 0.5)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
