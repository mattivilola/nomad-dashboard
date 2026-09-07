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
    @StateObject private var lifeController: NomadLifeController
    @StateObject private var runtimeCoordinator: NomadRuntimeCoordinator
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
            hudUserAPIToken: AppRuntimeConfiguration.resolveHUDUserAPIToken(
                userSetting: persistedSettings.hudUserAPIToken
            ),
            tankerkonigAPIKey: AppRuntimeConfiguration.resolveTankerkonigAPIKey(
                userSetting: persistedSettings.tankerkonigAPIKey
            ),
            smartravellerBrowserFetcher: WebKitSmartravellerBrowserFetcher(),
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

        let snapshotStore = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies, analytics: analytics)
        let locationStore = CurrentLocationStore()
        let lifeController = NomadLifeController(storageURL: applicationSupportDirectory.appendingPathComponent("workplace-diary.json"), preferencesKey: "\(storageNamespace.settingsKey).NomadLife")
        _settingsStore = StateObject(wrappedValue: settingsStore)
        _snapshotStore = StateObject(wrappedValue: snapshotStore)
        _locationStore = StateObject(wrappedValue: locationStore)
        _lifeController = StateObject(wrappedValue: lifeController)
        _runtimeCoordinator = StateObject(wrappedValue: NomadRuntimeCoordinator(
            snapshotStore: snapshotStore,
            locationStore: locationStore,
            settingsStore: settingsStore,
            timeTracking: timeTrackingController,
            life: lifeController
        ))
        _launchAtLoginController = StateObject(wrappedValue: launchAtLoginController)
        _timeTrackingController = StateObject(wrappedValue: timeTrackingController)
        _settingsNavigationController = StateObject(wrappedValue: SettingsNavigationController())
        self.analytics = analytics
        analytics.recordAppLaunch()
    }

    var body: some Scene {
        MenuBarExtra {
            DashboardRootView(
                lifeController: lifeController,
                runtimeCoordinator: runtimeCoordinator,
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
            CommandGroup(replacing: .appTermination) {
                Button("Quit \(AppRuntimeInfo.appName)") { runtimeCoordinator.quitApplication() }
                    .keyboardShortcut("q", modifiers: [.command])
            }
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

        Window("Workplace Diary", id: "workplace-diary") {
            WorkplaceDiaryWindow(controller: lifeController, locationStore: locationStore)
                .frame(minWidth: 620, minHeight: 470)
                .modifier(SceneAppearanceSync(settingsStore: settingsStore))
        }
        .defaultSize(width: 740, height: 600)

        Window("Nomad Preferences", id: "nomad-preferences") {
            NomadLifeSettingsWindow(controller: lifeController, notifications: runtimeCoordinator.notifications)
                .modifier(SceneAppearanceSync(settingsStore: settingsStore))
        }
        .defaultSize(width: 600, height: 640)

        Window("Time Tracking", id: "time-tracking") {
            TimeTrackingWindowView(
                settingsStore: settingsStore,
                controller: timeTrackingController
            )
            .onAppear { runtimeCoordinator.setVisible(true, surface: "time-tracking") }
            .onDisappear { runtimeCoordinator.setVisible(false, surface: "time-tracking") }
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
