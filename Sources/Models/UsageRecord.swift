import Foundation
import SwiftData

/// SwiftData persistent entity logging daily token consumption per account
@Model
public final class DailyUsageLog {
    public var id: UUID
    public var accountId: UUID
    public var date: Date
    public var tokensConsumed: Int64
    public var providerRawValue: String

    public init(
        id: UUID = UUID(),
        accountId: UUID,
        date: Date = Date(),
        tokensConsumed: Int64,
        provider: AIProvider
    ) {
        self.id = id
        self.accountId = accountId
        self.date = date
        self.tokensConsumed = tokensConsumed
        self.providerRawValue = provider.rawValue
    }

    public var provider: AIProvider {
        AIProvider(rawValue: providerRawValue) ?? .gemini
    }
}
