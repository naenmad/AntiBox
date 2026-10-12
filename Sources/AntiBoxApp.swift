import SwiftUI
import SwiftData

@main
struct AntiBoxApp: App {
    @StateObject private var dashboardViewModel = DashboardViewModel()

    // SwiftData container for logging daily token usage analytics
    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(for: DailyUsageLog.self)
        } catch {
            fatalError("Failed to initialize SwiftData ModelContainer: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(viewModel: dashboardViewModel)
                .modelContainer(modelContainer)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: menuBarIcon)
                if let lowestPct = lowestAccountPercentage {
                    Text("\(Int(lowestPct))%")
                        .font(.system(size: 11, design: .rounded).monospacedDigit())
                }
            }
        }
        .menuBarExtraStyle(.window)
    }

    // Dynamic icon showing system status
    private var menuBarIcon: String {
        guard let lowest = lowestAccountPercentage else {
            return "gauge.with.dots.needle.33percent"
        }
        if lowest <= 15.0 {
            return "exclamationmark.triangle.fill"
        } else if lowest <= 25.0 {
            return "gauge.with.dots.needle.50percent"
        } else {
            return "gauge.with.dots.needle.33percent"
        }
    }

    private var lowestAccountPercentage: Double? {
        let items = dashboardViewModel.currentQuotaItems
        if !items.isEmpty {
            return items.map { $0.remainingPercentage }.min()
        }
        let active = dashboardViewModel.accounts.filter { $0.isActive }
        guard !active.isEmpty else { return nil }
        return active.map { $0.remainingPercentage }.min()
    }
}
