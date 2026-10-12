import SwiftUI

public enum MainNavigationTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case accounts = "Accounts"
    case models = "Model Explorer"
    case settings = "Settings"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.33percent"
        case .accounts: return "person.2.fill"
        case .models: return "cpu.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

/// Full native macOS application window dashboard
public struct MainDashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var selectedTab: MainNavigationTab = .overview

    public init(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationSplitView {
            sidebarView
        } detail: {
            detailContentView
        }
        .frame(minWidth: 800, minHeight: 540)
        .background(VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow))
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                // Current Account Indicator
                HStack(spacing: 5) {
                    Circle()
                        .fill(viewModel.selectedAccount?.status.color ?? .green)
                        .frame(width: 6, height: 6)

                    Text(viewModel.selectedAccount?.email.isEmpty ?? true ? (viewModel.selectedAccount?.name ?? "Account") : (viewModel.selectedAccount?.email ?? ""))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(Color.primary.opacity(0.04))
                .clipShape(Capsule())

                // Refresh Button
                Button {
                    Task {
                        await viewModel.refreshAllQuotas()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: [.command])

                // Add Account Button
                Button {
                    viewModel.showingAddAccountSheet = true
                } label: {
                    Label("Add Account", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
        }
        .sheet(isPresented: $viewModel.showingAddAccountSheet) {
            AddAccountSheet { name, provider, tier, total, used, resetDate, apiKey in
                viewModel.addAccount(
                    name: name,
                    provider: provider,
                    tier: tier,
                    totalTokens: total,
                    usedTokens: used,
                    resetDate: resetDate,
                    apiKey: apiKey
                )
            }
        }
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        List(MainNavigationTab.allCases, selection: $selectedTab) { tab in
            NavigationLink(value: tab) {
                Label(tab.rawValue, systemImage: tab.iconName)
                    .font(.system(size: 13, weight: .medium))
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContentView: some View {
        switch selectedTab {
        case .overview:
            overviewView
        case .accounts:
            accountsListView
        case .models:
            modelsExplorerView
        case .settings:
            settingsView
        }
    }

    // MARK: - Overview Tab

    private var overviewView: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 18) {
                // Header Banner
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quota & Health Matrix")
                        .font(.system(size: 20, weight: .bold))

                    Text("Live token allocations and cycle reset horizons for active pools")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                // 2 Core Category Cards (Gemini vs Claude/GPT-OSS)
                HStack(spacing: 14) {
                    ForEach(viewModel.currentQuotaGroups) { group in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: group.iconName)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(group.accentColor)

                                Text(group.title)
                                    .font(.system(size: 14, weight: .bold))

                                Spacer()

                                Text(group.displayPercentage)
                                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                                    .foregroundColor(group.isDepleted ? Color.red : Color.green)
                            }

                            Text("Resets in \(group.countdownString)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.orange)

                            Text(group.description)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)

                            Divider().opacity(0.1)

                            Text("\(group.models.count) models tracked in this group")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                    }
                }

                // Smart Advisor Section
                if let recommendation = viewModel.recommendation {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Smart Token Consumption Advisor")
                            .font(.system(size: 13, weight: .semibold))

                        BudgetAdvisorCardView(recommendation: recommendation)
                    }
                }

                // Multi-Account Pool Grid
                VStack(alignment: .leading, spacing: 8) {
                    Text("Configured Account Pools (\(viewModel.accounts.count))")
                        .font(.system(size: 13, weight: .semibold))

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(viewModel.accounts) { acc in
                            HStack {
                                Circle()
                                    .fill(acc.status.color)
                                    .frame(width: 8, height: 8)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(acc.email.isEmpty ? acc.name : acc.email)
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(1)

                                    Text(acc.tier)
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Text("\(Int(acc.remainingPercentage))%")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(acc.status.color)
                            }
                            .padding(10)
                            .background(Color.primary.opacity(0.025))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(acc.id == viewModel.selectedAccount?.id ? Color.accentColor : Color.white.opacity(0.06), lineWidth: acc.id == viewModel.selectedAccount?.id ? 1 : 0.5)
                            )
                            .onTapGesture {
                                viewModel.selectAccount(id: acc.id)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - Accounts Tab

    private var accountsListView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Account Management")
                        .font(.system(size: 18, weight: .bold))

                    Text("All local proxy pools and direct API configurations")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Connect Account") {
                    viewModel.showingAddAccountSheet = true
                }
                .buttonStyle(.borderedProminent)
            }
            .padding([.horizontal, .top], 20)

            List(viewModel.accounts) { account in
                HStack(spacing: 12) {
                    Circle()
                        .fill(account.status.color)
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(account.email.isEmpty ? account.name : account.email)
                                .font(.system(size: 13, weight: .semibold))

                            if account.id == viewModel.selectedAccount?.id {
                                Text("ACTIVE")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.green.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }

                        Text("Tier: \(account.tier) • \(account.quotas.count) models tracked")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text("\(Int(account.remainingPercentage))%")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(account.status.color)

                    Button(account.id == viewModel.selectedAccount?.id ? "Selected" : "Set Active") {
                        viewModel.selectAccount(id: account.id)
                    }
                    .buttonStyle(.bordered)
                    .disabled(account.id == viewModel.selectedAccount?.id)
                }
                .padding(.vertical, 4)
            }
            .listStyle(.inset)
        }
    }

    // MARK: - Model Explorer Tab

    private var modelsExplorerView: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Model Quota Explorer")
                    .font(.system(size: 18, weight: .bold))

                Text("Granular view of all rate-limited models under \(viewModel.selectedAccount?.email ?? "active account")")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding([.horizontal, .top], 20)

            List(viewModel.currentQuotaItems) { item in
                ModelQuotaRowView(item: item, currentTime: viewModel.currentTime)
                    .padding(.vertical, 2)
            }
            .listStyle(.plain)
            .padding(.horizontal, 14)
        }
    }

    // MARK: - Settings Tab

    private var settingsView: some View {
        Form {
            Section("Data Source Engine") {
                Picker("Sync Mode", selection: $viewModel.engineMode) {
                    ForEach(DashboardViewModel.EngineMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text("Hybrid automatically syncs local Antigravity Tools accounts when available, while allowing standalone direct API keys via Keychain.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Section("About AntiBox") {
                LabeledContent("Version", value: "1.2.0")
                LabeledContent("Platform", value: "macOS 14+ Sonoma / Sequoia")
                LabeledContent("Security", value: "Apple Keychain Protected")
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
