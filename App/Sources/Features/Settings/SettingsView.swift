import NomadCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsStore: AppSettingsStore
    @ObservedObject var locationStore: CurrentLocationStore
    @ObservedObject var launchAtLoginController: LaunchAtLoginController

    var body: some View {
        Form {
            Section("Nomad Metrics") {
                Toggle("Use current location for weather", isOn: binding(\.useCurrentLocationForWeather))
                    .onChange(of: settingsStore.settings.useCurrentLocationForWeather) { _, isEnabled in
                        if isEnabled {
                            locationStore.prepareForWeather()
                        }
                    }

                Toggle("Enable public IP geolocation", isOn: binding(\.publicIPGeolocationEnabled))
                Stepper(
                    "Metric retention: \(settingsStore.settings.historyRetentionHours) hours",
                    value: binding(\.historyRetentionHours),
                    in: 6...72
                )
            }

            Section("Behavior") {
                Toggle("Check for updates automatically", isOn: binding(\.automaticUpdateChecksEnabled))

                Toggle(
                    "Launch at login",
                    isOn: Binding(
                        get: { launchAtLoginController.isEnabled },
                        set: { newValue in
                            launchAtLoginController.setEnabled(newValue)
                            settingsStore.settings.launchAtLoginEnabled = newValue
                        }
                    )
                )
            }

            Section("Refresh Cadence") {
                Stepper(
                    "Fast polling: \(Int(settingsStore.settings.refreshIntervalSeconds)) seconds",
                    value: Binding(
                        get: { Int(settingsStore.settings.refreshIntervalSeconds) },
                        set: { settingsStore.settings.refreshIntervalSeconds = Double($0) }
                    ),
                    in: 2...10
                )

                Stepper(
                    "Slow refresh: \(Int(settingsStore.settings.slowRefreshIntervalSeconds)) seconds",
                    value: Binding(
                        get: { Int(settingsStore.settings.slowRefreshIntervalSeconds) },
                        set: { settingsStore.settings.slowRefreshIntervalSeconds = Double($0) }
                    ),
                    in: 30...300,
                    step: 15
                )
            }

            Section("Permissions") {
                LabeledContent("Location status", value: locationStore.authorizationSummary)
                Button("Request location access") {
                    locationStore.requestAuthorization()
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 520)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { settingsStore.settings[keyPath: keyPath] = $0 }
        )
    }
}

