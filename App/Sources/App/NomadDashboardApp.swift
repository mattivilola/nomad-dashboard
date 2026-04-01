import AppKit
import NomadCore
import NomadUI
import SwiftUI

@main
struct NomadDashboardApp: App {
    @StateObject private var settingsStore: AppSettingsStore
    @StateObject private var snapshotStore: DashboardSnapshotStore
    @StateObject private var locationStore: CurrentLocationStore
    @StateObject private var launchAtLoginController: LaunchAtLoginController
    @StateObject private var timeTrackingController: ProjectTimeTrackingController
    @StateObject private var settingsNavigationController: SettingsNavigationController
    private let analytics: AppAnalytics

    init() {
        let storageNamespace = AppRuntimeInfo.storageNamespace
        let settingsStore = AppSettingsStore(key: storageNamespace.settingsKey)
        let persistedSettings = settingsStore.settings
        let applicationSupportDirectory = (try? FileManager.default.nomadApplicationSupportDirectory(namespace: storageNamespace))
            ?? FileManager.default.temporaryDirectory.appendingPathComponent(
                storageNamespace.applicationSupportFolderName,
                isDirectory: true
            )
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
        let timeTrackingController = ProjectTimeTrackingController(
            settingsStore: settingsStore,
            ledgerStore: FileTimeTrackingLedgerStore(
                fileURL: applicationSupportDirectory.appendingPathComponent("time-tracking-ledger.json")
            )
        )
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
        _snapshotStore = StateObject(wrappedValue: DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies, analytics: analytics))
        _locationStore = StateObject(wrappedValue: CurrentLocationStore())
        _launchAtLoginController = StateObject(wrappedValue: launchAtLoginController)
        _timeTrackingController = StateObject(wrappedValue: timeTrackingController)
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
                timeTrackingController: timeTrackingController,
                settingsNavigationController: settingsNavigationController,
                updatesEnabled: UpdateFeatureConfiguration.isEnabled,
                analytics: analytics
            )
            .modifier(SceneAppearanceSync(settingsStore: settingsStore))
        } label: {
            MenuBarStatusLabel(snapshot: snapshotStore.snapshot)
        }
        .menuBarExtraStyle(.window)
        .commands {
            if AppRuntimeInfo.isDebugBuild {
                CommandGroup(replacing: .saveItem) {
                    Button("Save Screenshot") {
                        DebugScreenshotService.shared.saveFrontmostVisibleWindowScreenshot()
                    }
                    .keyboardShortcut("s", modifiers: [.command])
                }
            }
        }

        Window("Settings", id: "settings") {
            SettingsView(
                settingsStore: settingsStore,
                snapshotStore: snapshotStore,
                locationStore: locationStore,
                launchAtLoginController: launchAtLoginController,
                timeTrackingController: timeTrackingController,
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

        Window("Time Tracking", id: "time-tracking") {
            TimeTrackingWindowView(
                settingsStore: settingsStore,
                controller: timeTrackingController
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
            .overlay {
                // Keep window chrome on the macOS system appearance. Only the scene content
                // gets the app-selected appearance override so MenuBarExtra/titlebar controls
                // continue rendering with the native toolbar theme.
                ContentAppearanceBridge(appearance: settingsStore.settings.appearanceMode.appKitAppearance)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
            }
    }
}
