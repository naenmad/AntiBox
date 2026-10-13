import Foundation
import SwiftUI
import Combine

@MainActor
public final class DashboardViewModel: ObservableObject {
    @Published public var accounts: [Account] = []
    @Published public var selectedAccountId: UUID? = nil
    @Published public var currentTime: Date = Date()
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var recommendation: BudgetRecommendation? = nil
    @Published public var showingAddAccountSheet: Bool = false

    private let keychainManager = KeychainManager.shared
    private let notificationManager = NotificationManager.shared
    private let budgetAdvisor = SmartBudgetAdvisor.shared
    private let syncService = LocalProxySyncService.shared
    private let directEngine = DirectCloudCodeEngine.shared
    private let accountStore = AntiBoxAccountStore.shared

    @Published public var syncFrequency: SyncFrequency = .balanced
    @Published public var autoRotateFocus: AutoSwitchQuotaFocus = .claude
    @Published public var notifyLowQuota: Bool = true
    @Published public var lowQuotaThreshold: Double = 15.0
    @Published public var trackImageQuota: Bool = true
    @Published public var importStatusMessage: String? = nil

    private let independentEngine = IndependentQuotaEngine.shared
    private let accountsStorageKey = "com.antibox.saved_accounts_v3"

    public struct MenuBarMetricItem: Identifiable, Sendable {
        public let id: String
        public let label: String
        public let percentage: Int
        public let iconSystemName: String
    }

    @Published public var menuBarShowGemini: Bool = true {
        didSet { UserDefaults.standard.set(menuBarShowGemini, forKey: "com.antibox.bar_show_gemini") }
    }
    @Published public var menuBarShowClaudeGpt: Bool = true {
        didSet { UserDefaults.standard.set(menuBarShowClaudeGpt, forKey: "com.antibox.bar_show_claude_gpt") }
    }
    @Published public var menuBarShowImage: Bool = false {
        didSet { UserDefaults.standard.set(menuBarShowImage, forKey: "com.antibox.bar_show_image") }
    }

    /// Single compact formatted text string for macOS MenuBarExtra label
    public var menuBarSummaryText: String {
        guard let account = selectedAccount else { return "AntiBox" }
        var parts: [String] = []

        if menuBarShowGemini {
            let pct = Int(account.remainingPercentage)
            parts.append("G: \(pct)%")
        }

        if menuBarShowClaudeGpt {
            let tpGroup = currentQuotaGroups.first(where: { $0.id == "claude-gpt" })
            let pct = Int(tpGroup?.percentage ?? 0.0)
            parts.append("C: \(pct)%")
        }

        if menuBarShowImage {
            let imgPct = account.imageQuotaPercentage ?? currentQuotaGroups.first(where: { $0.id == "gemini" })?.imageQuota?.percentage
            if let p = imgPct {
                parts.append("Img: \(Int(p))%")
            }
        }

        if parts.isEmpty {
            return "\(Int(account.remainingPercentage))%"
        }
        return parts.joined(separator: " • ")
    }

    public var menuBarActiveMetrics: [MenuBarMetricItem] {
        guard let account = selectedAccount else { return [] }
        var items: [MenuBarMetricItem] = []

        if menuBarShowGemini {
            let pct = Int(account.remainingPercentage)
            items.append(MenuBarMetricItem(id: "gemini", label: "Gemini", percentage: pct, iconSystemName: "sparkles"))
        }

        if menuBarShowClaudeGpt {
            let tpGroup = currentQuotaGroups.first(where: { $0.id == "claude-gpt" })
            let pct = Int(tpGroup?.percentage ?? 0.0)
            items.append(MenuBarMetricItem(id: "claude-gpt", label: "Claude", percentage: pct, iconSystemName: "cpu"))
        }

        if menuBarShowImage {
            let imgPct = account.imageQuotaPercentage ?? currentQuotaGroups.first(where: { $0.id == "gemini" })?.imageQuota?.percentage
            if let p = imgPct {
                items.append(MenuBarMetricItem(id: "image", label: "Image", percentage: Int(p), iconSystemName: "photo.fill"))
            }
        }

        return items
    }

    // Antigravity IDE Synchronization State
    @Published public var activeIDEAccountEmail: String? = nil
    @Published public var ideSwitchStatusMessage: String? = nil
    @Published public var isSwitchingIDE: Bool = false
    public let ideSyncService = AntigravityIDESyncService.shared

