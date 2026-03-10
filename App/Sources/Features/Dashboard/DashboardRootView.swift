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
    @ObservedObject var settingsNavigationController: SettingsNavigationController
    let updatesEnabled: Bool

    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedFuelStation: FuelStationMapDestination?

    var body: some View {
        DashboardPanelView(
            snapshot: snapshotStore.snapshot,
            settings: settingsStore.settings,
            dashboardCardOrder: settingsStore.settings.dashboardCardOrder,
            isPublicIPLocationEnabled: settingsStore.settings.publicIPGeolocationEnabled,
            travelAlertPreferences: settingsStore.settings.travelAlertPreferences,
            versionDescription: AppRuntimeInfo.versionDescription,
            buildFlavorBadgeTitle: AppRuntimeInfo.headerFlavorBadgeTitle,
            weatherAvailabilityExplanation: AppRuntimeInfo.weatherAvailabilityExplanation,
            locationStatusDetail: locationStore.diagnostics.detailText,
            appIcon: AppRuntimeInfo.applicationIconImage,
            refreshAction: refresh,
            toggleAppearanceAction: toggleAppearance,
            copyIPAddressAction: copyIPAddress,
            openVisitedMapAction: openVisitedMap,
            openNetworkSettingsAction: openNetworkSettings,
            openFuelStationMapPreviewAction: openFuelStationMapPreview,
            openFuelStationInGoogleMapsAction: openFuelStationInGoogleMaps,
            checkForUpdatesAction: checkForUpdatesAction,
            openSettingsAction: openSettings,
            openSurfSpotSettingsAction: openSurfSpotSettings,
            openAboutAction: openAbout,
            quitAction: quitApplication,
            onCardOrderChange: persistDashboardCardOrder
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
        .sheet(item: $selectedFuelStation) { station in
            FuelStationPreviewSheet(
                station: station,
                openInGoogleMapsAction: { openFuelStationInGoogleMaps(station) }
            )
        }
    }

    private func refresh() {
        if settingsStore.settings.usesDeviceLocation {
            locationStore.requestCurrentLocation()
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

    private func openSurfSpotSettings() {
        settingsNavigationController.focus(.surfSpot)
        openDashboardWindow(.settings)
    }

    private func openVisitedMap() {
        openDashboardWindow(.visitedMap)
    }

    private func openFuelStationMapPreview(_ station: FuelStationMapDestination) {
        guard station.isCoordinateValid else {
            return
        }

        selectedFuelStation = station
    }

    private func openFuelStationInGoogleMaps(_ station: FuelStationMapDestination) {
        guard let url = station.googleMapsURL else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func quitApplication() {
        NSApp.terminate(nil)
    }

    private func persistDashboardCardOrder(_ cardOrder: [DashboardCardID]) {
        let sanitizedOrder = DashboardCardID.sanitizedOrder(cardOrder)
        guard settingsStore.settings.dashboardCardOrder != sanitizedOrder else {
            return
        }

        settingsStore.settings.dashboardCardOrder = sanitizedOrder
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

private struct FuelStationPreviewSheet: View {
    let station: FuelStationMapDestination
    let openInGoogleMapsAction: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(station.stationName)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(NomadTheme.primaryText)

                    Text(station.fuelType.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(station.fuelType == .diesel ? NomadTheme.teal : NomadTheme.sand)

                    if let addressLine = station.addressLine {
                        Text(addressLine)
                            .font(.subheadline)
                            .foregroundStyle(NomadTheme.secondaryText)
                    }
                }

                Spacer(minLength: 12)

                Text(NomadFormatters.fuelPricePerLiter(station.pricePerLiter))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(station.fuelType == .diesel ? NomadTheme.teal : NomadTheme.sand)
            }

            FuelStationMapView(
                stationName: station.stationName,
                coordinate: station.coordinate
            )
            .frame(width: 420, height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(NomadTheme.cardBorder.opacity(0.85), lineWidth: 1)
            )

            HStack(spacing: 10) {
                Button("Open in Google Maps") {
                    openInGoogleMapsAction()
                }
                .buttonStyle(.borderedProminent)

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }

            if let updatedAt = station.updatedAt {
                Text("Updated \(NomadFormatters.compactClockTime(updatedAt))")
                    .font(.caption)
                    .foregroundStyle(NomadTheme.tertiaryText)
            }
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 420, alignment: .topLeading)
        .background(NomadTheme.background)
    }
}

struct MenuBarStatusLabel: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        let presentation = snapshot.menuBarStatusPresentation

        HStack(spacing: 6) {
            Image(systemName: presentation.symbolName)
            if let text = presentation.text {
                Text(text)
                    .monospacedDigit()
            }
        }
    }
}
