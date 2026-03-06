import AppKit
import Combine
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
        let updateCoordinator: any UpdateCoordinator

        if UpdateFeatureConfiguration.isEnabled {
            updateCoordinator = SparkleUpdateCoordinator(automaticChecksEnabled: persistedSettings.automaticUpdateChecksEnabled)
        } else {
            updateCoordinator = PausedUpdateCoordinator()
        }

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

        DispatchQueue.main.async {
            applyAppAppearance(persistedSettings.appearanceMode)
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
                launchAtLoginController: launchAtLoginController,
                updatesEnabled: UpdateFeatureConfiguration.isEnabled
            )
            .modifier(SceneAppearanceSync(settingsStore: settingsStore))
        } label: {
            MenuBarStatusLabel(snapshot: snapshotStore.snapshot)
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsView(
                settingsStore: settingsStore,
                snapshotStore: snapshotStore,
                locationStore: locationStore,
                launchAtLoginController: launchAtLoginController,
                updatesEnabled: UpdateFeatureConfiguration.isEnabled
            )
            .modifier(SceneAppearanceSync(settingsStore: settingsStore))
        }
        .windowResizability(.contentSize)

        Window("About Nomad Dashboard", id: "about") {
            AboutView()
                .modifier(SceneAppearanceSync(settingsStore: settingsStore))
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
private func applyAppAppearance(_ appearanceMode: AppAppearanceMode) {
    let appearance = appearanceMode.appKitAppearance
    NSApp.appearance = appearance

    for window in NSApp.windows {
        window.appearance = appearance
    }
}

private struct SceneAppearanceSync: ViewModifier {
    @ObservedObject var settingsStore: AppSettingsStore

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(settingsStore.settings.appearanceMode.preferredColorScheme)
            .task {
                applyAppAppearance(settingsStore.settings.appearanceMode)
            }
            .onReceive(settingsStore.$settings.map(\.appearanceMode).removeDuplicates()) { appearanceMode in
                applyAppAppearance(appearanceMode)
            }
    }
}
