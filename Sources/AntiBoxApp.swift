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
            HStack(spacing: 4) {
                let status = dashboardViewModel.currentMenuBarQuota
                Image(systemName: status.icon)
                if let pct = status.percentage {
                    Text("\(Int(pct))%")
                        .font(.system(size: 11, design: .rounded).monospacedDigit())
                } else {
                    Text(status.label)
                        .font(.system(size: 11, design: .rounded))
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
