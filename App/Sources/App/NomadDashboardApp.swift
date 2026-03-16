import NomadCore
import NomadUI
import SwiftUI

@main
struct NomadDashboardApp: App {
    @StateObject private var settingsStore: AppSettingsStore
    @StateObject private var snapshotStore: DashboardSnapshotStore
    @StateObject private var locationStore: CurrentLocationStore
    @StateObject private var launchAtLoginController: LaunchAtLoginController
    @StateObject private var settingsNavigationController: SettingsNavigationController
    private let analytics: AppAnalytics

    init() {
        let settingsStore = AppSettingsStore()
        let persistedSettings = settingsStore.settings
        let applicationSupportDirectory = (try? FileManager.default.nomadApplicationSupportDirectory())
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("Nomad Dashboard", isDirectory: true)
        let updateCoordinator: any UpdateCoordinator = if UpdateFeatureConfiguration.isEnabled {
            SparkleUpdateCoordinator(automaticChecksEnabled: persistedSettings.automaticUpdateChecksEnabled)
        } else {
            PausedUpdateCoordinator()
        }

        let dependencies = DashboardDependencies.live(
            applicationSupportDirectory: applicationSupportDirectory,
            latencyHosts: persistedSettings.latencyHosts,
            historyRetentionHours: persistedSettings.historyRetentionHours,
            reliefWebAppName: reliefWebAppName(),
            tankerkonigAPIKey: AppRuntimeConfiguration.resolveTankerkonigAPIKey(
                userSetting: persistedSettings.tankerkonigAPIKey
            ),
            updateCoordinator: updateCoordinator
        )
        let launchAtLoginController = LaunchAtLoginController(initialEnabled: persistedSettings.launchAtLoginEnabled)
        let analyticsContext = AnalyticsContext(
            appID: AppRuntimeInfo.telemetryDeckAppID,
            appName: AppRuntimeInfo.appName,
            appVersion: AppRuntimeInfo.marketingVersion,
            buildNumber: AppRuntimeInfo.buildNumber,
            distributionChannel: AppRuntimeInfo.analyticsDistributionChannel,
            appType: .menuBar
        )
        let analytics = AppAnalytics(
            client: AnalyticsClientFactory.makeClient(context: analyticsContext),
            keyPrefix: "\(AppRuntimeInfo.bundleIdentifier).Analytics"
        )

        if settingsStore.settings.launchAtLoginEnabled != launchAtLoginController.isEnabled {
            settingsStore.settings.launchAtLoginEnabled = launchAtLoginController.isEnabled
        }

        _settingsStore = StateObject(wrappedValue: settingsStore)
        _snapshotStore = StateObject(wrappedValue: DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies))
        _locationStore = StateObject(wrappedValue: CurrentLocationStore())
        _launchAtLoginController = StateObject(wrappedValue: launchAtLoginController)
        _settingsNavigationController = StateObject(wrappedValue: SettingsNavigationController())
        self.analytics = analytics
        analytics.recordAppLaunch()
    }

    var body: some Scene {
        MenuBarExtra {
            DashboardRootView(
                snapshotStore: snapshotStore,
                settingsStore: settingsStore,
                locationStore: locationStore,
                launchAtLoginController: launchAtLoginController,
                settingsNavigationController: settingsNavigationController,
                updatesEnabled: UpdateFeatureConfiguration.isEnabled,
                analytics: analytics
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
                settingsNavigationController: settingsNavigationController,
                updatesEnabled: UpdateFeatureConfiguration.isEnabled,
                analytics: analytics
            )
            .modifier(SceneAppearanceSync(settingsStore: settingsStore))
        }
        .windowResizability(.contentSize)

        Window("About Nomad Dashboard", id: "about") {
            AboutView()
                .modifier(SceneAppearanceSync(settingsStore: settingsStore))
        }
        .windowResizability(.contentSize)

        Window("Visited Map", id: "visited-map") {
            VisitedMapWindowView(
                snapshotStore: snapshotStore,
                settingsStore: settingsStore
            )
            .modifier(SceneAppearanceSync(settingsStore: settingsStore))
        }
    }
}

private func reliefWebAppName() -> String? {
    if let environmentValue = ProcessInfo.processInfo.environment["RELIEFWEB_APPNAME"]?
        .trimmingCharacters(in: .whitespacesAndNewlines), environmentValue.isEmpty == false
    {
        return environmentValue
    }

    if let plistValue = Bundle.main.object(forInfoDictionaryKey: "ReliefWebAppName") as? String {
        let trimmedValue = plistValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedValue.isEmpty == false {
            return trimmedValue
        }
    }

    return Bundle.main.bundleIdentifier
}
private struct SceneAppearanceSync: ViewModifier {
    @ObservedObject var settingsStore: AppSettingsStore

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(settingsStore.settings.appearanceMode.preferredColorScheme)
    }
}
