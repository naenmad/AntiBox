import Foundation
import SwiftUI

/// Supported AI providers for AntiBox
public enum AIProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case gemini = "Gemini"
    case claude = "Claude"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .gemini: return "Google Gemini"
        case .claude: return "Anthropic Claude"
        }
    }

    public var iconName: String {
        switch self {
        case .gemini: return "sparkles"
        case .claude: return "cpu"
        }
    }

    public var brandColor: Color {
        switch self {
        case .gemini: return Color.blue
        case .claude: return Color.orange
        }
    }
}
