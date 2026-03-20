import AppKit
import Combine
import CoreLocation
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
    let analytics: AppAnalytics

    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedFuelStation: FuelStationMapDestination?
    @State private var locationRefreshTask: Task<Void, Never>?
    @State private var pendingLocationRefresh: CLLocation?
    @State private var lastLocationRefreshLocation: CLLocation?

    var body: some View {
        DashboardPanelView(
            snapshot: snapshotStore.snapshot,
            refreshActivity: snapshotStore.refreshActivity,
            settings: settingsStore.settings,
            dashboardCardOrder: settingsStore.settings.dashboardCardOrder,
            dashboardCardWidthModes: settingsStore.settings.dashboardCardWidthModes,
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
            onCardOrderChange: persistDashboardCardOrder,
            onCardWidthModesChange: persistDashboardCardWidthModes
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

            guard settingsStore.settings.usesDeviceLocation else {
                return
            }

            scheduleLocationRefresh(for: location)
        }
        .sheet(item: $selectedFuelStation) { station in
            FuelStationPreviewSheet(
                station: station,
                openInGoogleMapsAction: { openFuelStationInGoogleMaps(station) }
            )
        }
        .onDisappear {
            locationRefreshTask?.cancel()
        }
        .onAppear {
            analytics.recordPrimaryUIOpened(analyticsEnabled: settingsStore.settings.shareAnonymousAnalytics)
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

    private func persistDashboardCardWidthModes(_ widthModes: [DashboardCardID: DashboardCardWidthMode]) {
        let sanitizedWidthModes = DashboardCardID.sanitizedWidthModes(widthModes)
        guard settingsStore.settings.dashboardCardWidthModes != sanitizedWidthModes else {
            return
        }

        settingsStore.settings.dashboardCardWidthModes = sanitizedWidthModes
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

    private func scheduleLocationRefresh(for location: CLLocation?) {
        guard let location, shouldScheduleLocationRefresh(for: location) else {
            return
        }

        pendingLocationRefresh = location
        locationRefreshTask?.cancel()
        locationRefreshTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else {
                return
            }

            await snapshotStore.refresh(manual: true)

            await MainActor.run {
                lastLocationRefreshLocation = location
                pendingLocationRefresh = nil
            }
        }
    }

    private func shouldScheduleLocationRefresh(for location: CLLocation) -> Bool {
        if let pendingLocationRefresh,
           hasInsignificantLocationChange(from: pendingLocationRefresh, to: location)
        {
            return false
        }

        if let lastLocationRefreshLocation,
           hasInsignificantLocationChange(from: lastLocationRefreshLocation, to: location)
        {
            return false
        }

        return true
    }

    private func hasInsignificantLocationChange(from previous: CLLocation, to current: CLLocation) -> Bool {
        previous.distance(from: current) < 250
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
            statusIcon(for: presentation)
            if let text = presentation.text {
                Text(text)
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private func statusIcon(for presentation: MenuBarStatusPresentation) -> some View {
        StatusSymbolView(
            systemName: presentation.symbolName,
            treatment: presentation.tone == .attention ? .warningBadge : .plain,
            size: .menuBar
        )
    }
}
