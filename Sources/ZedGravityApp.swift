import SwiftUI
import SwiftData

@main
struct ZedGravityApp: App {
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
        WindowGroup("ZedGravity", id: "main") {
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
            HStack(spacing: 4) {
                Image(systemName: "sparkle")
                Text(dashboardViewModel.menuBarSummaryText)
                    .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
            }
        }
        .menuBarExtraStyle(.window)
    }
}
