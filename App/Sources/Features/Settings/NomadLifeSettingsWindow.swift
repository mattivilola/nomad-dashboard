import AppKit
import NomadCore
import NomadUI
import SwiftUI

struct NomadLifeSettingsWindow: View {
    @ObservedObject var controller: NomadLifeController
    @ObservedObject var notifications: UserNotificationCenterNomadLifeDelivery

    var body: some View {
        VStack(spacing: 0) {
            if controller.preferences.areQuietAlertsEnabled {
                HStack {
                    Label(permissionDescription, systemImage: notifications.authorizationStatus == .authorized ? "bell.badge" : "bell.slash")
                    Spacer()
                    if notifications.authorizationStatus == .denied {
                        Button("Open Notification Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    } else if notifications.authorizationStatus == .notDetermined {
                        Button("Allow Notifications") { notifications.requestPermission() }
                    }
                }
                .font(.caption).padding(16)
                Divider()
            }
            NomadLifePreferencesView(controller: controller)
        }
        .onAppear { notifications.refreshAuthorization() }
        .frame(minWidth: 560, minHeight: 540)
    }

    private var permissionDescription: String {
        switch notifications.authorizationStatus {
        case .authorized, .provisional, .ephemeral: "Quiet alerts are enabled. Notifications are silent."
        case .denied: "macOS notifications are turned off for Nomad."
        case .notDetermined: "Allow notifications to receive quiet alerts."
        @unknown default: "Check notification permissions in macOS Settings."
        }
    }
}