    // Zed IDE (Antigravity ACP) Synchronization State
    @Published public var activeZedACPEmail: String? = nil
    @Published public var isZedACPRunning: Bool = false
    @Published public var isSwitchingZedACP: Bool = false
    @Published public var zedACPSwitchStatusMessage: String? = nil
    @Published public var isZedACPSwitchSuccess: Bool = true
    @Published public var autoRotateZedACPEnabled: Bool = false
    public let zedACPSyncService = ZedACPSyncService.shared

    private var secondTimer: AnyCancellable?
    private var syncTimer: AnyCancellable?

    public init() {
        self.menuBarShowGemini = UserDefaults.standard.object(forKey: "com.antibox.bar_show_gemini") as? Bool ?? true
        self.menuBarShowClaudeGpt = UserDefaults.standard.object(forKey: "com.antibox.bar_show_claude_gpt") as? Bool ?? true
        self.menuBarShowImage = UserDefaults.standard.object(forKey: "com.antibox.bar_show_image") as? Bool ?? false
        self.autoRotateZedACPEnabled = UserDefaults.standard.object(forKey: "com.antibox.auto_rotate_zed_acp") as? Bool ?? false
        if let freqRaw = UserDefaults.standard.string(forKey: "com.antibox.sync_frequency"),
           let freq = SyncFrequency(rawValue: freqRaw) {
            self.syncFrequency = freq
        }
        if let focusRaw = UserDefaults.standard.string(forKey: "com.antibox.auto_rotate_focus"),
           let focus = AutoSwitchQuotaFocus(rawValue: focusRaw) {
            self.autoRotateFocus = focus
        }

        notificationManager.requestAuthorization()
        loadInitialData()
        startRealtimeTickers()
        checkActiveIDEAccount()
        checkActiveZedACP()
    }

    deinit {
        secondTimer?.cancel()
        syncTimer?.cancel()
    }

    private func loadInitialData() {
        // Priority 1: Load from AntiBox's independent store
        let stored = accountStore.loadAccounts()
        if !stored.isEmpty {
            self.accounts = stored
            let (zedEmail, matchedAcc) = zedACPSyncService.getActiveAccount(from: stored)
            self.activeZedACPEmail = zedEmail
            self.selectedAccountId = matchedAcc?.id ?? stored.first?.id
        } else {
            // First run: migrate accounts once into AntiBox independent store
            let migration = accountStore.migrateFromAntigravityTools()
            if migration.success {
                self.accounts = accountStore.loadAccounts()
                let (zedEmail, matchedAcc) = zedACPSyncService.getActiveAccount(from: self.accounts)
                self.activeZedACPEmail = zedEmail
                self.selectedAccountId = matchedAcc?.id ?? accounts.first?.id
            } else if syncService.isAvailable, let localSync = syncService.syncFromLocalStore() {
                self.accounts = localSync.accounts
                self.selectedAccountId = localSync.currentAccountId ?? accounts.first?.id
                accountStore.saveAccounts(self.accounts)
            } else {
                loadPersistedAccounts()
                if accounts.isEmpty {
                    seedRealWorldAccounts()
                }
                selectedAccountId = accounts.first?.id
            }
        }
        recalculateBudget()
    }

    public func startRealtimeTickers() {
        // Live 1-second countdown clock ticker
        secondTimer?.cancel()
        secondTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                guard let self = self else { return }
                self.currentTime = now
                // Periodic background check of active IDE / ACP state every 5 seconds
                if Int(now.timeIntervalSince1970) % 5 == 0 {
                    self.checkActiveZedACP()
                    self.checkActiveIDEAccount()
                }
            }

