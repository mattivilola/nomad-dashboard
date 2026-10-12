import Combine
import Foundation
import NomadUI

struct SettingsFocusRequest: Equatable {
    let id = UUID()
    let target: SettingsFocusTarget
}

@MainActor
final class SettingsNavigationController: ObservableObject {
    /// The page shown in the Settings window. It lives here so the last page stays selected when the window is reopened.
    @Published var selectedPage: SettingsPage = .general
    @Published private(set) var focusRequest: SettingsFocusRequest?

    /// Selects the page that owns `target` and asks that page to scroll to the group.
    func focus(_ target: SettingsFocusTarget) {
        selectedPage = target.page
        focusRequest = SettingsFocusRequest(target: target)
    }

    /// Called by the page once it has handled `request`, so reopening Settings does not replay it.
    func complete(_ request: SettingsFocusRequest) {
        guard focusRequest == request else {
            return
        }

        focusRequest = nil
    }
}
