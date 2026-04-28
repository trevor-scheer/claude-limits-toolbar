import Foundation
import ServiceManagement

@MainActor
enum LaunchAtLoginHelper {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            switch (enabled, SMAppService.mainApp.status) {
            case (true, .enabled):
                return
            case (true, _):
                try SMAppService.mainApp.register()
            case (false, .enabled):
                try SMAppService.mainApp.unregister()
            case (false, _):
                return
            }
        } catch {
            NSLog("LaunchAtLogin error: \(error.localizedDescription)")
        }
    }
}
