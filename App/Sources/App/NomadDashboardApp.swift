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
        let applicationSupportDirectory = (try? FileManager.default.nomadApplicationSupportDirectory())
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("Nomad Dashboard", isDirectory: true)
        let updateCoordinator = SparkleUpdateCoordinator()
        let dependencies = DashboardDependencies.live(
            applicationSupportDirectory: applicationSupportDirectory,
            latencyHosts: settingsStore.settings.latencyHosts,
            updateCoordinator: updateCoordinator
        )

        _settingsStore = StateObject(wrappedValue: settingsStore)
        _snapshotStore = StateObject(wrappedValue: DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies))
        _locationStore = StateObject(wrappedValue: CurrentLocationStore())
        _launchAtLoginController = StateObject(wrappedValue: LaunchAtLoginController(initialEnabled: settingsStore.settings.launchAtLoginEnabled))
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

