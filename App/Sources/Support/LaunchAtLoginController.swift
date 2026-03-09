import Combine
import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var isEnabled: Bool

    init(initialEnabled: Bool) {
        if #available(macOS 13.0, *) {
            isEnabled = SMAppService.mainApp.status == .enabled
        } else {
            isEnabled = initialEnabled
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else {
            isEnabled = enabled
            return
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }

            isEnabled = enabled
        } catch {
            isEnabled = SMAppService.mainApp.status == .enabled
        }
    }
}

