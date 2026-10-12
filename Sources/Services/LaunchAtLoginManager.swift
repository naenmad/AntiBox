import Foundation
import ServiceManagement
import Combine

/// Native macOS Launch at Login service utilizing Apple's SMAppService API (macOS 13.0+)
@MainActor
public final class LaunchAtLoginManager: ObservableObject {
    public static let shared = LaunchAtLoginManager()

    @Published public var isEnabled: Bool = false
    @Published public var statusMessage: String = ""

    private init() {
        checkStatus()
    }

    public func checkStatus() {
        if #available(macOS 13.0, *) {
            self.isEnabled = SMAppService.mainApp.status == .enabled
        }
    }

    public func setLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
                self.isEnabled = SMAppService.mainApp.status == .enabled
                self.statusMessage = enabled ? "Auto startup enabled" : "Auto startup disabled"
            } catch {
                self.isEnabled = SMAppService.mainApp.status == .enabled
                self.statusMessage = "Status: \(error.localizedDescription)"
            }
        }
    }
}
