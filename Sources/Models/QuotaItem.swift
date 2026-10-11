import Foundation
import SwiftUI

public enum QuotaIconKind: String, Codable, Sendable {
    case sparkle   // Gemini standard models
    case robot     // Gemini Lite models
    case sunburst  // Anthropic Claude models
    case chip      // Specialized agents

    public var systemName: String {
        switch self {
        case .sparkle: return "sparkle"
        case .robot: return "cpu"
        case .sunburst: return "sun.max.fill"
        case .chip: return "bolt.shield.fill"
        }
    }
}

/// Represents a specific model quota or rate limit bucket under an account
public struct QuotaItem: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var provider: AIProvider
    public var iconKind: QuotaIconKind
    public var remainingPercentage: Double
    public var customLabel: String? // e.g. "Weekly 0%"
    public var resetDate: Date
    public var remainingTokens: Int64
    public var totalTokens: Int64

    public init(
        id: UUID = UUID(),
        name: String,
        provider: AIProvider,
        iconKind: QuotaIconKind = .sparkle,
        remainingPercentage: Double,
        customLabel: String? = nil,
        resetDate: Date,
        remainingTokens: Int64 = 7_300_000,
        totalTokens: Int64 = 10_000_000
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.iconKind = iconKind
        self.remainingPercentage = remainingPercentage
        self.customLabel = customLabel
        self.resetDate = resetDate
        self.remainingTokens = remainingTokens
        self.totalTokens = totalTokens
    }

    public var isDepletedOrCritical: Bool {
        remainingPercentage <= 15.0
    }

    public var status: QuotaStatus {
        if remainingPercentage <= 15.0 {
            return .critical
        } else if remainingPercentage <= 25.0 {
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

    public var displayPercentageString: String {
        if let customLabel = customLabel {
            return customLabel
        }
        return "\(Int(remainingPercentage))%"
    }
}
