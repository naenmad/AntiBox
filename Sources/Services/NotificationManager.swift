import Foundation
import UserNotifications

/// Handles native macOS UserNotifications for quota threshold breaches
public final class NotificationManager: @unchecked Sendable {
    public static let shared = NotificationManager()

    private var center: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil else {
            return nil
        }
        return UNUserNotificationCenter.current()
    }
    private var recentlyNotifiedAccounts: Set<UUID> = []
    private let queue = DispatchQueue(label: "com.antibox.notifications")

    private init() {}

    /// Requests authorization from macOS notification system
    public func requestAuthorization() {
        guard let center = center else {
            print("[NotificationManager] Running in unbundled mode (swift run). Notifications require an app bundle.")
            return
        }
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification authorization error: \(error.localizedDescription)")
            }
        }
    }

    /// Evaluates account quota and fires alert if critical threshold (<= 15%) is reached
    public func evaluateQuotaThreshold(for account: Account) {
        let isCritical = account.remainingPercentage <= 15.0

        queue.async { [weak self] in
            guard let self = self else { return }

            if isCritical {
                if !self.recentlyNotifiedAccounts.contains(account.id) {
                    self.recentlyNotifiedAccounts.insert(account.id)
                    self.dispatchAlert(for: account)
                }
            } else {
                // Reset throttle once account is topped up or refreshed above critical threshold
                self.recentlyNotifiedAccounts.remove(account.id)
            }
        }
    }

    private func dispatchAlert(for account: Account) {
        guard let center = center else {
            print("[NotificationManager] Quota alert triggered for \(account.name) (\(String(format: "%.1f", account.remainingPercentage))% remaining)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "\(account.provider.displayName) Quota Warning"
        content.subtitle = "\(account.name) is at \(String(format: "%.1f", account.remainingPercentage))%"
        content.body = "Only \(Account.formatTokens(account.remainingTokens)) tokens remain. Consider throttling non-essential AI workloads."
        content.sound = .default

        let identifier = "quota-alert-\(account.id.uuidString)-\(Date().timeIntervalSince1970)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        center.add(request) { error in
            if let error = error {
                print("Failed to schedule notification: \(error.localizedDescription)")
            }
        }
    }
}
