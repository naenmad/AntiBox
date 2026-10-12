import Foundation
import SwiftUI

/// Represents one of the two core quota categories (Gemini vs Claude/GPT)
public struct QuotaGroup: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let iconName: String
    public let accentColor: Color
    public let percentage: Double
    public let customLabel: String?
    public let countdownString: String
    public let resetDate: Date
    public let description: String
    public let models: [QuotaItem]

    public init(
        id: String,
        title: String,
        iconName: String,
        accentColor: Color,
        percentage: Double,
        customLabel: String? = nil,
        countdownString: String,
        resetDate: Date,
        description: String = "",
        models: [QuotaItem] = []
    ) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.accentColor = accentColor
        self.percentage = percentage
        self.customLabel = customLabel
        self.countdownString = countdownString
        self.resetDate = resetDate
        self.description = description
        self.models = models
    }

    public var isDepleted: Bool {
        percentage <= 15.0
    }

    public var displayPercentage: String {
        if let customLabel = customLabel {
            return customLabel
        }
        return "\(Int(percentage))%"
    }
}
