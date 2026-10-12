import SwiftUI

/// Clean, frosted group card presenting one of the two core quota categories (Gemini vs Claude/GPT)
public struct QuotaGroupCardView: View {
    public let group: QuotaGroup
    public let currentTime: Date

    @State private var isExpanded: Bool = false
    @State private var isHovered: Bool = false

    public init(group: QuotaGroup, currentTime: Date = Date()) {
        self.group = group
        self.currentTime = currentTime
    }

    private var statusColor: Color {
        if group.isDepleted {
            return Color(red: 0.96, green: 0.36, blue: 0.40) // Coral red
        } else if group.percentage <= 25.0 {
            return Color.orange
        } else {
            return Color(red: 0.22, green: 0.82, blue: 0.55) // Mint green
        }
    }

    private let timerColor = Color(red: 0.92, green: 0.74, blue: 0.30)

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Group Header Row
            HStack(spacing: 8) {
                // Group Icon
                Image(systemName: group.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(group.accentColor)
                    .frame(width: 22, height: 22)
                    .background(group.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                // Group Title
                Text(group.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer(minLength: 4)

                // Countdown Timer
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(timerColor)

                    Text(group.countdownString)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(timerColor)
                }

                // Quota Percentage Pill
                HStack(spacing: 4) {
                    if group.isDepleted {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                    }

                    Text(group.displayPercentage)
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                }
                .foregroundColor(statusColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(statusColor.opacity(0.1))
                .clipShape(Capsule())
            }

            // Quota Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.06))

                    Capsule()
                        .fill(statusColor)
                        .frame(width: max(0, min(geo.size.width * CGFloat(group.percentage / 100.0), geo.size.width)))
                        .animation(.easeInOut(duration: 0.3), value: group.percentage)
                }
            }
            .frame(height: 4)

            // Sub-Models (Compact or Expanded)
            if !group.models.isEmpty {
                VStack(spacing: 4) {
                    let displayedModels = isExpanded ? group.models : Array(group.models.prefix(3))

                    ForEach(displayedModels) { model in
                        ModelQuotaRowView(item: model, currentTime: currentTime)
                    }

                    if group.models.count > 3 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text(isExpanded ? "Show fewer models" : "Show all \(group.models.count) models")
                                    .font(.system(size: 10, weight: .medium))

                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 8, weight: .semibold))
                            }
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(isHovered ? 0.045 : 0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
