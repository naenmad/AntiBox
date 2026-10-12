import SwiftUI
import AppKit

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

/// Native macOS application window dashboard with authentic Apple frosted glass translucency
public struct MainDashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var selectedTab: MainNavigationTab = .overview
    @ObservedObject private var launchManager = LaunchAtLoginManager.shared

    public init(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationSplitView {
            sidebarView
                .scrollContentBackground(.hidden)
                .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
        } detail: {
            detailContentView
        }
        .frame(minWidth: 840, minHeight: 560)
        .background(VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow))
        .background(WindowAccessor())
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                // Current Account & Tier Indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.selectedAccount?.status.color ?? .green)
                        .frame(width: 6, height: 6)

                    Text(viewModel.selectedAccount?.email.isEmpty ?? true ? (viewModel.selectedAccount?.name ?? "Account") : (viewModel.selectedAccount?.email ?? ""))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.primary)

                    if let acc = viewModel.selectedAccount {
                        let tier = acc.accountTier
                        HStack(spacing: 2) {
                            if tier == .ultra {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 7.5))
                            }
                            Text(tier.displayName.uppercased())
                                .font(.system(size: 8.5, weight: .bold))
                        }
                        .foregroundColor(tier.color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(tier.color.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
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
        ZStack {
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()

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
    }

    // MARK: - Overview Tab

    private var overviewView: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 18) {
                // Header Banner
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quota & Health Matrix")
                        .font(.system(size: 20, weight: .bold))

                    Text("Real-time token allocations and cycle reset horizons for active pools")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                // 2 Core Category Cards (Gemini vs Claude/GPT-OSS)
                HStack(alignment: .top, spacing: 14) {
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
                                    .foregroundColor(group.isDepleted ? Color.red : Color(red: 0.22, green: 0.82, blue: 0.55))
                            }

                            Text("Resets in \(group.countdownString)")
                                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                .foregroundColor(Color(red: 0.92, green: 0.74, blue: 0.30))

                            // Core Progress Bar
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.primary.opacity(0.06))
                                    Capsule().fill(group.isDepleted ? Color.red : Color(red: 0.22, green: 0.82, blue: 0.55))
                                        .frame(width: max(0, min(geo.size.width * CGFloat(group.percentage / 100.0), geo.size.width)))
                                }
                            }
                            .frame(height: 5)

                            // Dedicated Gemini Image Quota
                            if let imageQuota = group.imageQuota {
                                Divider().opacity(0.12)

                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "photo.badge.sparkles")
                                            .font(.system(size: 12))
                                            .foregroundColor(Color(red: 0.70, green: 0.35, blue: 0.95))

                                        Text("Gemini Image Quota")
                                            .font(.system(size: 12, weight: .medium))

                                        Spacer()

                                        Text("Resets in \(imageQuota.countdownString)")
                                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                            .foregroundColor(Color(red: 0.92, green: 0.74, blue: 0.30))

                                        Text("\(Int(imageQuota.percentage))%")
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundColor(imageQuota.percentage <= 15 ? Color.red : Color(red: 0.70, green: 0.35, blue: 0.95))
                                    }

                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Color.primary.opacity(0.06))
                                            Capsule().fill(imageQuota.percentage <= 15 ? Color.red : Color(red: 0.70, green: 0.35, blue: 0.95))
                                                .frame(width: max(0, min(geo.size.width * CGFloat(imageQuota.percentage / 100.0), geo.size.width)))
                                        }
                                    }
                                    .frame(height: 4)
                                }
                            }

                            Text(group.description)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.04))
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
                            .font(.system(size: 14, weight: .bold))

                        HStack(spacing: 12) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 18))
                                .foregroundColor(.cyan)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(recommendation.actionableSummary)
                                    .font(.system(size: 12.5, weight: .medium))

                                Text("Pace: \(recommendation.burnRateStatus.title) • Reset in: \(recommendation.daysUntilReset) days")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Text(Account.formatTokens(recommendation.recommendedDailyBudget) + "/day")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(.cyan)
                        }
                        .padding(14)
                        .background(Color.cyan.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }

                // Active Account Switcher Grid
                VStack(alignment: .leading, spacing: 8) {
                    Text("Configured Account Pools")
                        .font(.system(size: 14, weight: .bold))

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                        ForEach(viewModel.accounts) { acc in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(acc.status.color)
                                    .frame(width: 7, height: 7)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(acc.email.isEmpty ? acc.name : acc.email)
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(1)

                                    HStack(spacing: 4) {
                                        Text(acc.accountTier.displayName.uppercased())
                                            .font(.system(size: 8.5, weight: .bold))
                                            .foregroundColor(acc.accountTier.color)

                                        Text("• \(Int(acc.remainingPercentage))%")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()

                                if acc.id == viewModel.selectedAccount?.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.035))
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

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(account.email.isEmpty ? account.name : account.email)
                                .font(.system(size: 13, weight: .semibold))

                            // Tier Badge
                            HStack(spacing: 2.5) {
                                if account.accountTier == .ultra {
                                    Image(systemName: "crown.fill")
                                        .font(.system(size: 7))
                                }
                                Text(account.accountTier.displayName.uppercased())
                                    .font(.system(size: 8.5, weight: .bold))
                            }
                            .foregroundColor(account.accountTier.color)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(account.accountTier.color.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))

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

                        Text("Plan: \(account.accountTier.badgeLabel) • \(account.quotas.count) models tracked")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Tier Selection Menu
                    Menu {
                        ForEach(AccountTier.allCases, id: \.self) { t in
                            Button {
                                viewModel.updateAccountTier(id: account.id, tier: t)
                            } label: {
                                HStack {
                                    Text("\(t.displayName) (\(t.badgeLabel))")
                                    if account.accountTier == t {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Text(account.accountTier.displayName)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 65)

                    Text("\(Int(account.remainingPercentage))%")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(account.status.color)
                        .frame(width: 45, alignment: .trailing)

                    Button(account.id == viewModel.selectedAccount?.id ? "Selected" : "Set Active") {
                        viewModel.selectAccount(id: account.id)
                    }
                    .buttonStyle(.bordered)
                    .disabled(account.id == viewModel.selectedAccount?.id)
                }
                .padding(.vertical, 6)
                .listRowBackground(Color.white.opacity(0.02))
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
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
                    .padding(.vertical, 3)
                    .listRowBackground(Color.white.opacity(0.02))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 14)
        }
    }

    // MARK: - Settings Tab

    private var settingsView: some View {
        Form {
            Section("General & System Startup") {
                Toggle("Launch AntiBox at Login", isOn: Binding(
                    get: { launchManager.isEnabled },
                    set: { launchManager.setLaunchAtLogin(enabled: $0) }
                ))

                Text("Automatically launch AntiBox companion in the Menu Bar when your Mac boots up.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                if !launchManager.statusMessage.isEmpty {
                    Text(launchManager.statusMessage)
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
            }

            Section("Quota Monitoring & Image Tracking") {
                Toggle("Track Gemini Flash Image Generation Quota", isOn: $viewModel.trackImageQuota)
                Toggle("Notify When Quota Drops Below Safe Threshold", isOn: $viewModel.notifyLowQuota)

                if viewModel.notifyLowQuota {
                    Picker("Critical Alert Threshold", selection: $viewModel.lowQuotaThreshold) {
                        Text("25% Remaining").tag(25.0)
                        Text("20% Remaining").tag(20.0)
                        Text("15% (Critical Default)").tag(15.0)
                        Text("10% Remaining").tag(10.0)
                    }
                }
            }

            Section("Data Engine & Independence") {
                Picker("Engine Mode", selection: $viewModel.engineMode) {
                    ForEach(DashboardViewModel.EngineMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.green)
                    Text(viewModel.standaloneStatus)
                        .font(.system(size: 11, weight: .medium))
                }

                Button("Migrate & Detach from Antigravity Tools") {
                    viewModel.detachFromAntigravityTools()
                }
                .buttonStyle(.borderedProminent)

                Text("Imports existing accounts and tokens directly into macOS Keychain and AntiBox local storage (~/Library/Application Support/AntiBox). After detachment, AntiBox operates completely standalone via direct Google OAuth & Cloud Code APIs without Antigravity Tools.")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)

                Button("Refresh Live Quotas Now") {
                    Task {
                        await viewModel.refreshAllQuotas()
                    }
                }
            }

            Section("About AntiBox") {
                LabeledContent("Version", value: "1.2.0")
                LabeledContent("Design Language", value: "Native Apple Frosted Vibrancy")
                LabeledContent("Platform", value: "macOS 14+ Sonoma / Sequoia")
                LabeledContent("Security", value: "Apple Keychain Protected")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(20)
    }
}

/// Helper NSViewRepresentable to configure window transparency for full-surface frosted glass
private struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.titlebarAppearsTransparent = true
                window.isOpaque = false
                window.backgroundColor = .clear
                window.styleMask.insert(.fullSizeContentView)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
