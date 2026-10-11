import SwiftUI

/// Pixel-refined macOS MenuBar popover conforming strictly to Apple HIG
public struct MenuBarView: View {
    @ObservedObject var viewModel: DashboardViewModel

    public init(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerView

            Divider()
                .opacity(0.3)

            // Content Area
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 10) {
                    // Smart Advisor Compact Banner
                    if let recommendation = viewModel.recommendation {
                        BudgetAdvisorCardView(recommendation: recommendation)
                    }

                    // Account Selector / Active Context
                    if !viewModel.accounts.isEmpty {
                        accountSwitcherBar
                    }

                    // Main Quota Indicator List (Directly matches screenshot design)
                    quotaListView
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }

            Divider()
                .opacity(0.3)

            // Footer
            footerView
        }
        .frame(width: 360, height: 490)
        .background(.ultraThinMaterial)
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
            // App Branding
            HStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(red: 0.22, green: 0.88, blue: 0.62))

                Text("AntiBox")
                    .font(.system(size: 13, weight: .bold))

                Text("Quota Monitor")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

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
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Add Account (⌘N)")
            .keyboardShortcut("n", modifiers: [.command])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
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
                .padding(.vertical, 4)
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
        VStack(spacing: 5) {
            ForEach(viewModel.currentQuotaItems) { item in
                ModelQuotaRowView(item: item)
            }
        }
    }

    private var footerView: some View {
        HStack {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color(red: 0.22, green: 0.88, blue: 0.62))
                    .frame(width: 5, height: 5)

                Text("\(viewModel.accounts.count) accounts configured")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Quit AntiBox") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5))
            .foregroundColor(.secondary)
            .keyboardShortcut("q", modifiers: [.command])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }
}
