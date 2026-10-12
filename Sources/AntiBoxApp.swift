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
        // Main Application Window
        WindowGroup("AntiBox", id: "main") {
            MainDashboardView(viewModel: dashboardViewModel)
                .modelContainer(modelContainer)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 880, height: 580)

        // Menu Bar Companion Extra
        MenuBarExtra {
            MenuBarView(viewModel: dashboardViewModel)
                .modelContainer(modelContainer)
        } label: {
            HStack(spacing: 6) {
                let metrics = dashboardViewModel.menuBarActiveMetrics
                if metrics.isEmpty {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                    if let acc = dashboardViewModel.selectedAccount {
                        Text("\(Int(acc.remainingPercentage))%")
                            .font(.system(size: 11, design: .rounded).monospacedDigit())
                    }
                } else {
                    ForEach(Array(metrics.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 3) {
                            Image(systemName: item.iconSystemName)
                                .font(.system(size: 10))
                            Text("\(item.percentage)%")
                                .font(.system(size: 11, design: .rounded).monospacedDigit())
                        }
                        if index < metrics.count - 1 {
                            Text("•")
                                .foregroundColor(.secondary.opacity(0.6))
                                .font(.system(size: 9))
                        }
                    }
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
