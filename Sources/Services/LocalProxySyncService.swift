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

            var geminiBucketPct: Double = 100.0
            var claudeBucketPct: Double = 100.0
            _ = claudeBucketPct
            var hasQuotaGroups = false
            var accountTierString = "FREE"

            if let detailData = try? Data(contentsOf: detailFile),
               let detailJson = try? JSONSerialization.jsonObject(with: detailData) as? [String: Any],
               let quotaObj = detailJson["quota"] as? [String: Any] {

                // Parse authoritative quota groups (Gemini Models & Claude/GPT models)
                if let quotaGroups = quotaObj["quota_groups"] as? [[String: Any]] {
                    hasQuotaGroups = true
                    for group in quotaGroups {
                        let dName = (group["display_name"] as? String) ?? ""
                        if let buckets = group["buckets"] as? [[String: Any]] {
                            for b in buckets {
                                if (b["window"] as? String) == "weekly" {
                                    let remFrac = (b["remaining_fraction"] as? Double) ?? 1.0
                                    let pct = remFrac * 100.0
                                    if dName.contains("Gemini") || (b["bucket_id"] as? String) == "gemini-weekly" {
                                        geminiBucketPct = pct
                                    } else if dName.contains("Claude") || (b["bucket_id"] as? String) == "3p-weekly" {
                                        claudeBucketPct = pct
                                    }
                                }
                            }
                        }
                    }
                }

                if let modelsArr = quotaObj["models"] as? [[String: Any]] {
                    var seenNames: Set<String> = []

                    for model in modelsArr {
                        let rawName = (model["name"] as? String) ?? ""
                        let displayName = (model["display_name"] as? String) ?? rawName

                        // Filter out internal aliases or duplicates
                        guard displayName != "None" && !rawName.isEmpty && !seenNames.contains(displayName) else {
                            continue
                        }
                        seenNames.insert(displayName)

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

                        let maxTokens = Int64((model["max_tokens"] as? Int) ?? 1_000_000)
                        let remaining = Int64(Double(maxTokens) * (pct / 100.0))
                        totalRemainingTokens += remaining
                        totalCapacityTokens += maxTokens

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

                // Parse subscription tier (e.g. FREE, PLUS, PRO, ULTRA)
                if let subTier = quotaObj["subscription_tier"] as? String, !subTier.isEmpty {
                    accountTierString = subTier.uppercased()
                }
            }

            let providerGuess: AIProvider = quotaItems.contains(where: { $0.provider == .claude }) ? .claude : .gemini

            // The account's primary active percentage is the Gemini weekly quota (e.g. 73.4%)
            let authoritativePct: Double = hasQuotaGroups ? geminiBucketPct : (totalCapacityTokens > 0 ? (Double(totalRemainingTokens) / Double(totalCapacityTokens)) * 100.0 : 100.0)

            // Extract dedicated Gemini Image Quota (gemini-3.1-flash-image)
            var imagePct: Double? = nil
            var imageReset: Date? = nil
            var imageCountdownStr: String? = nil
            if let imgItem = quotaItems.first(where: { $0.name.lowercased().contains("image") }) {
                imagePct = imgItem.remainingPercentage
                imageReset = imgItem.resetDate
                imageCountdownStr = imgItem.countdownString(at: Date())
            }

            let account = Account(
                id: uuid,
                name: name,
                email: email,
                provider: providerGuess,
                tier: accountTierString,
                totalQuotaTokens: max(totalCapacityTokens, 10_000_000),
                usedQuotaTokens: max(0, totalCapacityTokens - totalRemainingTokens),
                resetDate: earliestReset,
                isActive: !isDisabled,
                quotas: quotaItems,
                customRemainingPercentage: authoritativePct,
                imageQuotaPercentage: imagePct,
                imageQuotaResetDate: imageReset,
                imageQuotaCountdown: imageCountdownStr
            )

            syncedAccounts.append(account)
        }

        return SyncResult(accounts: syncedAccounts, currentAccountId: currentUUID)
    }
}
