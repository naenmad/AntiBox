import Foundation

/// Background quota synchronization profile
public enum SyncFrequency: String, CaseIterable, Identifiable, Codable, Sendable {
    case balanced = "balanced"
    case fast = "fast"
    case batterySaver = "saver"
    case manual = "manual"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .balanced: return "Balanced (60s) - Recommended"
        case .fast: return "Fast (15s) - Active Development"
        case .batterySaver: return "Battery Saver (5 minutes)"
        case .manual: return "Manual Only (On-Demand)"
        }
    }

    public var intervalSeconds: Double? {
        switch self {
        case .fast: return 15.0
        case .balanced: return 60.0
        case .batterySaver: return 300.0
        case .manual: return nil
        }
    }
}
