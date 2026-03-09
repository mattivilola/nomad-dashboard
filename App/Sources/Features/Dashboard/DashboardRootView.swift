import AppKit
import Combine
import NomadCore
import NomadUI
import SwiftUI

struct DashboardRootView: View {
    @ObservedObject var snapshotStore: DashboardSnapshotStore
    @ObservedObject var settingsStore: AppSettingsStore
    @ObservedObject var locationStore: CurrentLocationStore
    @ObservedObject var launchAtLoginController: LaunchAtLoginController
    let updatesEnabled: Bool

    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        DashboardPanelView(
            snapshot: snapshotStore.snapshot,
            isPublicIPLocationEnabled: settingsStore.settings.publicIPGeolocationEnabled,
            travelAlertPreferences: settingsStore.settings.travelAlertPreferences,
            versionDescription: AppRuntimeInfo.versionDescription,
            appIcon: AppRuntimeInfo.applicationIconImage,
            refreshAction: refresh,
            toggleAppearanceAction: toggleAppearance,
            copyIPAddressAction: copyIPAddress,
            openVisitedMapAction: openVisitedMap,
            openNetworkSettingsAction: openNetworkSettings,
            checkForUpdatesAction: checkForUpdatesAction,
            openSettingsAction: openSettings,
            openAboutAction: openAbout,
            quitAction: quitApplication
        )
        .task {
            snapshotStore.setCurrentLocation(locationStore.currentLocation)
            snapshotStore.start()
            if settingsStore.settings.usesDeviceLocation {
                locationStore.prepareForWeather()
            }
        }
        .onReceive(locationStore.$currentLocation) { location in
            snapshotStore.setCurrentLocation(location)
            Task {
                await snapshotStore.refresh(manual: true)
            }
        }
    }

    private func refresh() {
        if settingsStore.settings.usesDeviceLocation {
            locationStore.refreshLocation()
        }

        Task {
            await snapshotStore.refresh(manual: true)
        }
    }

    private func toggleAppearance() {
        settingsStore.settings.appearanceMode = settingsStore.settings.appearanceMode
            .toggled(resolvedSystemAppearanceIsDark: colorScheme == .dark)
    }

    private func copyIPAddress() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(snapshotStore.snapshot.travelContext.publicIP?.address ?? "", forType: .string)
    }

    private func openNetworkSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func openSettings() {
        openDashboardWindow(.settings)
    }

    private func openAbout() {
        openDashboardWindow(.about)
    }

    private func openVisitedMap() {
        openDashboardWindow(.visitedMap)
    }

    private func quitApplication() {
        NSApp.terminate(nil)
    }

    private func openDashboardWindow(_ destination: AppWindowDestination) {
        let sourceWindow = NSApp.keyWindow
        openAndActivateWindow(destination, with: openWindow)

        DispatchQueue.main.async {
            sourceWindow?.close()
        }
    }

    private var checkForUpdatesAction: (() -> Void)? {
        guard updatesEnabled else {
            return nil
        }

        return {
            snapshotStore.checkForUpdates()
        }
    }
}

struct MenuBarStatusLabel: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
            if let percentage = snapshot.power.snapshot?.chargePercent {
                Text("\(Int(percentage * 100))%")
                    .monospacedDigit()
            }
        }
    }

    private var symbolName: String {
        if snapshot.travelContext.vpn?.isActive == true {
            return "lock.shield.fill"
        }

        if let latency = snapshot.network.latency?.milliseconds, latency > 90 {
            return "wifi.exclamationmark"
        }

        return "suitcase.rolling.fill"
    }
}
