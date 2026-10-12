import Foundation
import SwiftUI

/// Status level based on remaining quota percentage
public enum QuotaStatus: Sendable {
    case safe      // > 25% remaining
    case warning   // 15% - 25% remaining
    case critical  // <= 15% remaining

    public var color: Color {
        switch self {
        case .safe: return Color(red: 0.18, green: 0.82, blue: 0.58) // Apple vibrant emerald
        case .warning: return Color.orange
        case .critical: return Color(red: 0.95, green: 0.36, blue: 0.42) // Apple vibrant coral
        }
    }

    public var label: String {
        switch self {
        case .safe: return "Healthy"
        case .warning: return "Moderate"
        case .critical: return "Critical"
        }
    }
}

/// Represents an individual AI provider account
public struct Account: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var email: String
    public var provider: AIProvider
    public var tier: String
    public var totalQuotaTokens: Int64
    public var usedQuotaTokens: Int64
    public var resetDate: Date
    public var isActive: Bool
    public var quotas: [QuotaItem]
    public var customRemainingPercentage: Double?

    public init(
        id: UUID = UUID(),
        name: String,
        email: String = "",
        provider: AIProvider,
        tier: String = "Pro",
        totalQuotaTokens: Int64 = 10_000_000,
        usedQuotaTokens: Int64 = 2_700_000,
        resetDate: Date = Date().addingTimeInterval(17940), // 4h 59m
        isActive: Bool = true,
        quotas: [QuotaItem] = [],
        customRemainingPercentage: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.email = email.isEmpty ? name : email
        self.provider = provider
        self.tier = tier
        self.totalQuotaTokens = totalQuotaTokens
        self.usedQuotaTokens = usedQuotaTokens
        self.resetDate = resetDate
        self.isActive = isActive
        self.quotas = quotas
        self.customRemainingPercentage = customRemainingPercentage
    }

    public var remainingTokens: Int64 {
        max(0, totalQuotaTokens - usedQuotaTokens)
    }

    public var remainingPercentage: Double {
        if let custom = customRemainingPercentage {
            return custom
        }
        guard totalQuotaTokens > 0 else { return 0.0 }
        let fraction = Double(remainingTokens) / Double(totalQuotaTokens)
        return min(max(fraction * 100.0, 0.0), 100.0)
    }

    public var status: QuotaStatus {
        let pct = remainingPercentage
        if pct <= 15.0 {
            return .critical
        } else if pct <= 25.0 {
            return .warning
        } else {
            return .safe
        }
    }

    public var countdownString: String {
        let now = Date()
        guard resetDate > now else { return "0m" }
        let diff = Calendar.current.dateComponents([.day, .hour, .minute], from: now, to: resetDate)
        let days = diff.day ?? 0
        let hours = diff.hour ?? 0
        let minutes = diff.minute ?? 0

        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(max(1, minutes))m"
        }
    }

    public var daysUntilReset: Int {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfReset = calendar.startOfDay(for: resetDate)
        let components = calendar.dateComponents([.day], from: startOfToday, to: startOfReset)
        return max(1, components.day ?? 1)
    }

    public static func formatTokens(_ count: Int64) -> String {
        let doubleVal = Double(count)
        if doubleVal >= 1_000_000 {
            return String(format: "%.1fM", doubleVal / 1_000_000.0)
        } else if doubleVal >= 1_000 {
            return String(format: "%.0fK", doubleVal / 1_000.0)
        } else {
            return "\(count)"
        }
    }
}
