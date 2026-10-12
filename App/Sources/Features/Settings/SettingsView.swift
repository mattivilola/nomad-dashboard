import NomadCore
import NomadUI
import SwiftUI

/// The Settings window: a sidebar of pages with one grouped form per page.
struct SettingsView: View {
    @ObservedObject var settingsStore: AppSettingsStore
    @ObservedObject var snapshotStore: DashboardSnapshotStore
    @ObservedObject var locationStore: CurrentLocationStore
    @ObservedObject var launchAtLoginController: LaunchAtLoginController
    @ObservedObject var timeTrackingController: ProjectTimeTrackingController
    @ObservedObject var lifeController: NomadLifeController
    @ObservedObject var notifications: UserNotificationCenterNomadLifeDelivery
    @ObservedObject var settingsNavigationController: SettingsNavigationController
    @StateObject private var surfSpotForm: SurfSpotFormModel
    let updatesEnabled: Bool
    let analytics: AppAnalytics

    init(
        settingsStore: AppSettingsStore,
        snapshotStore: DashboardSnapshotStore,
        locationStore: CurrentLocationStore,
        launchAtLoginController: LaunchAtLoginController,
        timeTrackingController: ProjectTimeTrackingController,
        lifeController: NomadLifeController,
        notifications: UserNotificationCenterNomadLifeDelivery,
        settingsNavigationController: SettingsNavigationController,
        updatesEnabled: Bool,
        analytics: AppAnalytics
    ) {
        self.settingsStore = settingsStore
        self.snapshotStore = snapshotStore
        self.locationStore = locationStore
        self.launchAtLoginController = launchAtLoginController
        self.timeTrackingController = timeTrackingController
        self.lifeController = lifeController
        self.notifications = notifications
        self.settingsNavigationController = settingsNavigationController
        self.updatesEnabled = updatesEnabled
        self.analytics = analytics
        _surfSpotForm = StateObject(wrappedValue: SurfSpotFormModel(settingsStore: settingsStore))
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: selectedPageBinding) { page in
                Label(page.title, systemImage: page.symbolName)
                    .tag(page)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 240)
        } detail: {
            pageContent(for: settingsNavigationController.selectedPage)
                .navigationSubtitle(settingsNavigationController.selectedPage.title)
        }
        .toolbar(removing: .sidebarToggle)
        .frame(minWidth: 720, minHeight: 560)
        .onAppear {
            surfSpotForm.syncFromSettings()
            analytics.recordSettingsOpened(analyticsEnabled: settingsStore.settings.shareAnonymousAnalytics)
        }
        .onReceive(locationStore.$currentLocation) { location in
            snapshotStore.setCurrentLocation(location)
            surfSpotForm.fillFromLocationIfAwaiting(location)

            guard settingsStore.settings.usesDeviceLocation else {
                return
            }

            Task {
                await snapshotStore.refresh(manual: true)
            }
        }
    }

    private var selectedPageBinding: Binding<SettingsPage?> {
        Binding(
            get: { settingsNavigationController.selectedPage },
            set: { page in
                if let page {
                    settingsNavigationController.selectedPage = page
                }
            }
        )
    }

    @ViewBuilder
    private func pageContent(for page: SettingsPage) -> some View {
        switch page {
        case .general:
            GeneralSettingsPage(
                settingsStore: settingsStore,
                launchAtLoginController: launchAtLoginController,
                lifeController: lifeController,
                navigationController: settingsNavigationController,
                updatesEnabled: updatesEnabled
            )
        case .weatherAndLocal:
            WeatherLocalSettingsPage(
                settingsStore: settingsStore,
                snapshotStore: snapshotStore,
                locationStore: locationStore,
                navigationController: settingsNavigationController,
                surfSpotForm: surfSpotForm
            )
        case .safety:
            SafetySettingsPage(
                settingsStore: settingsStore,
                snapshotStore: snapshotStore,
                locationStore: locationStore,
                navigationController: settingsNavigationController
            )
        case .stays:
            StaysSettingsPage(
                settingsStore: settingsStore,
                navigationController: settingsNavigationController
            )
        case .connectionAndData:
            ConnectionDataSettingsPage(
                settingsStore: settingsStore,
                snapshotStore: snapshotStore,
                lifeController: lifeController,
                notifications: notifications,
                navigationController: settingsNavigationController
            )
        case .work:
            WorkSettingsPage(
                settingsStore: settingsStore,
                timeTrackingController: timeTrackingController,
                lifeController: lifeController,
                navigationController: settingsNavigationController
            )
        case .privacyAndLocation:
            PrivacyLocationSettingsPage(
                settingsStore: settingsStore,
                snapshotStore: snapshotStore,
                locationStore: locationStore,
                navigationController: settingsNavigationController
            )
        case .advanced:
            AdvancedSettingsPage(
                settingsStore: settingsStore,
                snapshotStore: snapshotStore,
                navigationController: settingsNavigationController,
                updatesEnabled: updatesEnabled
            )
        }
    }
}
