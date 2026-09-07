import Combine
import Foundation
import NomadCore
import UserNotifications

@MainActor
protocol NomadLifeNotificationDelivering {
    func deliver(_ alerts: [NomadLifeQuietAlert])
    func requestPermission()
    var authorizationStatus: UNAuthorizationStatus { get }
}

@MainActor
final class UserNotificationCenterNomadLifeDelivery: ObservableObject, NomadLifeNotificationDelivering {
    private let center: UNUserNotificationCenter
    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        refreshAuthorization()
    }

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    func refreshAuthorization() {
        Task { [weak self] in
            guard let self else { return }
            authorizationStatus = await (center.notificationSettings()).authorizationStatus
        }
    }

    func requestPermission() {
        Task { [weak self] in
            guard let self else { return }
            let settings = await center.notificationSettings()
            authorizationStatus = settings.authorizationStatus
            guard settings.authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert])
            authorizationStatus = await (center.notificationSettings()).authorizationStatus
        }
    }

    func deliver(_ alerts: [NomadLifeQuietAlert]) {
        guard !alerts.isEmpty else { return }
        Task {
            guard authorizationStatus == .authorized || authorizationStatus == .provisional else { return }
            for alert in alerts {
                let content = UNMutableNotificationContent()
                content.title = alert.title
                content.body = alert.body
                let request = UNNotificationRequest(identifier: "nomad-life-\(alert.kind.rawValue)", content: content, trigger: nil)
                try? await center.add(request)
            }
        }
    }
}
