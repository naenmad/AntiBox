import SwiftUI

/// Clean, native modal sheet for connecting an Antigravity account via Google OAuth login popup
public struct AddAccountSheet: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject private var oauthManager = OAuthSignInManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showingManualInput: Bool = false
    @State private var manualRefreshToken: String = ""

    public init(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 20) {
            // Header Bar
            HStack {
                Text("Connect Antigravity Account")
                    .font(.system(size: 15, weight: .bold))

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }

            // Visual Hero Banner
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.cyan.opacity(0.12))
                        .frame(width: 54, height: 54)

                    Image(systemName: "sparkles")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.cyan)
                }

                VStack(spacing: 4) {
                    Text("Sign in with Google")
                        .font(.system(size: 14, weight: .semibold))

                    Text("Authorize AntiBox directly to monitor your live Gemini & Claude weekly pools, cycle resets, and image tokens.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                }
            }
            .padding(.vertical, 6)

            // Primary Action: Google OAuth Login Popup
            VStack(spacing: 10) {
                Button {
                    Task {
                        await viewModel.connectAntigravityAccountViaOAuth()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if oauthManager.isAuthenticating {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                            Text(oauthManager.statusMessage.isEmpty ? "Connecting..." : oauthManager.statusMessage)
                                .font(.system(size: 13, weight: .medium))
                        } else {
                            Image(systemName: "arrow.up.right.square.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Log in with Google (Popup)")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(oauthManager.isAuthenticating)

                if let error = oauthManager.errorMessage {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
            }

            // Optional Manual Refresh Token Fallback
            VStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingManualInput.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(showingManualInput ? "Hide manual input" : "Or enter refresh token manually")
                            .font(.system(size: 11))
                        Image(systemName: showingManualInput ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                if showingManualInput {
                    VStack(spacing: 8) {
                        SecureField("Google OAuth Refresh Token (1//...)", text: $manualRefreshToken)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))

                        Button("Connect with Token") {
                            addManualToken()
                        }
                        .buttonStyle(.bordered)
                        .font(.system(size: 11))
                        .disabled(manualRefreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(VisualEffectView(material: .sheet, blendingMode: .behindWindow))
    }

    private func addManualToken() {
        let token = manualRefreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }

        Task {
            if let accessToken = try? await DirectCloudCodeEngine.shared.refreshAccessToken(refreshToken: token) {
                let id = UUID()
                _ = try? KeychainManager.shared.save(token: token, forAccount: id)

                var account = Account(
                    id: id,
                    name: "Antigravity Account",
                    email: "antigravity.user@gmail.com",
                    provider: .gemini,
                    tier: "PRO",
                    totalQuotaTokens: 10_000_000,
                    usedQuotaTokens: 2_700_000,
                    resetDate: Date().addingTimeInterval(17940),
                    isActive: true
                )

                if let directRes = try? await DirectCloudCodeEngine.shared.fetchDirectQuotas(accessToken: accessToken) {
                    account.customRemainingPercentage = directRes.geminiWeeklyPercentage
                    account.resetDate = directRes.geminiResetDate
                    account.imageQuotaPercentage = directRes.imageQuotaPercentage
                    account.imageQuotaResetDate = directRes.imageQuotaResetDate
                    account.quotas = directRes.models
                }

                viewModel.accounts.append(account)
                viewModel.selectedAccountId = id
                viewModel.showingAddAccountSheet = false
                dismiss()
            }
        }
    }
}
