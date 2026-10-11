import Foundation

public struct QuotaFetchResult: Sendable {
    public let totalTokens: Int64
    public let usedTokens: Int64
    public let resetDate: Date

    public init(totalTokens: Int64, usedTokens: Int64, resetDate: Date) {
        self.totalTokens = totalTokens
        self.usedTokens = usedTokens
        self.resetDate = resetDate
    }
}

public protocol QuotaServiceProtocol: Sendable {
    func fetchQuota(apiKey: String) async throws -> QuotaFetchResult
}
