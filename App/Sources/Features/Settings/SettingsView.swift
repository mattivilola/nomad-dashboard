import CoreLocation
import NomadCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsStore: AppSettingsStore
    @ObservedObject var snapshotStore: DashboardSnapshotStore
    @ObservedObject var locationStore: CurrentLocationStore
    @ObservedObject var launchAtLoginController: LaunchAtLoginController
    let updatesEnabled: Bool
    @Environment(\.openURL) private var openURL
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Settings")
                    .font(.title2.weight(.semibold))

                Text("Manage startup behavior, privacy, and refresh cadence for Nomad Dashboard.")
                    .foregroundStyle(.secondary)
            }

            Form {
                Section {
                    Picker("Appearance", selection: binding(\.appearanceMode)) {
                        ForEach(AppAppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.displayName)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Launch at login", isOn: launchAtLoginBinding)

                    if updatesEnabled {
                        Toggle("Check for updates automatically", isOn: binding(\.automaticUpdateChecksEnabled))
                    } else {
                        LabeledContent("Updates") {
                            Text("Paused")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("General")
                } footer: {
                    Text(updatesEnabled ? "System follows your macOS appearance. The dashboard header button flips quickly between dark and light, and all preferences stay across relaunches." : "System follows your macOS appearance. The dashboard header button flips quickly between dark and light, and all preferences stay across relaunches. In-app update checks stay paused until the release pipeline is ready.")
                }

                Section {
                    Toggle("Use current location for weather", isOn: weatherLocationBinding)
                    Toggle("Show external IP location", isOn: binding(\.publicIPGeolocationEnabled))
                    Toggle("Save visited places locally", isOn: visitedPlacesBinding)

                    LabeledContent("Location status") {
                        Text(locationStore.authorizationSummary)
                            .foregroundStyle(.secondary)
                    }

                    Button(locationActionTitle) {
                        handleLocationAction()
                    }
                } header: {
                    Text("Privacy & Location")
                } footer: {
                    Text("Weather and local weather alerts use device location only when you opt in. External IP lookups use a third-party geolocation service to show city and country, and that display is on by default for new installs. Visited places stay on this Mac until you clear them.")
                }

                Section {
                    Toggle("Travel advisory", isOn: binding(\.travelAdvisoryEnabled))
                    Toggle("Weather alerts", isOn: travelWeatherAlertsBinding)
                    Toggle("Regional security", isOn: binding(\.regionalSecurityEnabled))
                } header: {
                    Text("Travel Alerts")
                } footer: {
                    Text("Travel advisory uses Smartraveller by default and starts enabled. Regional security uses ReliefWeb, and weather alerts use WeatherKit. Advisory and security check your current country plus bordering countries; weather alerts use your current location when available.")
                }

                Section {
                    Stepper(value: fastRefreshBinding, in: 2...10) {
                        LabeledContent("Fast refresh") {
                            Text("\(fastRefreshValue) seconds")
                                .monospacedDigit()
                        }
                    }

                    Stepper(value: slowRefreshBinding, in: 30...300, step: 15) {
                        LabeledContent("Slow refresh") {
                            Text("\(slowRefreshValue) seconds")
                                .monospacedDigit()
                        }
                    }

                    Stepper(value: binding(\.historyRetentionHours), in: 6...72) {
                        LabeledContent("Metric retention") {
                            Text("\(settingsStore.settings.historyRetentionHours) hours")
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text("Refresh & History")
                } footer: {
                    Text("Fast refresh controls lightweight polling. Slow refresh covers heavier network, power, location, and weather lookups.")
                }

                Section {
                    LabeledContent("Version", value: AppRuntimeInfo.versionDescription)

                    if updatesEnabled {
                        Button("Check for Updates") {
                            snapshotStore.checkForUpdates()
                        }
                    } else {
                        Text(UpdateFeatureConfiguration.pausedReason)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button("About Nomad Dashboard") {
                        openWindow(id: "about")
                    }

                    Button("Open Visited Map") {
                        openWindow(id: "visited-map")
                    }
                } header: {
                    Text("Support")
                }
            }
            .formStyle(.grouped)
        }
        .padding(20)
        .frame(width: 560, height: 520, alignment: .topLeading)
        .onReceive(locationStore.$currentLocation) { location in
            snapshotStore.setCurrentLocation(location)

            guard settingsStore.settings.usesDeviceLocation else {
                return
            }

            Task {
                await snapshotStore.refresh(manual: true)
            }
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { settingsStore.settings[keyPath: keyPath] = $0 }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLoginController.isEnabled },
            set: { newValue in
                launchAtLoginController.setEnabled(newValue)
                settingsStore.settings.launchAtLoginEnabled = launchAtLoginController.isEnabled
            }
        )
    }

    private var weatherLocationBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.useCurrentLocationForWeather },
            set: { isEnabled in
                settingsStore.settings.useCurrentLocationForWeather = isEnabled
                snapshotStore.setCurrentLocation(locationStore.currentLocation)

                if settingsStore.settings.usesDeviceLocation {
                    locationStore.prepareForWeather()
                }
            }
        )
    }

    private var travelWeatherAlertsBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.travelWeatherAlertsEnabled },
            set: { isEnabled in
                settingsStore.settings.travelWeatherAlertsEnabled = isEnabled
                snapshotStore.setCurrentLocation(locationStore.currentLocation)

                if settingsStore.settings.usesDeviceLocation {
                    locationStore.prepareForWeather()
                }
            }
        )
    }

    private var visitedPlacesBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.visitedPlacesEnabled },
            set: { isEnabled in
                settingsStore.settings.visitedPlacesEnabled = isEnabled
                snapshotStore.setCurrentLocation(locationStore.currentLocation)

                if settingsStore.settings.usesDeviceLocation {
                    locationStore.prepareForWeather()
                }
            }
        )
    }

    private var fastRefreshBinding: Binding<Int> {
        Binding(
            get: { fastRefreshValue },
            set: { settingsStore.settings.refreshIntervalSeconds = Double($0) }
        )
    }

    private var slowRefreshBinding: Binding<Int> {
        Binding(
            get: { slowRefreshValue },
            set: { settingsStore.settings.slowRefreshIntervalSeconds = Double($0) }
        )
    }

    private var fastRefreshValue: Int {
        Int(settingsStore.settings.refreshIntervalSeconds)
    }

    private var slowRefreshValue: Int {
        Int(settingsStore.settings.slowRefreshIntervalSeconds)
    }

    private var locationActionTitle: String {
        switch locationStore.authorizationStatus {
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
        switch locationStore.authorizationStatus {
        case .notDetermined:
            locationStore.requestAuthorization()
        case .denied, .restricted:
            openLocationSettings()
        case .authorizedAlways, .authorizedWhenInUse:
            snapshotStore.setCurrentLocation(locationStore.currentLocation)
            locationStore.refreshLocation()
        @unknown default:
            openLocationSettings()
        }
    }

    private func openLocationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") else {
            return
        }

        openURL(url)
    }
}
