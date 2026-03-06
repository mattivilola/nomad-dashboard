import CoreLocation
import NomadCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsStore: AppSettingsStore
    @ObservedObject var snapshotStore: DashboardSnapshotStore
    @ObservedObject var locationStore: CurrentLocationStore
    @ObservedObject var launchAtLoginController: LaunchAtLoginController
    @Environment(\.openURL) private var openURL
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Settings")
                    .font(.title2.weight(.semibold))

                Text("Manage update behavior, privacy, and refresh cadence for Nomad Dashboard.")
                    .foregroundStyle(.secondary)
            }

            Form {
                Section {
                    Toggle("Launch at login", isOn: launchAtLoginBinding)
                    Toggle("Check for updates automatically", isOn: binding(\.automaticUpdateChecksEnabled))
                } header: {
                    Text("General")
                } footer: {
                    Text("Nomad Dashboard stays menu-bar-first and keeps these preferences across relaunches.")
                }

                Section {
                    Toggle("Use current location for weather", isOn: weatherLocationBinding)
                    Toggle("Enable public IP geolocation", isOn: binding(\.publicIPGeolocationEnabled))

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
                    Text("Weather uses device location only when you opt in. Public IP geolocation stays disabled until you enable it.")
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

                    Button("Check for Updates") {
                        snapshotStore.checkForUpdates()
                    }

                    Button("About Nomad Dashboard") {
                        openWindow(id: "about")
                    }
                } header: {
                    Text("Support")
                }
            }
            .formStyle(.grouped)
        }
        .padding(20)
        .frame(width: 560, height: 520, alignment: .topLeading)
        .onReceive(locationStore.$currentCoordinate) { coordinate in
            snapshotStore.setWeatherCoordinate(coordinate)

            guard settingsStore.settings.useCurrentLocationForWeather else {
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
                snapshotStore.setWeatherCoordinate(locationStore.currentCoordinate)

                if isEnabled {
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
            snapshotStore.setWeatherCoordinate(locationStore.currentCoordinate)
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
