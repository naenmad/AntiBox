import SwiftUI

/// Modal sheet for adding a new AI provider account and saving credentials to Keychain
public struct AddAccountSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var provider: AIProvider = .gemini
    @State private var tier: String = "Pro"
    @State private var totalTokensString: String = "10000000"
    @State private var usedTokensString: String = "2000000"
    @State private var resetDate: Date = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
    @State private var apiKey: String = ""

    public let onSave: (String, AIProvider, String, Int64, Int64, Date, String) -> Void

    public init(onSave: @escaping (String, AIProvider, String, Int64, Int64, Date, String) -> Void) {
        self.onSave = onSave
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (Int64(totalTokensString) ?? 0) > 0
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Add Monitored Account")
                    .font(.system(size: 15, weight: .semibold))

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            Divider()

            // Form Fields
            Form {
                Picker("Provider", selection: $provider) {
                    ForEach(AIProvider.allCases) { item in
                        Label(item.displayName, systemImage: item.iconName).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Account Label", text: $name, prompt: Text("e.g. Production Backend"))

                TextField("Plan Tier", text: $tier, prompt: Text("e.g. Pro or Pay-as-you-go"))

                TextField("Total Token Quota", text: $totalTokensString)
                    .help("Total allowed tokens per billing cycle")

                TextField("Used Tokens", text: $usedTokensString)
                    .help("Tokens consumed in current cycle")

                DatePicker("Billing Reset Date", selection: $resetDate, displayedComponents: [.date])

                SecureField("API Key / Session Token", text: $apiKey, prompt: Text("Stored securely in macOS Keychain"))
                    .help("Credentials are saved in Apple Keychain Services and never logged")
            }

            Divider()

            // Actions
            HStack {
                Spacer()

                Button("Add Account") {
                    let total = Int64(totalTokensString) ?? 10_000_000
                    let used = Int64(usedTokensString) ?? 0
                    onSave(name, provider, tier, total, used, resetDate, apiKey)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
        }
        .padding(16)
        .frame(width: 420)
    }
}
