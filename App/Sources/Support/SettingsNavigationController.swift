import Combine
import Foundation

enum SettingsFocusTarget: String {
    case surfSpot
}

struct SettingsFocusRequest {
    let id = UUID()
    let target: SettingsFocusTarget
}

@MainActor
final class SettingsNavigationController: ObservableObject {
    @Published private(set) var focusRequest: SettingsFocusRequest?

    func focus(_ target: SettingsFocusTarget) {
        focusRequest = SettingsFocusRequest(target: target)
    }
}
