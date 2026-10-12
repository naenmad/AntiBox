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

    public enum EngineMode: String, CaseIterable, Identifiable {
        case direct = "Native Direct Engine (Independent)"
        case hybrid = "Hybrid (Direct + Local Sync)"
        case localStore = "Local Antigravity Tools (Legacy)"
        public var id: String { rawValue }
    }

    @Published public var engineMode: EngineMode = .direct
    @Published public var autoRefreshIntervalSeconds: Double = 60.0
    @Published public var notifyLowQuota: Bool = true
    @Published public var lowQuotaThreshold: Double = 15.0
    @Published public var trackImageQuota: Bool = true
    @Published public var standaloneStatus: String = "100% Standalone (Direct to Google Cloud API)"

    private let independentEngine = IndependentQuotaEngine.shared
    private let accountsStorageKey = "com.antibox.saved_accounts_v3"

    public enum MenuBarDisplayMode: String, CaseIterable, Identifiable, Codable {
        case gemini = "gemini"
        case claudeGpt = "claudeGpt"
        case geminiImage = "geminiImage"

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .gemini: return "Gemini Quota"
            case .claudeGpt: return "Claude & GPT-OSS Quota"
            case .geminiImage: return "Gemini Image Quota"
            }
        }

        public var shortLabel: String {
            switch self {
            case .gemini: return "Gemini"
            case .claudeGpt: return "Claude"
            case .geminiImage: return "Image"
            }
        }

        public var iconName: String {
            switch self {
            case .gemini: return "sparkles"
            case .claudeGpt: return "cpu"
            case .geminiImage: return "photo.fill"
            }
        }
    }

    private let menuBarDisplayModeKey = "com.antibox.menuBarDisplayMode"

    @Published public var menuBarDisplayMode: MenuBarDisplayMode = .gemini {
        didSet {
            UserDefaults.standard.set(menuBarDisplayMode.rawValue, forKey: menuBarDisplayModeKey)
        }
    }

    public var currentMenuBarQuota: (percentage: Double?, label: String, icon: String) {
        guard let account = selectedAccount else {
            return (nil, "No Account", "gauge.with.dots.needle.33percent")
        }
        switch menuBarDisplayMode {
        case .gemini:
            let pct = account.remainingPercentage
            return (pct, "\(Int(pct))%", "sparkles")
        case .claudeGpt:
            let tpGroup = currentQuotaGroups.first(where: { $0.id == "claude-gpt" })
            let pct = tpGroup?.percentage ?? 0.0
            return (pct, "\(Int(pct))%", "cpu")
        case .geminiImage:
            let pct = account.imageQuotaPercentage ?? currentQuotaGroups.first(where: { $0.id == "gemini" })?.imageQuota?.percentage
            if let p = pct {
                return (p, "\(Int(p))%", "photo.fill")
            } else {
                return (nil, "N/A", "photo.fill")
            }
        }
    }

    private var secondTimer: AnyCancellable?
    private var syncTimer: AnyCancellable?

    public init() {
        if let savedMode = UserDefaults.standard.string(forKey: menuBarDisplayModeKey),
           let mode = MenuBarDisplayMode(rawValue: savedMode) {
            self.menuBarDisplayMode = mode
        }
        notificationManager.requestAuthorization()
        loadInitialData()
        startRealtimeTickers()
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
            self.selectedAccountId = stored.first?.id
        } else {
            // First run: migrate accounts once into AntiBox independent store
            let migration = accountStore.migrateFromAntigravityTools()
            if migration.success {
                self.accounts = accountStore.loadAccounts()
                self.selectedAccountId = accounts.first?.id
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

    private func startRealtimeTickers() {
        // Live 1-second countdown clock ticker
        secondTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                self?.currentTime = now
            }

        // Live 30-second direct synchronizer
        syncTimer = Timer.publish(every: 30.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.refreshAllQuotas()
                }
            }
    }

    private func performBackgroundSync() {
        Task {
            await refreshAllQuotas()
        }
    }

    /// Currently active account for focused model quota inspection
    public var selectedAccount: Account? {
        if let id = selectedAccountId {
            return accounts.first(where: { $0.id == id }) ?? accounts.first
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

    public func refreshAllQuotas() async {
        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
            recalculateBudget()
            saveAccounts()
        }

        // Direct standalone communication with Google Cloud Code API (No Antigravity Tools required)
        if engineMode == .direct || engineMode == .hybrid {
            var updated = self.accounts
            var directSuccess = false

            for i in 0..<updated.count {
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
                        directSuccess = true
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

            if directSuccess {
                self.accounts = updated
                standaloneStatus = "Active: Direct Standalone Google Cloud API"
                return
            }
        }

        // Fallback only if local proxy is present and direct credentials not yet configured
        if syncService.isAvailable, let localSync = syncService.syncFromLocalStore() {
            self.accounts = localSync.accounts
        }

        for account in accounts where account.isActive {
            notificationManager.evaluateQuotaThreshold(for: account)
        }
    }

    public func detachFromAntigravityTools() {
        let migration = accountStore.migrateFromAntigravityTools()
        if migration.success {
            self.accounts = accountStore.loadAccounts()
            self.engineMode = .direct
            standaloneStatus = "100% Standalone (Migrated \(migration.importedCount) accounts)"
            Task {
                await refreshAllQuotas()
            }
        }
    }

    // MARK: - Account Management

    public func selectAccount(id: UUID) {
        selectedAccountId = id
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
