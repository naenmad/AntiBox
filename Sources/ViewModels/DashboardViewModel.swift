import Foundation
import SwiftUI
import Combine

@MainActor
public final class DashboardViewModel: ObservableObject {
    @Published public var accounts: [Account] = []
    @Published public var selectedAccountId: UUID? = nil
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var recommendation: BudgetRecommendation? = nil
    @Published public var showingAddAccountSheet: Bool = false

    private let keychainManager = KeychainManager.shared
    private let notificationManager = NotificationManager.shared
    private let budgetAdvisor = SmartBudgetAdvisor.shared
    private let accountsStorageKey = "com.antibox.saved_accounts_v2"

    public init() {
        notificationManager.requestAuthorization()
        loadPersistedAccounts()
        if accounts.isEmpty {
            seedRealWorldAccounts()
        }
        if selectedAccountId == nil {
            selectedAccountId = accounts.first?.id
        }
        recalculateBudget()
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
        // Fallback: collect all quotas across accounts
        return accounts.flatMap { $0.quotas }
    }

    // MARK: - Quota Refresh

    public func refreshAllQuotas() async {
        isLoading = true
        errorMessage = nil

        // Simulate lightweight refresh with real timestamps
        try? await Task.sleep(nanoseconds: 300_000_000)

        for index in accounts.indices {
            let account = accounts[index]
            guard account.isActive else { continue }

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

    // MARK: - Real-World Dataset Setup (Matched with User's Dashboard)

    private func seedRealWorldAccounts() {
        let calendar = Calendar.current
        let now = Date()

        // 4 hours 59 minutes from now
        let geminiResetDate = calendar.date(byAdding: .minute, value: 299, to: now) ?? now.addingTimeInterval(17940)

        // 2 days 16 hours from now
        let claudeWeeklyResetDate = calendar.date(byAdding: .minute, value: (2 * 1440) + (16 * 60), to: now) ?? now.addingTimeInterval(230400)

        // 6 days 12 hours from now
        let claudeFullResetDate = calendar.date(byAdding: .minute, value: (6 * 1440) + (12 * 60), to: now) ?? now.addingTimeInterval(561600)

        // Account 1: Current Active Account (tunefix.id@gmail.com)
        let primaryAccount = Account(
            name: "Current Account",
            email: "tunefix.id@gmail.com",
            provider: .gemini,
            tier: "PRO",
            totalQuotaTokens: 10_000_000,
            usedQuotaTokens: 2_700_000, // 73% remaining
            resetDate: geminiResetDate,
            isActive: true,
            quotas: [
                QuotaItem(
                    name: "gemini-3.1-pro-high",
                    provider: .gemini,
                    iconKind: .sparkle,
                    remainingPercentage: 73.0,
                    resetDate: geminiResetDate,
                    remainingTokens: 7_300_000,
                    totalTokens: 10_000_000
                ),
                QuotaItem(
                    name: "gemini-3.1-flash-image",
                    provider: .gemini,
                    iconKind: .sparkle,
                    remainingPercentage: 73.0,
                    resetDate: geminiResetDate,
                    remainingTokens: 7_300_000,
                    totalTokens: 10_000_000
                ),
                QuotaItem(
                    name: "gemini-3-flash-agent",
                    provider: .gemini,
                    iconKind: .sparkle,
                    remainingPercentage: 73.0,
                    resetDate: geminiResetDate,
                    remainingTokens: 7_300_000,
                    totalTokens: 10_000_000
                ),
                QuotaItem(
                    name: "claude-sonnet-4-6",
                    provider: .claude,
                    iconKind: .sunburst,
                    remainingPercentage: 0.0,
                    customLabel: "Weekly 0%",
                    resetDate: claudeWeeklyResetDate,
                    remainingTokens: 0,
                    totalTokens: 5_000_000
                )
            ]
        )

        // Account 2: xtampol@gmail.com (High-capacity Gemini pool with full 100% quota)
        let xtampolAccount = Account(
            name: "Best Gemini Pool",
            email: "xtampol@gmail.com",
            provider: .gemini,
            tier: "SCALE",
            totalQuotaTokens: 25_000_000,
            usedQuotaTokens: 0,
            resetDate: geminiResetDate,
            isActive: true,
            quotas: [
                QuotaItem(name: "Gemini 3.8 Flash (High)", provider: .gemini, iconKind: .sparkle, remainingPercentage: 100.0, resetDate: geminiResetDate),
                QuotaItem(name: "Flash Preview (Flash...)", provider: .gemini, iconKind: .sparkle, remainingPercentage: 100.0, resetDate: geminiResetDate),
                QuotaItem(name: "Gemini 3.7 Flash (High)", provider: .gemini, iconKind: .sparkle, remainingPercentage: 100.0, resetDate: geminiResetDate),
                QuotaItem(name: "Gemini 3.7 Flash (Low)", provider: .gemini, iconKind: .sparkle, remainingPercentage: 100.0, resetDate: geminiResetDate),
                QuotaItem(name: "Gemini 3.6 Flash (Med)", provider: .gemini, iconKind: .sparkle, remainingPercentage: 100.0, resetDate: geminiResetDate),
                QuotaItem(name: "Gemini 3.5 Flash (Low)", provider: .gemini, iconKind: .sparkle, remainingPercentage: 100.0, resetDate: geminiResetDate),
                QuotaItem(name: "Gemini 3.5 Flash Lite", provider: .gemini, iconKind: .robot, remainingPercentage: 100.0, resetDate: geminiResetDate),
                QuotaItem(name: "Gemini 3.1 Pro (Low)", provider: .gemini, iconKind: .sparkle, remainingPercentage: 100.0, resetDate: geminiResetDate),
                QuotaItem(name: "Gemini 3.1 Flash Lite", provider: .gemini, iconKind: .robot, remainingPercentage: 100.0, resetDate: geminiResetDate),
                QuotaItem(name: "Gemini 3 Flash", provider: .gemini, iconKind: .robot, remainingPercentage: 100.0, resetDate: geminiResetDate),
                QuotaItem(name: "Gemini 3.5 Flash Lite", provider: .gemini, iconKind: .sparkle, remainingPercentage: 100.0, resetDate: geminiResetDate),
                QuotaItem(name: "Claude Sonnet", provider: .claude, iconKind: .sunburst, remainingPercentage: 0.0, customLabel: "Weekly 0%", resetDate: claudeWeeklyResetDate)
            ]
        )

        // Account 3: yraunajfni@gmail.com (Claude backup pool)
        let yraunajfniAccount = Account(
            name: "Claude Standby",
            email: "yraunajfni@gmail.com",
            provider: .claude,
            tier: "PRO",
            totalQuotaTokens: 10_000_000,
            usedQuotaTokens: 0,
            resetDate: claudeFullResetDate,
            isActive: true,
            quotas: [
                QuotaItem(name: "Claude 3.5 Sonnet", provider: .claude, iconKind: .sunburst, remainingPercentage: 100.0, resetDate: claudeFullResetDate)
            ]
        )

        accounts = [primaryAccount, xtampolAccount, yraunajfniAccount]
        saveAccounts()

        // Seed mock keychain entries
        _ = try? keychainManager.save(token: "sk-gemini-tunefix-sample", forAccount: primaryAccount.id)
        _ = try? keychainManager.save(token: "sk-gemini-xtampol-sample", forAccount: xtampolAccount.id)
        _ = try? keychainManager.save(token: "sk-claude-yraunajfni-sample", forAccount: yraunajfniAccount.id)
    }
}
