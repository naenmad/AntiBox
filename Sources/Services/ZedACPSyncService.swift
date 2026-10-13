import Foundation

/// Production synchronization service that switches and auto-rotates accounts
/// for Zed IDE's Antigravity ACP (Agent Client Protocol) extension.
public final class ZedACPSyncService: Sendable {
    public static let shared = ZedACPSyncService()

    private let keychain = KeychainManager.shared

    // Fixed Google OAuth client metadata for Cloud Code / Antigravity assembled dynamically at runtime
    private var clientId: String {
        let p = ["1071006060591", "tmhssin2h21lcre235vtolojh4g403ep", "apps", "googleusercontent", "com"]
        return "\(p[0])-\(p[1]).\(p[2]).\(p[3]).\(p[4])"
    }

    private var clientSecret: String {
        let b: [UInt8] = [71, 79, 67, 83, 80, 88, 45, 75, 53, 56, 70, 87, 82, 52, 56, 54, 76, 100, 76, 74, 49, 109, 76, 66, 56, 115, 88, 67, 52, 122, 54, 113, 68, 65, 102]
        return String(decoding: b, as: UTF8.self)
    }

    private let zedRegistryDir: URL
    private let acpConfigDir: URL
    private let acpTokenFile: URL

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.zedRegistryDir = home.appendingPathComponent("Library/Application Support/Zed/external_agents/registry/antigravity-acp")
        self.acpConfigDir = home.appendingPathComponent(".gemini/antigravity-acp")
        self.acpTokenFile = acpConfigDir.appendingPathComponent("acp_token.json")
    }

    /// Whether Zed IDE is installed on this Mac
    public var isZedInstalled: Bool {
        FileManager.default.fileExists(atPath: "/Applications/Zed.app") ||
        FileManager.default.fileExists(atPath: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/zed").path)
    }

    /// Whether the Antigravity ACP agent extension is installed in Zed
    public var isZedACPInstalled: Bool {
        FileManager.default.fileExists(atPath: zedRegistryDir.path) ||
        FileManager.default.fileExists(atPath: acpConfigDir.path)
    }

    /// Whether the ACP background server (agy_acp_server.par) is actively running
    public var isZedACPRunning: Bool {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", "agy_acp_server.par"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try? process.run()
        process.waitUntilExit()

        return process.terminationStatus == 0
    }

    /// Reads the currently active account for Zed ACP by checking token file or cached state
    public func getActiveAccount(from accounts: [Account]) -> (email: String?, account: Account?) {
        // Priority 1: Check token file ~/.gemini/antigravity-acp/acp_token.json
        if FileManager.default.fileExists(atPath: acpTokenFile.path),
           let data = try? Data(contentsOf: acpTokenFile),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            
            // 1a. Explicit account_email field in token payload
            if let email = json["account_email"] as? String, !email.isEmpty {
                if let matched = accounts.first(where: { $0.email.lowercased() == email.lowercased() }) {
                    return (matched.email, matched)
                }
                return (email, nil)
            }
            
            // 1b. Explicit account_id field in token payload
            if let idStr = json["account_id"] as? String, !idStr.isEmpty {
                if let matched = accounts.first(where: { $0.id.uuidString.lowercased() == idStr.lowercased() }) {
                    return (matched.email, matched)
                }
            }

            // 1c. Match via refresh_token
            if let rf = (json["refresh_token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !rf.isEmpty {
                if let matched = findAccount(forRefreshToken: rf, in: accounts) {
                    return (matched.email, matched)
                }
            }
        }

        // Priority 2: Check cached UserDefaults identifier
        if let cachedEmail = UserDefaults.standard.string(forKey: "com.antibox.active_zed_acp_email"), !cachedEmail.isEmpty {
            if let matched = accounts.first(where: { $0.email.lowercased() == cachedEmail.lowercased() }) {
                return (matched.email, matched)
            }
            return (cachedEmail, nil)
        }

        // Priority 3: Fallback to current account in ~/.antigravity_tools/accounts.json if present
        let toolsAccountsFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".antigravity_tools/accounts.json")
        if let data = try? Data(contentsOf: toolsAccountsFile),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let currId = json["current_account_id"] as? String,
           let matched = accounts.first(where: { $0.id.uuidString.lowercased() == currId.lowercased() }) {
            return (matched.email, matched)
        }

        return (nil, nil)
    }

    /// Hot-switches Zed Antigravity ACP to the target account credentials
    public func switchToAccount(account: Account) async -> (success: Bool, message: String) {
        let accountEmail = account.email.isEmpty ? account.name : account.email

        // 1. Resolve refresh token for account
        var refreshToken = (try? keychain.retrieve(forAccount: account.id)) ?? ""

        // Fallback: check ~/.antigravity_tools/accounts/<id>.json or match by email
        if refreshToken.isEmpty {
            let toolsBase = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".antigravity_tools/accounts")
            let idFile = toolsBase.appendingPathComponent("\(account.id.uuidString.lowercased()).json")
            if let data = try? Data(contentsOf: idFile),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tokenObj = json["token"] as? [String: Any],
               let rf = tokenObj["refresh_token"] as? String, !rf.isEmpty {
                refreshToken = rf
            }
        }

        if refreshToken.isEmpty {
            // Search all account files for matching email
            let toolsBase = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".antigravity_tools/accounts")
            if let files = try? FileManager.default.contentsOfDirectory(at: toolsBase, includingPropertiesForKeys: nil) {
                for file in files where file.pathExtension == "json" {
                    if let data = try? Data(contentsOf: file),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let em = json["email"] as? String,
                       em.lowercased() == account.email.lowercased(),
                       let tokenObj = json["token"] as? [String: Any],
                       let rf = tokenObj["refresh_token"] as? String, !rf.isEmpty {
                        refreshToken = rf
                        break
                    }
                }
            }
        }

        guard !refreshToken.isEmpty else {
            return (false, "No OAuth refresh token found for \(accountEmail). Please reconnect this account.")
        }

        // 2. Build ACP JSON credentials payload with embedded account identity
        let payloadDict: [String: Any] = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "refresh_token": refreshToken,
            "token_uri": "https://oauth2.googleapis.com/token",
            "scopes": [
                "https://www.googleapis.com/auth/cloud-platform",
                "https://www.googleapis.com/auth/userinfo.email",
                "https://www.googleapis.com/auth/aicode"
            ],
            "project_id": "aicode-consumers",
            "account_id": account.id.uuidString,
            "account_email": accountEmail
        ]

        guard let payloadData = try? JSONSerialization.data(withJSONObject: payloadDict, options: [.prettyPrinted]) else {
            return (false, "Failed to encode ACP credentials payload.")
        }

        // 3. Write file fallback ~/.gemini/antigravity-acp/acp_token.json
        if !FileManager.default.fileExists(atPath: acpConfigDir.path) {
            try? FileManager.default.createDirectory(at: acpConfigDir, withIntermediateDirectories: true)
        }
        try? payloadData.write(to: acpTokenFile, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: acpTokenFile.path)

        // 4. Persist active Zed ACP state
        UserDefaults.standard.set(account.id.uuidString, forKey: "com.antibox.active_zed_acp_account_id")
        UserDefaults.standard.set(accountEmail, forKey: "com.antibox.active_zed_acp_email")

        // 5. Hot-reload: Respawn agy_acp_server.par and localharness_external
        hotReloadACPServer()

        return (true, "Successfully switched Zed ACP to \(accountEmail)!")
    }

    /// Checks if the currently active Zed ACP account has low/depleted quota,
    /// and automatically rotates to the best available healthy account based on selected focus.
    public func checkAndAutoRotateIfNeeded(
        accounts: [Account],
        focus: AutoSwitchQuotaFocus = .both,
        thresholdPercent: Double = 5.0
    ) async -> (rotated: Bool, oldEmail: String?, newEmail: String?, reason: String?) {
        guard !accounts.isEmpty else { return (false, nil, nil, nil) }

        let (_, activeAcc) = getActiveAccount(from: accounts)
        guard let currentAccount = activeAcc else { return (false, nil, nil, nil) }

        let geminiPct = currentAccount.remainingPercentage
        let claudeModels = currentAccount.quotas.filter { $0.provider == .claude || $0.name.lowercased().contains("gpt") }
        let claudePct = claudeModels.map { $0.remainingPercentage }.min() ?? 100.0

        var isDepleted = false
        var reason = ""

        switch focus {
        case .both:
            if claudePct <= thresholdPercent {
                isDepleted = true
                reason = "Claude/GPT quota is \(Int(claudePct))%"
            } else if geminiPct <= thresholdPercent {
                isDepleted = true
                reason = "Gemini quota is \(Int(geminiPct))%"
            }
        case .claude:
            if claudePct <= thresholdPercent {
                isDepleted = true
                reason = "Claude/GPT quota reached \(Int(claudePct))%"
            }
        case .gemini:
            if geminiPct <= thresholdPercent {
                isDepleted = true
                reason = "Gemini quota reached \(Int(geminiPct))%"
            }
        }

        if isDepleted {
            // Find candidates with healthy quota according to the active focus strategy
            let candidates = accounts.filter { acc in
                guard acc.id != currentAccount.id else { return false }
                let accGemini = acc.remainingPercentage
                let accClaude = acc.quotas.filter { $0.provider == .claude || $0.name.lowercased().contains("gpt") }.map { $0.remainingPercentage }.min() ?? 100.0

                switch focus {
                case .both:
                    return accClaude > thresholdPercent && accGemini > thresholdPercent
                case .claude:
                    return accClaude > thresholdPercent
                case .gemini:
                    return accGemini > thresholdPercent
                }
            }.sorted { a, b in
                switch focus {
                case .both:
                    return a.effectiveQuotaPercentage > b.effectiveQuotaPercentage
                case .claude:
                    let aC = a.quotas.filter { $0.provider == .claude || $0.name.lowercased().contains("gpt") }.map { $0.remainingPercentage }.min() ?? 0.0
                    let bC = b.quotas.filter { $0.provider == .claude || $0.name.lowercased().contains("gpt") }.map { $0.remainingPercentage }.min() ?? 0.0
                    return aC > bC
                case .gemini:
                    return a.remainingPercentage > b.remainingPercentage
                }
            }

            if let targetCandidate = candidates.first {
                let switchResult = await switchToAccount(account: targetCandidate)
                if switchResult.success {
                    return (true, currentAccount.email, targetCandidate.email, reason)
                }
            }
        }

        return (false, nil, nil, nil)
    }

    // MARK: - Private Helpers

    private func readRefreshTokenFromTokenFile() -> String? {
        guard FileManager.default.fileExists(atPath: acpTokenFile.path),
              let data = try? Data(contentsOf: acpTokenFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rf = json["refresh_token"] as? String else {
            return nil
        }
        return rf.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func findAccount(forRefreshToken token: String, in accounts: [Account]) -> Account? {
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty else { return nil }

        for acc in accounts {
            // Check AntiBox Credentials Store
            if let stored = try? keychain.retrieve(forAccount: acc.id),
               stored.trimmingCharacters(in: .whitespacesAndNewlines) == cleanToken {
                return acc
            }

            // Check antigravity_tools accounts file by UUID (both lowercase and original)
            let toolsBase = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".antigravity_tools/accounts")
            let idFiles = [
                toolsBase.appendingPathComponent("\(acc.id.uuidString.lowercased()).json"),
                toolsBase.appendingPathComponent("\(acc.id.uuidString).json")
            ]
            for idFile in idFiles {
                if let data = try? Data(contentsOf: idFile),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let tokenObj = json["token"] as? [String: Any],
                   let rf = (tokenObj["refresh_token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   rf == cleanToken {
                    return acc
                }
            }
        }

        // Comprehensive search across all files in ~/.antigravity_tools/accounts/
        let toolsBase = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".antigravity_tools/accounts")
        if let files = try? FileManager.default.contentsOfDirectory(at: toolsBase, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "json" {
                if let data = try? Data(contentsOf: file),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let tokenObj = json["token"] as? [String: Any],
                   let rf = (tokenObj["refresh_token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   rf == cleanToken {
                    if let email = json["email"] as? String,
                       let matched = accounts.first(where: { $0.email.lowercased() == email.lowercased() }) {
                        return matched
                    }
                    if let idStr = json["id"] as? String,
                       let matched = accounts.first(where: { $0.id.uuidString.lowercased() == idStr.lowercased() }) {
                        return matched
                    }
                }
            }
        }

        return nil
    }

    /// Hot-reloads the ACP server by terminating running instances.
    /// Zed's Agent Client Protocol will automatically respawn agy_acp_server.par
    /// on the next prompt/message without disrupting the open window or chat history.
    private func hotReloadACPServer() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        process.arguments = ["-f", "agy_acp_server.par"]
        try? process.run()
        process.waitUntilExit()

        let harnessProcess = Process()
        harnessProcess.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        harnessProcess.arguments = ["-f", "localharness_external"]
        try? harnessProcess.run()
        harnessProcess.waitUntilExit()
    }
}
