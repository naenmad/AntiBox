import Foundation

/// Focus strategy for Auto-Switching Zed ACP accounts
public enum AutoSwitchQuotaFocus: String, CaseIterable, Identifiable, Codable, Sendable {
    case both = "both"
    case claude = "claude"
    case gemini = "gemini"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .both: return "Both (Gemini & Claude)"
        case .claude: return "Claude / GPT Only"
        case .gemini: return "Gemini Only"
        }
    }

    public var description: String {
        switch self {
        case .both: return "Switches when either Gemini or Claude quota is critically depleted."
        case .claude: return "Switches only when Claude & GPT models hit 0% / low quota."
        case .gemini: return "Switches only when Gemini models hit low quota."
        }
    }
}
