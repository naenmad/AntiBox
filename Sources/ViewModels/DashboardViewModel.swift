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
    public enum EngineMode: String, CaseIterable, Identifiable {
        case hybrid = "Hybrid (Auto)"
        case direct = "Direct API"
        case localStore = "Local Store"
        public var id: String { rawValue }
    }

    @Published public var engineMode: EngineMode = .hybrid
    @Published public var autoRefreshIntervalSeconds: Double = 60.0
    @Published public var notifyLowQuota: Bool = true
    @Published public var lowQuotaThreshold: Double = 15.0
    @Published public var trackImageQuota: Bool = true

    private let independentEngine = IndependentQuotaEngine.shared
    private let accountsStorageKey = "com.antibox.saved_accounts_v3"

    private var secondTimer: AnyCancellable?
    private var syncTimer: AnyCancellable?

    public init() {
        notificationManager.requestAuthorization()
        loadInitialData()
        startRealtimeTickers()
    }

    deinit {
        secondTimer?.cancel()
        syncTimer?.cancel()
    }

    private func loadInitialData() {
        if syncService.isAvailable, let localSync = syncService.syncFromLocalStore() {
            self.accounts = localSync.accounts
            if let activeId = localSync.currentAccountId {
                self.selectedAccountId = activeId
            } else {
                self.selectedAccountId = accounts.first?.id
            }
        } else {
            loadPersistedAccounts()
            if accounts.isEmpty {
                seedRealWorldAccounts()
            }
            if selectedAccountId == nil {
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

        // Live 5-second store synchronizer to catch quota changes in background proxy
        syncTimer = Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.performBackgroundSync()
            }
    }

    private func performBackgroundSync() {
        guard syncService.isAvailable, let localSync = syncService.syncFromLocalStore() else {
            return
        }

        // Update accounts with live data
        self.accounts = localSync.accounts
        if self.selectedAccountId == nil, let activeId = localSync.currentAccountId {
            self.selectedAccountId = activeId
        }
        self.recalculateBudget()
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

        try? await Task.sleep(nanoseconds: 200_000_000)

        if engineMode == .direct {
            for index in accounts.indices {
                let acc = accounts[index]
                guard acc.isActive else { continue }
                if let key = try? keychainManager.retrieve(forAccount: acc.id), !key.isEmpty {
                    if acc.provider == .gemini {
                        if let live = try? await independentEngine.fetchGeminiDirectQuota(apiKey: key) {
                            accounts[index].quotas = live
                        }
                    } else {
                        if let live = try? await independentEngine.fetchClaudeDirectQuota(apiKey: key) {
                            accounts[index].quotas = live
                        }
                    }
                }
            }
        } else {
            performBackgroundSync()
        }

        for account in accounts where account.isActive {
            notificationManager.evaluateQuotaThreshold(for: account)
        }

        saveAccounts()
        recalculateBudget()
        isLoading = false
    }

    // MARK: - Account Management

    public func selectAccount(id: UUID) {
        selectedAccountId = id
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
