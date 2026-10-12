import CoreLocation
import NomadCore
import NomadUI
import SwiftUI

struct PrivacyLocationSettingsPage: View {
    @ObservedObject var settingsStore: AppSettingsStore
    @ObservedObject var snapshotStore: DashboardSnapshotStore
    @ObservedObject var locationStore: CurrentLocationStore
    @ObservedObject var navigationController: SettingsNavigationController

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        SettingsPageForm(page: .privacyAndLocation, navigationController: navigationController) {
            locationSection
            externalIPSection
            wifiNamesSection
            visitedPlacesSection
            analyticsSection
        }
    }

    private var locationSection: some View {
        Section {
            LabeledContent("Location status") {
                Text(locationStore.authorizationSummary)
                    .foregroundStyle(.secondary)
            }

            if let detail = locationStore.diagnostics.detailText {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(locationActionTitle) {
                handleLocationAction()
            }
            .disabled(locationStore.diagnostics.isRequestInProgress)
        } header: {
            Text("Location")
        } footer: {
            Text("Weather, nearby fuel prices, nearby emergency hospitals, and local weather alerts use device location only when you opt in.")
        }
    }

    private var externalIPSection: some View {
        Section {
            Toggle("Show external IP location", isOn: settingsStore.binding(\.publicIPGeolocationEnabled))
        } header: {
            Text("External IP location")
        } footer: {
            Text("External IP lookups use a third-party geolocation service to show city and country, and that display is on by default for new installs.")
        }
    }

    private var wifiNamesSection: some View {
        Section {
            Toggle("Use location to read Wi‑Fi names (SSIDs)", isOn: settingsStore.binding(\.useLocationForWiFiNames))
        } header: {
            Text("Wi‑Fi names")
        } footer: {
            Text("Data Guard reads the name of your current Wi‑Fi network to recognize remembered hotspots and apply their data caps. macOS only shares Wi‑Fi names with apps that may use your location.")
        }
    }

    private var visitedPlacesSection: some View {
        Section {
            Toggle(
                "Save visited places locally",
                isOn: settingsStore.locationAwareBinding(\.visitedPlacesEnabled, snapshotStore: snapshotStore, locationStore: locationStore)
            )
            .id(SettingsFocusTarget.visitedPlaces.rawValue)

            Button("Open Visited Map") {
                openAndActivateWindow(.visitedMap, with: openWindow)
            }
        } header: {
            Text("Visited places")
        } footer: {
            Text("Visited places and country-day history stay on this Mac until you clear them.")
        }
    }

    private var analyticsSection: some View {
        Section {
            Toggle("Share anonymous analytics", isOn: settingsStore.binding(\.shareAnonymousAnalytics))
        } header: {
            Text("Analytics")
        } footer: {
            Text("Anonymous install, launch, and daily background activity counts are always sent so app reach can be estimated; turn analytics off here to stop UI-based daily activity and window-open events.")
        }
    }

    private var locationActionTitle: String {
        if locationStore.diagnostics.isRequestInProgress {
            return "Requesting Location…"
        }

        if locationStore.diagnostics.isLocationServicesEnabled == false {
            return "Open Location Settings"
        }

        return switch locationStore.authorizationStatus {
        case .notDetermined:
            "Request Location Access"
        case .denied, .restricted:
            "Open Location Settings"
        case .authorizedAlways, .authorizedWhenInUse:
            "Refresh Current Location"
        @unknown default:
            "Open Location Settings"
        }
    }

    private func handleLocationAction() {
        if locationStore.diagnostics.isLocationServicesEnabled == false {
            CurrentLocationStore.openLocationPrivacySettings()
            return
        }

        switch locationStore.authorizationStatus {
        case .notDetermined:
            locationStore.requestAuthorization()
        case .denied, .restricted:
            CurrentLocationStore.openLocationPrivacySettings()
        case .authorizedAlways, .authorizedWhenInUse:
            snapshotStore.setCurrentLocation(locationStore.currentLocation)
            locationStore.requestCurrentLocation()
        @unknown default:
            CurrentLocationStore.openLocationPrivacySettings()
        }
    }
}
