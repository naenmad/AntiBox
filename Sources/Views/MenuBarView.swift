import SwiftUI

/// Pixel-refined macOS MenuBar popover conforming strictly to Apple HIG
public struct MenuBarView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.openWindow) private var openWindow

    public init(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerView

            Divider()
                .opacity(0.12)

            // Content Area
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 9) {
                    // Smart Advisor Compact Banner
                    if let recommendation = viewModel.recommendation {
                        BudgetAdvisorCardView(recommendation: recommendation)
                    }

                    // Account Selector Capsule Bar
                    if !viewModel.accounts.isEmpty {
                        accountSwitcherBar
                    }

                    // 2 Core Group Cards (Gemini vs Claude/GPT-OSS)
                    quotaListView
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }

            Divider()
                .opacity(0.12)

            // Footer
            footerView
        }
        .frame(width: 360, height: 490)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
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

    // MARK: - Subviews

    private var headerView: some View {
        HStack(spacing: 8) {
            // App Branding with live status dot
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(red: 0.22, green: 0.88, blue: 0.62))
                    .frame(width: 7, height: 7)

                Text("AntiBox")
                    .font(.system(size: 13, weight: .bold))

                Text("Quota Monitor")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Open Full App Button (⌘O)
            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "macwindow")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open Full Dashboard Window (⌘O)")
            .keyboardShortcut("o", modifiers: [.command])

            // Refresh Button (⌘R)
            Button {
                Task {
                    await viewModel.refreshAllQuotas()
                }
            } label: {
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.55)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .help("Refresh Quotas (⌘R)")
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(viewModel.isLoading)

            // Add Account Button (⌘N)
            Button {
                viewModel.showingAddAccountSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Add Account (⌘N)")
            .keyboardShortcut("n", modifiers: [.command])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var accountSwitcherBar: some View {
        HStack {
            Menu {
                ForEach(viewModel.accounts) { account in
                    Button {
                        viewModel.selectAccount(id: account.id)
                    } label: {
                        HStack {
                            Text(account.email.isEmpty ? account.name : account.email)
                            if account.id == viewModel.selectedAccount?.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(viewModel.selectedAccount?.status.color ?? .green)
                        .frame(width: 6, height: 6)

                    Text(viewModel.selectedAccount?.email.isEmpty ?? true ? (viewModel.selectedAccount?.name ?? "Account") : (viewModel.selectedAccount?.email ?? ""))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if let tier = viewModel.selectedAccount?.tier {
                        Text(tier)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    }

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(Color.primary.opacity(0.04))
                .clipShape(Capsule())
            }
            .menuStyle(.borderlessButton)

            Spacer()

            Text("\(viewModel.currentQuotaItems.count) models")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    private var quotaListView: some View {
        VStack(spacing: 8) {
            ForEach(viewModel.currentQuotaGroups) { group in
                QuotaGroupCardView(group: group, currentTime: viewModel.currentTime)
            }
        }
    }

    private var footerView: some View {
        HStack {
            Button("Open Full Dashboard") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundColor(.accentColor)

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5))
            .foregroundColor(.secondary)
            .keyboardShortcut("q", modifiers: [.command])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
