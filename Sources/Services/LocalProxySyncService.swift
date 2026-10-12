import Foundation

/// Real-time synchronization service that reads local account and quota states directly from ~/.antigravity_tools
public final class LocalProxySyncService: Sendable {
    public static let shared = LocalProxySyncService()

    private let baseDirectory: URL

    private init() {
        self.baseDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".antigravity_tools")
    }

    public var isAvailable: Bool {
        let accountsFile = baseDirectory.appendingPathComponent("accounts.json")
        return FileManager.default.fileExists(atPath: accountsFile.path)
    }

    public struct SyncResult: Sendable {
        public let accounts: [Account]
        public let currentAccountId: UUID?
    }

    public func syncFromLocalStore() -> SyncResult? {
        guard isAvailable else { return nil }

        let accountsFile = baseDirectory.appendingPathComponent("accounts.json")
        guard let data = try? Data(contentsOf: accountsFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accountsArray = json["accounts"] as? [[String: Any]] else {
            return nil
        }

        let currentIdString = json["current_account_id"] as? String
        let currentUUID = currentIdString != nil ? UUID(uuidString: currentIdString!) : nil

        let isoFormatter = ISO8601DateFormatter()
        var syncedAccounts: [Account] = []

        for accDict in accountsArray {
            guard let idStr = accDict["id"] as? String,
                  let uuid = UUID(uuidString: idStr),
                  let email = accDict["email"] as? String else {
                continue
            }

            let name = (accDict["name"] as? String) ?? email
            let isDisabled = (accDict["disabled"] as? Bool) ?? false

            // Read specific account quota detail file
            let detailFile = baseDirectory
                .appendingPathComponent("accounts")
                .appendingPathComponent("\(idStr).json")

            var quotaItems: [QuotaItem] = []
            var earliestReset: Date = Date().addingTimeInterval(86400 * 3)
            var totalRemainingTokens: Int64 = 0
            var totalCapacityTokens: Int64 = 0

            if let detailData = try? Data(contentsOf: detailFile),
               let detailJson = try? JSONSerialization.jsonObject(with: detailData) as? [String: Any],
               let quotaObj = detailJson["quota"] as? [String: Any],
               let modelsArr = quotaObj["models"] as? [[String: Any]] {

                for model in modelsArr {
                    let rawName = (model["name"] as? String) ?? ""
                    let displayName = (model["display_name"] as? String) ?? rawName
                    let pct = Double((model["percentage"] as? Int) ?? 100)
                    let resetStr = (model["reset_time"] as? String) ?? ""
                    let resetDate = isoFormatter.date(from: resetStr) ?? Date().addingTimeInterval(17940)

                    if resetDate < earliestReset && resetDate > Date() {
                        earliestReset = resetDate
                    }

                    let provider: AIProvider = rawName.lowercased().contains("claude") ? .claude : .gemini

                    let iconKind: QuotaIconKind
                    if rawName.lowercased().contains("lite") {
                        iconKind = .robot
                    } else if rawName.lowercased().contains("claude") {
                        iconKind = .sunburst
                    } else {
                        iconKind = .sparkle
                    }

                    let customLabel: String?
                    if pct <= 0 {
                        customLabel = provider == .claude ? "Weekly 0%" : "0%"
                    } else {
                        customLabel = nil
                    }

                    // Estimate token quantities based on model capacity and percentage
                    let maxTokens = Int64((model["max_tokens"] as? Int) ?? 1_000_000)
                    let remaining = Int64(Double(maxTokens) * (pct / 100.0))
                    totalRemainingTokens += remaining
                    totalCapacityTokens += maxTokens

                    // Avoid duplicate placeholder entries
                    if displayName != "None" && !rawName.isEmpty {
                        quotaItems.append(
                            QuotaItem(
                                name: displayName,
                                provider: provider,
                                iconKind: iconKind,
                                remainingPercentage: pct,
                                customLabel: customLabel,
                                resetDate: resetDate,
                                remainingTokens: remaining,
                                totalTokens: maxTokens
                            )
                        )
                    }
                }
            }

            let providerGuess: AIProvider = quotaItems.contains(where: { $0.provider == .claude }) ? .claude : .gemini

            let account = Account(
                id: uuid,
                name: name,
                email: email,
                provider: providerGuess,
                tier: "PRO",
                totalQuotaTokens: max(totalCapacityTokens, 10_000_000),
                usedQuotaTokens: max(0, totalCapacityTokens - totalRemainingTokens),
                resetDate: earliestReset,
                isActive: !isDisabled,
                quotas: quotaItems
            )

            syncedAccounts.append(account)
        }

        return SyncResult(accounts: syncedAccounts, currentAccountId: currentUUID)
    }
}
