import NomadCore
import NomadUI
import SwiftUI

@main
struct NomadDashboardApp: App {
    @StateObject private var settingsStore: AppSettingsStore
    @StateObject private var snapshotStore: DashboardSnapshotStore
    @StateObject private var locationStore: CurrentLocationStore
    @StateObject private var launchAtLoginController: LaunchAtLoginController

    init() {
        let settingsStore = AppSettingsStore()
        let persistedSettings = settingsStore.settings
        let applicationSupportDirectory = (try? FileManager.default.nomadApplicationSupportDirectory())
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("Nomad Dashboard", isDirectory: true)
        let updateCoordinator = SparkleUpdateCoordinator(
            automaticChecksEnabled: persistedSettings.automaticUpdateChecksEnabled
        )
        let dependencies = DashboardDependencies.live(
            applicationSupportDirectory: applicationSupportDirectory,
            latencyHosts: persistedSettings.latencyHosts,
            historyRetentionHours: persistedSettings.historyRetentionHours,
            updateCoordinator: updateCoordinator
        )
        let launchAtLoginController = LaunchAtLoginController(initialEnabled: persistedSettings.launchAtLoginEnabled)

        if settingsStore.settings.launchAtLoginEnabled != launchAtLoginController.isEnabled {
            settingsStore.settings.launchAtLoginEnabled = launchAtLoginController.isEnabled
        }

        _settingsStore = StateObject(wrappedValue: settingsStore)
        _snapshotStore = StateObject(wrappedValue: DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies))
        _locationStore = StateObject(wrappedValue: CurrentLocationStore())
        _launchAtLoginController = StateObject(wrappedValue: launchAtLoginController)
    }

    var body: some Scene {
        MenuBarExtra {
            DashboardRootView(
                snapshotStore: snapshotStore,
                settingsStore: settingsStore,
                locationStore: locationStore,
                launchAtLoginController: launchAtLoginController
            )
        } label: {
            MenuBarStatusLabel(snapshot: snapshotStore.snapshot)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                settingsStore: settingsStore,
                snapshotStore: snapshotStore,
                locationStore: locationStore,
                launchAtLoginController: launchAtLoginController
            )
        }

        Window("About Nomad Dashboard", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}
