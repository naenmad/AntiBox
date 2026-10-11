import SwiftUI

/// Pixel-crafted macOS indicator row directly matching Apple HIG and system terminal aesthetic
public struct ModelQuotaRowView: View {
    public let item: QuotaItem

    public init(item: QuotaItem) {
        self.item = item
    }

    private var isCritical: Bool {
        item.isDepletedOrCritical
    }

    // Emerald palette for healthy, Crimson palette for critical/zero
    private var rowBackground: Color {
        if isCritical {
            return Color(red: 0.18, green: 0.08, blue: 0.10)
        } else {
            return Color(red: 0.08, green: 0.16, blue: 0.14)
        }
    }

    private var rowBorderColor: Color {
        if isCritical {
            return Color(red: 0.65, green: 0.22, blue: 0.28).opacity(0.85)
        } else {
            return Color(red: 0.16, green: 0.38, blue: 0.28).opacity(0.75)
        }
    }

    private var primaryTextColor: Color {
        if isCritical {
            return Color(red: 0.98, green: 0.75, blue: 0.78)
        } else {
            return Color(red: 0.88, green: 0.92, blue: 0.92)
        }
    }

    private var quotaValueColor: Color {
        if isCritical {
            return Color(red: 0.98, green: 0.42, blue: 0.48)
        } else {
            return Color(red: 0.22, green: 0.88, blue: 0.62)
        }
    }

    private let timerColor = Color(red: 0.95, green: 0.76, blue: 0.22)

    public var body: some View {
        HStack(spacing: 8) {
            // Leading Icon Group
            HStack(spacing: 5) {
                if isCritical {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(quotaValueColor)

                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(red: 0.96, green: 0.58, blue: 0.45))
                } else {
                    switch item.iconKind {
                    case .sparkle:
                        Image(systemName: "sparkle")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.cyan, Color(red: 0.95, green: 0.55, blue: 0.65)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    case .robot:
                        Image(systemName: "cpu")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(red: 0.55, green: 0.75, blue: 0.82))
                    case .sunburst:
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.orange)
                    case .chip:
                        Image(systemName: "bolt.shield.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.cyan)
                    }
                }

                Text(item.name)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundColor(primaryTextColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            // Middle: Timer indicator with clock icon
            HStack(spacing: 3) {
                Image(systemName: "clock")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(timerColor)

                Text(item.countdownString)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(timerColor)
            }

            // Trailing: Quota percentage / indicator label
            Text(item.displayPercentageString)
                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                .foregroundColor(quotaValueColor)
                .frame(minWidth: 44, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(rowBorderColor, lineWidth: 1)
        )
    }
}
