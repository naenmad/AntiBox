import SwiftUI

/// Clean, fixed frosted card for the 2 core quota categories (Gemini vs Claude/GPT-OSS)
public struct QuotaGroupCardView: View {
    public let group: QuotaGroup
    public let currentTime: Date

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
        VStack(alignment: .leading, spacing: 9) {
            // Group Header Row
            HStack(spacing: 8) {
                // Group Icon Badges
                if group.id == "gemini" {
                    BrandLogoView(.gemini, size: 15)
                        .frame(width: 24, height: 24)
                        .background(group.accentColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    HStack(spacing: 3.5) {
                        BrandLogoView(.claude, size: 12.5)
                            .frame(width: 20, height: 20)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                        BrandLogoView(.chatgpt, size: 12.5)
                            .frame(width: 20, height: 20)
                            .background(Color.teal.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                }

                // Group Title
                Text(group.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer(minLength: 4)

                // Countdown Timer
                HStack(spacing: 3.5) {
                    Image(systemName: "clock")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(timerColor)

                    Text(group.countdownString)
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
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
                .padding(.vertical, 3)
                .background(statusColor.opacity(0.12))
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
            .frame(height: 5)

            // Optional Dedicated Image Generation Quota (Gemini)
            if let imageQuota = group.imageQuota {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Image(systemName: "photo.badge.sparkles")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color(red: 0.70, green: 0.35, blue: 0.95))

                        Text("Image Quota")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)

                        Spacer()

                        HStack(spacing: 3) {
                            Image(systemName: "clock")
                                .font(.system(size: 8.5))
                                .foregroundColor(timerColor)

                            Text(imageQuota.countdownString)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(timerColor)
                        }

                        Text("\(Int(imageQuota.percentage))%")
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .foregroundColor(imageQuota.percentage <= 15 ? Color.red : (imageQuota.percentage <= 25 ? Color.orange : Color(red: 0.22, green: 0.82, blue: 0.55)))
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.05))

                            Capsule()
                                .fill(imageQuota.percentage <= 15 ? Color.red : (imageQuota.percentage <= 25 ? Color.orange : Color(red: 0.70, green: 0.35, blue: 0.95)))
                                .frame(width: max(0, min(geo.size.width * CGFloat(imageQuota.percentage / 100.0), geo.size.width)))
                                .animation(.easeInOut(duration: 0.3), value: imageQuota.percentage)
                        }
                    }
                    .frame(height: 3.5)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
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
