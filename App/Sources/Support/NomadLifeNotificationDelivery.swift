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
            authorizationStatus = await readAuthorizationStatus()
        }
    }

    func requestPermission() {
        Task { [weak self] in
            guard let self else { return }
            authorizationStatus = await readAuthorizationStatus()
            guard authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert])
            authorizationStatus = await readAuthorizationStatus()
        }
    }

    private func readAuthorizationStatus() async -> UNAuthorizationStatus {
        // Keep the framework response in its callback context on older SDKs.
        let rawValue: Int = await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus.rawValue)
            }
        }
        return UNAuthorizationStatus(rawValue: rawValue) ?? .notDetermined
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
