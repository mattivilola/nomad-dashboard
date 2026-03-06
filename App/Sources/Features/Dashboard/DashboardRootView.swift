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

    var body: some View {
        DashboardPanelView(
            snapshot: snapshotStore.snapshot,
            isPublicIPLocationEnabled: settingsStore.settings.publicIPGeolocationEnabled,
            versionDescription: AppRuntimeInfo.versionDescription,
            refreshAction: refresh,
            copyIPAddressAction: copyIPAddress,
            openNetworkSettingsAction: openNetworkSettings,
            checkForUpdatesAction: checkForUpdatesAction,
            openSettingsAction: openSettings,
            openAboutAction: openAbout
        )
        .task {
            snapshotStore.start()
            if settingsStore.settings.useCurrentLocationForWeather {
                locationStore.prepareForWeather()
            }
        }
        .onReceive(locationStore.$currentCoordinate) { coordinate in
            snapshotStore.setWeatherCoordinate(coordinate)
            Task {
                await snapshotStore.refresh(manual: true)
            }
        }
    }

    private func refresh() {
        if settingsStore.settings.useCurrentLocationForWeather {
            locationStore.refreshLocation()
        }

        Task {
            await snapshotStore.refresh(manual: true)
        }
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
        openAppWindow(id: "settings")
    }

    private func openAbout() {
        openAppWindow(id: "about")
    }

    private func openAppWindow(id: String) {
        DispatchQueue.main.async {
            openWindow(id: id)
            NSApp.activate(ignoringOtherApps: true)
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
