import Foundation

/// Independent account storage engine for AntiBox
/// Persists accounts in ~/Library/Application Support/AntiBox/accounts.json
/// and securely saves OAuth refresh tokens in Apple Keychain.
public final class AntiBoxAccountStore: Sendable {
    public static let shared = AntiBoxAccountStore()

    private let appSupportDir: URL
    private let accountsFile: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let zedDir = appSupport.appendingPathComponent("ZedGravity", isDirectory: true)
        let oldDir = appSupport.appendingPathComponent("AntiBox", isDirectory: true)

        if !FileManager.default.fileExists(atPath: zedDir.path) {
            try? FileManager.default.createDirectory(at: zedDir, withIntermediateDirectories: true)
            let oldAccounts = oldDir.appendingPathComponent("accounts.json")
            if FileManager.default.fileExists(atPath: oldAccounts.path) {
                try? FileManager.default.copyItem(at: oldAccounts, to: zedDir.appendingPathComponent("accounts.json"))
            }
        }

        self.appSupportDir = zedDir
        self.accountsFile = zedDir.appendingPathComponent("accounts.json")
    }

    public var hasLocalAccounts: Bool {
        FileManager.default.fileExists(atPath: accountsFile.path)
    }

    public func loadAccounts() -> [Account] {
        guard FileManager.default.fileExists(atPath: accountsFile.path),
              let data = try? Data(contentsOf: accountsFile),
              let accounts = try? JSONDecoder().decode([Account].self, from: data) else {
            return []
        }
        return accounts
    }

    public func saveAccounts(_ accounts: [Account]) {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        try? data.write(to: accountsFile, options: [.atomic])
    }

    /// One-time automated migration to import accounts from ~/.antigravity_tools into AntiBox
    /// and save refresh tokens into Apple Keychain, fully detaching AntiBox thereafter.
    @discardableResult
    public func migrateFromAntigravityTools() -> (importedCount: Int, success: Bool) {
        let toolsBase = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".antigravity_tools")
        let toolsAccountsFile = toolsBase.appendingPathComponent("accounts.json")

        guard FileManager.default.fileExists(atPath: toolsAccountsFile.path),
              let data = try? Data(contentsOf: toolsAccountsFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accountsArr = json["accounts"] as? [[String: Any]] else {
            return (0, false)
        }

        var imported: [Account] = []
        let keychain = KeychainManager.shared

        for acc in accountsArr {
            guard let idStr = acc["id"] as? String,
                  let uuid = UUID(uuidString: idStr),
                  let email = acc["email"] as? String else {
                continue
            }

            let name = (acc["name"] as? String) ?? email
            let detailFile = toolsBase.appendingPathComponent("accounts").appendingPathComponent("\(idStr).json")

            var tierStr = "PRO"
            var refreshToken = ""

            if let detailData = try? Data(contentsOf: detailFile),
               let detailJson = try? JSONSerialization.jsonObject(with: detailData) as? [String: Any] {

                if let tokenObj = detailJson["token"] as? [String: Any],
                   let rf = tokenObj["refresh_token"] as? String {
                    refreshToken = rf
                }

                if let quotaObj = detailJson["quota"] as? [String: Any],
                   let subTier = quotaObj["subscription_tier"] as? String {
                    tierStr = subTier.uppercased()
                }
            }

            // Save refresh token securely in Keychain for direct standalone usage
            if !refreshToken.isEmpty {
                _ = try? keychain.save(token: refreshToken, forAccount: uuid)
            }

            let newAccount = Account(
                id: uuid,
                name: name,
                email: email,
                provider: .gemini,
                tier: tierStr,
                totalQuotaTokens: 10_000_000,
                usedQuotaTokens: 2_700_000,
                resetDate: Date().addingTimeInterval(17940),
                isActive: true,
                quotas: [],
                customRemainingPercentage: 73.4
            )

            imported.append(newAccount)
        }

        guard !imported.isEmpty else {
            return (0, false)
        }

        saveAccounts(imported)
        return (imported.count, true)
    }
}