        syncTimer?.cancel()
        if let interval = syncFrequency.intervalSeconds {
            syncTimer = Timer.publish(every: interval, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    Task { [weak self] in
                        // Background sync refreshes only the active account to save power & quota
                        await self?.refreshAllQuotas(activeAccountOnly: true)
                    }
                }
        }
    }

    public func updateSyncFrequency(_ frequency: SyncFrequency) {
        self.syncFrequency = frequency
        UserDefaults.standard.set(frequency.rawValue, forKey: "com.antibox.sync_frequency")
        startRealtimeTickers()
    }

    public func setAutoRotateFocus(_ focus: AutoSwitchQuotaFocus) {
        self.autoRotateFocus = focus
        UserDefaults.standard.set(focus.rawValue, forKey: "com.antibox.auto_rotate_focus")
    }

    private func performBackgroundSync() {
        Task {
            await refreshAllQuotas(activeAccountOnly: true)
        }
    }

    /// Currently active account for focused model quota inspection
    public var selectedAccount: Account? {
        if let id = selectedAccountId, let acc = accounts.first(where: { $0.id == id }) {
            return acc
        }
        if let zedEmail = activeZedACPEmail, let acc = accounts.first(where: { $0.email.lowercased() == zedEmail.lowercased() }) {
            return acc
        }
        if let ideEmail = activeIDEAccountEmail, let acc = accounts.first(where: { $0.email.lowercased() == ideEmail.lowercased() }) {
            return acc
        }
        return accounts.first
    }

    /// Items to display in the main quota indicator list
    public var currentQuotaItems: [QuotaItem] {
        if let account = selectedAccount, !account.quotas.isEmpty {
            return account.quotas
        }
        return accounts.flatMap { $0.quotas }
    }

    /// Two core groups (Gemini vs Claude/GPT-OSS) to keep view concise and organized
    public var currentQuotaGroups: [QuotaGroup] {
        let items = currentQuotaItems
        let geminiModels = items.filter { $0.provider == .gemini && !$0.name.lowercased().contains("gpt") }
        let thirdPartyModels = items.filter { $0.provider == .claude || $0.name.lowercased().contains("gpt") }

        // Gemini Group
        let geminiPct = selectedAccount?.remainingPercentage ?? (geminiModels.first?.remainingPercentage ?? 73.0)
        let geminiReset = geminiModels.first?.resetDate ?? Date().addingTimeInterval(17940)
        let geminiCountdown = geminiModels.first?.countdownString(at: currentTime) ?? "4h 59m"

        // Gemini Image Quota (gemini-3.1-flash-image)
        var geminiImageQuota: ImageQuota? = nil
        if trackImageQuota {
            if let imgItem = geminiModels.first(where: { $0.name.lowercased().contains("image") }) {
                geminiImageQuota = ImageQuota(
                    percentage: imgItem.remainingPercentage,
                    countdownString: imgItem.countdownString(at: currentTime),
                    resetDate: imgItem.resetDate,
                    modelName: imgItem.name
                )
            } else if let imgPct = selectedAccount?.imageQuotaPercentage, let imgDate = selectedAccount?.imageQuotaResetDate {
                geminiImageQuota = ImageQuota(
                    percentage: imgPct,
                    countdownString: selectedAccount?.imageQuotaCountdown ?? "2d 1h",
                    resetDate: imgDate
                )
            }
        }

        let geminiGroup = QuotaGroup(
            id: "gemini",
            title: "Google Gemini",
            iconName: "sparkle",
            accentColor: Color.cyan,
            percentage: geminiPct,
            countdownString: geminiCountdown,
            resetDate: geminiReset,
            description: "Gemini Flash, Pro, and Specialized agents",
            models: geminiModels,
            imageQuota: geminiImageQuota
        )

        // Claude & GPT Group
        let thirdPartyPct = thirdPartyModels.map { $0.remainingPercentage }.min() ?? 0.0
        let thirdPartyReset = thirdPartyModels.first?.resetDate ?? Date().addingTimeInterval(230400)
        let thirdPartyCountdown = thirdPartyModels.first?.countdownString(at: currentTime) ?? "2d 16h"

        let thirdPartyGroup = QuotaGroup(
            id: "claude-gpt",
            title: "Claude & GPT-OSS",
            iconName: "sun.max.fill",
            accentColor: Color.orange,
            percentage: thirdPartyPct,
            customLabel: thirdPartyPct <= 0 ? "Weekly 0%" : "\(Int(thirdPartyPct))%",
            countdownString: thirdPartyCountdown,
            resetDate: thirdPartyReset,
            description: "Claude Sonnet, Opus, and GPT models",
            models: thirdPartyModels
        )

        return [geminiGroup, thirdPartyGroup]
    }

    public func updateAccountTier(id: UUID, tier: AccountTier) {
        if let idx = accounts.firstIndex(where: { $0.id == id }) {
            accounts[idx].accountTier = tier
            saveAccounts()
        }
    }

    // MARK: - Quota Refresh

    public func refreshAllQuotas(activeAccountOnly: Bool = false) async {
        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
            recalculateBudget()
            saveAccounts()
        }

        var updated = self.accounts
        let targetIndices: [Int]
        if activeAccountOnly, let current = selectedAccount, let idx = updated.firstIndex(where: { $0.id == current.id }) {
            targetIndices = [idx]
        } else {
            targetIndices = Array(0..<updated.count)
        }

        for i in targetIndices {
            let acc = updated[i]
            guard acc.isActive else { continue }

            // Check Keychain for OAuth refresh token
            if let refreshToken = try? keychainManager.retrieve(forAccount: acc.id), !refreshToken.isEmpty {
                do {
                    let accessToken = try await directEngine.refreshAccessToken(refreshToken: refreshToken)
                    let directRes = try await directEngine.fetchDirectQuotas(accessToken: accessToken)

                    updated[i].customRemainingPercentage = directRes.geminiWeeklyPercentage
                    updated[i].resetDate = directRes.geminiResetDate
                    updated[i].imageQuotaPercentage = directRes.imageQuotaPercentage
                    updated[i].imageQuotaResetDate = directRes.imageQuotaResetDate
                    if let imgDate = directRes.imageQuotaResetDate {
                        updated[i].imageQuotaCountdown = Account.formatCountdown(from: imgDate, at: currentTime)
                    }
                    if !directRes.models.isEmpty {
                        updated[i].quotas = directRes.models
                    }
                } catch {
                    print("[AntiBox] Direct Google API sync failed for \(acc.email): \(error)")
                }
            } else if let apiKey = try? keychainManager.retrieve(forAccount: acc.id), !apiKey.isEmpty {
                if acc.provider == .gemini {
                    if let live = try? await independentEngine.fetchGeminiDirectQuota(apiKey: apiKey) {
                        updated[i].quotas = live
                    }
                } else {
                    if let live = try? await independentEngine.fetchClaudeDirectQuota(apiKey: apiKey) {
                        updated[i].quotas = live
                    }
                }
            }
        }

        self.accounts = updated

        if notifyLowQuota {
            for account in accounts where account.isActive {
                notificationManager.evaluateQuotaThreshold(for: account, threshold: lowQuotaThreshold)
            }
        }

        // Auto-Rotate Zed ACP if active account has depleted/low quota (<= 5%)
        if autoRotateZedACPEnabled {
            let (rotated, oldEmail, newEmail, reason) = await zedACPSyncService.checkAndAutoRotateIfNeeded(
                accounts: self.accounts,
                focus: autoRotateFocus,
                thresholdPercent: 5.0
            )
            if rotated, let old = oldEmail, let new = newEmail {
                if let newAcc = accounts.first(where: { $0.email.lowercased() == new.lowercased() }) {
                    self.selectedAccountId = newAcc.id
                }
                checkActiveZedACP()
                let reasonText = reason ?? "quota depleted"
                zedACPSwitchStatusMessage = "Auto-Switched to \(new) (\(reasonText))"
                notificationManager.notifyAutoSwitched(oldEmail: old, newEmail: new, reason: reasonText)
                Task {
                    try? await Task.sleep(nanoseconds: 8_000_000_000)
                    if self.zedACPSwitchStatusMessage?.contains("Auto-Switched") == true {
                        self.zedACPSwitchStatusMessage = nil
                    }
                }
            }
        }
    }

    public func importAccountsFromAntigravityTools() {
        let migration = accountStore.migrateFromAntigravityTools()
        if migration.success {
            self.accounts = accountStore.loadAccounts()
            let (zedEmail, matchedAcc) = zedACPSyncService.getActiveAccount(from: self.accounts)
            self.activeZedACPEmail = zedEmail
            if self.selectedAccountId == nil {
                self.selectedAccountId = matchedAcc?.id ?? accounts.first?.id
            }
            importStatusMessage = "Successfully imported \(migration.importedCount) accounts!"
            Task {
                await refreshAllQuotas(activeAccountOnly: false)
            }
        } else {
            importStatusMessage = "No accounts found in ~/.antigravity_tools."
        }

        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            self.importStatusMessage = nil
        }
    }

    // MARK: - Account Management & IDE Hot-Switching

    public func selectAccount(id: UUID) {
        selectedAccountId = id
        recalculateBudget()
    }

    public func checkActiveIDEAccount() {
        let (email, _) = ideSyncService.getActiveIDEAccount()
        self.activeIDEAccountEmail = email
    }

    /// Hot-switches the open Antigravity IDE directly to the target account credentials
    public func switchAntigravityIDE(to accountId: UUID) async {
        guard let account = accounts.first(where: { $0.id == accountId }) else { return }
        isSwitchingIDE = true
        selectAccount(id: accountId)

        let result = await ideSyncService.switchToAccount(account: account)
        isSwitchingIDE = false
        ideSwitchStatusMessage = result.message
        checkActiveIDEAccount()
        recalculateBudget()

        // Clear status message after 4 seconds
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if self.ideSwitchStatusMessage == result.message {
                self.ideSwitchStatusMessage = nil
            }
        }
    }

    // MARK: - Zed IDE (Antigravity ACP) Management

    public func checkActiveZedACP() {
        self.isZedACPRunning = zedACPSyncService.isZedACPRunning
        let (email, matchedAccount) = zedACPSyncService.getActiveAccount(from: accounts)
        self.activeZedACPEmail = email
        if selectedAccountId == nil {
            if let matched = matchedAccount {
                self.selectedAccountId = matched.id
                recalculateBudget()
            } else if let email = email, let matched = accounts.first(where: { $0.email.lowercased() == email.lowercased() }) {
                self.selectedAccountId = matched.id
                recalculateBudget()
            }
        }
    }

    public func toggleAutoRotateZedACP() {
        autoRotateZedACPEnabled.toggle()
        UserDefaults.standard.set(autoRotateZedACPEnabled, forKey: "com.antibox.auto_rotate_zed_acp")
    }

    /// Hot-switches Zed Antigravity ACP directly to the target account credentials
    public func switchZedACP(to accountId: UUID) async {
        guard let account = accounts.first(where: { $0.id == accountId }) else { return }
        isSwitchingZedACP = true
        self.selectedAccountId = accountId
        self.activeZedACPEmail = account.email.isEmpty ? account.name : account.email
        recalculateBudget()

        let result = await zedACPSyncService.switchToAccount(account: account)
        isSwitchingZedACP = false
        isZedACPSwitchSuccess = result.success
        zedACPSwitchStatusMessage = result.message
        self.selectedAccountId = accountId
        checkActiveZedACP()
        recalculateBudget()

        // Clear status message after 4 seconds
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if self.zedACPSwitchStatusMessage == result.message {
                self.zedACPSwitchStatusMessage = nil
            }
        }
    }

    /// Connects a new Antigravity account directly via native Google OAuth login popup
    public func connectAntigravityAccountViaOAuth() async {
        do {
            let result = try await OAuthSignInManager.shared.startAntigravitySignIn()

            let existingIdx = accounts.firstIndex(where: { $0.email.lowercased() == result.email.lowercased() })
            let accountId = existingIdx != nil ? accounts[existingIdx!].id : UUID()

            // Save refresh token securely in private credentials vault
            if !result.refreshToken.isEmpty {
                _ = try? keychainManager.save(token: result.refreshToken, forAccount: accountId)
            }

            var newAccount = Account(
                id: accountId,
                name: result.name,
                email: result.email,
                provider: .gemini,
                tier: "PRO",
                totalQuotaTokens: 10_000_000,
                usedQuotaTokens: 2_700_000,
                resetDate: Date().addingTimeInterval(17940),
                isActive: true
            )

            // Immediately query live quotas via Google Cloud Code API
            if let directResult = try? await directEngine.fetchDirectQuotas(accessToken: result.accessToken) {
                newAccount.customRemainingPercentage = directResult.geminiWeeklyPercentage
                newAccount.resetDate = directResult.geminiResetDate
                newAccount.imageQuotaPercentage = directResult.imageQuotaPercentage
                newAccount.imageQuotaResetDate = directResult.imageQuotaResetDate
                if let imgDate = directResult.imageQuotaResetDate {
                    newAccount.imageQuotaCountdown = Account.formatCountdown(from: imgDate, at: currentTime)
                }
                newAccount.quotas = directResult.models
            }

            if let idx = existingIdx {
                accounts[idx] = newAccount
            } else {
                accounts.append(newAccount)
            }

            selectedAccountId = accountId
            saveAccounts()
            recalculateBudget()
            showingAddAccountSheet = false
        } catch {
            print("[AntiBox] OAuth connect failed: \(error)")
        }
    }

    public func addAccount(
        name: String,
        email: String = "",
        provider: AIProvider,
        tier: String,
        totalTokens: Int64,
        usedTokens: Int64,
        resetDate: Date,
        apiKey: String
    ) {
        let newAccount = Account(
            name: name,
            email: email.isEmpty ? name : email,
            provider: provider,
            tier: tier,
            totalQuotaTokens: totalTokens,
            usedQuotaTokens: usedTokens,
            resetDate: resetDate,
            quotas: [
                QuotaItem(
                    name: "\(name) Quota",
                    provider: provider,
                    iconKind: provider == .gemini ? .sparkle : .sunburst,
                    remainingPercentage: totalTokens > 0 ? (Double(totalTokens - usedTokens) / Double(totalTokens)) * 100.0 : 0.0,
                    resetDate: resetDate,
                    remainingTokens: max(0, totalTokens - usedTokens),
                    totalTokens: totalTokens
                )
            ]
        )

        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                try keychainManager.save(token: apiKey, forAccount: newAccount.id)
            } catch {
                print("Failed to save credentials in Keychain: \(error.localizedDescription)")
            }
        }

        accounts.append(newAccount)
        saveAccounts()
        recalculateBudget()
        notificationManager.evaluateQuotaThreshold(for: newAccount)
    }

    public func deleteAccount(id: UUID) {
        keychainManager.delete(forAccount: id)
        accounts.removeAll { $0.id == id }
        if selectedAccountId == id {
            selectedAccountId = accounts.first?.id
        }
        saveAccounts()
        recalculateBudget()
    }

    public func toggleAccountStatus(id: UUID) {
        if let index = accounts.firstIndex(where: { $0.id == id }) {
            accounts[index].isActive.toggle()
            saveAccounts()
            recalculateBudget()
        }
    }

    // MARK: - Persistence

    private func saveAccounts() {
        accountStore.saveAccounts(accounts)
        if let encoded = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(encoded, forKey: accountsStorageKey)
        }
    }

    private func loadPersistedAccounts() {
        guard let data = UserDefaults.standard.data(forKey: accountsStorageKey),
              let decoded = try? JSONDecoder().decode([Account].self, from: data) else {
            return
        }
        self.accounts = decoded
    }

    private func recalculateBudget() {
        self.recommendation = budgetAdvisor.calculateRecommendation(accounts: accounts)
    }

    // MARK: - Fallback Seed Data

    private func seedRealWorldAccounts() {
        let calendar = Calendar.current
        let now = Date()

        let geminiResetDate = calendar.date(byAdding: .minute, value: 299, to: now) ?? now.addingTimeInterval(17940)
        let claudeWeeklyResetDate = calendar.date(byAdding: .minute, value: (2 * 1440) + (16 * 60), to: now) ?? now.addingTimeInterval(230400)

        let primaryAccount = Account(
            name: "Tune Fix",
            email: "tunefix.id@gmail.com",
            provider: .gemini,
            tier: "PRO",
            totalQuotaTokens: 10_000_000,
            usedQuotaTokens: 2_700_000,
            resetDate: geminiResetDate,
            isActive: true,
            quotas: [
                QuotaItem(name: "Gemini 3.8 Flash (Medium)", provider: .gemini, iconKind: .sparkle, remainingPercentage: 73.0, resetDate: geminiResetDate),
                QuotaItem(name: "Gemini 3.1 Flash Lite", provider: .gemini, iconKind: .robot, remainingPercentage: 73.0, resetDate: geminiResetDate),
                QuotaItem(name: "Gemini 3.1 Pro (High)", provider: .gemini, iconKind: .sparkle, remainingPercentage: 73.0, resetDate: geminiResetDate),
                QuotaItem(name: "Claude Opus 4.6 (Thinking)", provider: .claude, iconKind: .sunburst, remainingPercentage: 0.0, customLabel: "Weekly 0%", resetDate: claudeWeeklyResetDate),
                QuotaItem(name: "Claude Sonnet 4.6 (Thinking)", provider: .claude, iconKind: .sunburst, remainingPercentage: 0.0, customLabel: "Weekly 0%", resetDate: claudeWeeklyResetDate)
            ]
        )

        accounts = [primaryAccount]
        saveAccounts()
    }
}
