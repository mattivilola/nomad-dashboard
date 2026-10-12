import AppKit
import NomadCore
import NomadUI
import SwiftUI
import UserNotifications

struct ConnectionDataSettingsPage: View {
    @ObservedObject var settingsStore: AppSettingsStore
    @ObservedObject var snapshotStore: DashboardSnapshotStore
    @ObservedObject var lifeController: NomadLifeController
    @ObservedObject var notifications: UserNotificationCenterNomadLifeDelivery
    @ObservedObject var navigationController: SettingsNavigationController

    var body: some View {
        SettingsPageForm(page: .connectionAndData, navigationController: navigationController) {
            dataUsageSection
            dataGuardSection
            quietAlertsSection
        }
        .onAppear { notifications.refreshAuthorization() }
    }

    private var dataUsageSection: some View {
        Section {
            Picker("Data usage", selection: settingsStore.binding(\.dataUsageMode)) {
                ForEach(DataUsageMode.allCases, id: \.self) { mode in Text(mode.title).tag(mode) }
            }
            .pickerStyle(.segmented)
            Text("Automatic reduces optional downloads on hotspots, Low Data Mode, Low Power Mode, or when your Mac is under thermal pressure. Choose Low Data for mobile routers that look like regular Wi-Fi.")
                .font(.caption).foregroundStyle(.secondary)
            LabeledContent("Offline essentials", value: "Saved automatically")
            Text("Your enabled travel cards stay available offline with their source and last update time. Opening the dashboard reuses fresh data; Refresh fetches once on demand.")
                .font(.caption).foregroundStyle(.secondary)
            if let error = snapshotStore.offlineCacheError {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
        } header: {
            Text("Data usage")
        }
    }

    private var dataGuardSection: some View {
        Section {
            Toggle("Data Guard (metered tracking)", isOn: settingsStore.binding(\.meteredDataEnabled))
                .id(SettingsFocusTarget.dataGuard.rawValue)
            Toggle("Auto-monitor expensive connections", isOn: settingsStore.binding(\.autoEnableOnExpensivePath))
            Toggle("Auto-monitor remembered Wi‑Fi hotspots", isOn: settingsStore.binding(\.autoMonitorRememberedWiFiHotspots))
            Picker("Default billing period", selection: settingsStore.binding(\.defaultMeteredBillingPeriod)) {
                ForEach(MeteredBillingPeriod.allCases, id: \.self) { period in
                    Text(period.title).tag(period)
                }
            }
            Stepper(
                value: defaultMeteredCapGigabytesBinding,
                in: 1...200,
                step: 1
            ) {
                Text("Default cap: \(defaultMeteredCapGigabytesBinding.wrappedValue) GB")
            }
            if !settingsStore.settings.knownMeteredProfiles.isEmpty {
                ForEach(settingsStore.settings.knownMeteredProfiles) { profile in
                    LabeledContent(profile.displayName, value: profile.capBytes.map { MeteredUsageFormatting.byteCount($0) } ?? "No cap")
                }
            }
            Button("Reset Data Guard counters") {
                Task { await snapshotStore.resetMeteredUsagePeriod() }
            }
        } header: {
            Text("Data Guard")
        } footer: {
            SettingsFooter("Data Guard measures traffic on your Mac's default-route interface. It warns before caps and pauses Nomad's large downloads at the limit. It does not block other apps or system updates. Showing usage in the menu bar is in General, and reading Wi‑Fi names is in Privacy & Location.")
        }
    }

    private var quietAlertsSection: some View {
        Section {
            Toggle("Allow quiet connection alerts", isOn: $lifeController.preferences.areQuietAlertsEnabled)
                .id(SettingsFocusTarget.quietAlerts.rawValue)

            Stepper("Quiet hours start: \(lifeController.preferences.quietHoursStart):00", value: $lifeController.preferences.quietHoursStart, in: 0...23)
            Stepper("Quiet hours end: \(lifeController.preferences.quietHoursEnd):00", value: $lifeController.preferences.quietHoursEnd, in: 0...23)

            if lifeController.preferences.areQuietAlertsEnabled {
                notificationPermissionRow
            }
        } header: {
            Text("Quiet connection alerts")
        } footer: {
            SettingsFooter("Alerts use sustained state changes, cooldowns, and quiet hours. They never include a location or IP address.")
        }
    }

    private var notificationPermissionRow: some View {
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
        .font(.caption)
    }

    private var permissionDescription: String {
        switch notifications.authorizationStatus {
        case .authorized, .provisional, .ephemeral: "Quiet alerts are enabled. Notifications are silent."
        case .denied: "macOS notifications are turned off for Nomad."
        case .notDetermined: "Allow notifications to receive quiet alerts."
        @unknown default: "Check notification permissions in macOS Settings."
        }
    }

    private var defaultMeteredCapGigabytesBinding: Binding<Int> {
        Binding(
            get: {
                let bytes = settingsStore.settings.defaultMeteredCapBytes ?? (5 * 1_024 * 1_024 * 1_024)
                return max(1, Int(bytes / (1_024 * 1_024 * 1_024)))
            },
            set: { newValue in
                settingsStore.settings.defaultMeteredCapBytes = UInt64(max(1, newValue)) * 1_024 * 1_024 * 1_024
            }
        )
    }
}
