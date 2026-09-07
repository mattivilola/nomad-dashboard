import AppKit
import Combine
import NomadCore

/// App-owned collection keeps working when the menu is closed. Views only report visibility.
@MainActor
final class NomadRuntimeCoordinator: ObservableObject {
    let life: NomadLifeController
    let notifications: UserNotificationCenterNomadLifeDelivery
    private let snapshotStore: DashboardSnapshotStore
    private let locationStore: CurrentLocationStore
    private let settingsStore: AppSettingsStore
    private let timeTracking: ProjectTimeTrackingController
    private var observations: Set<AnyCancellable> = []
    private var visibleSurfaces: Set<String> = []
    private var locationTask: Task<Void, Never>?
    private var locationRefreshTask: Task<Void, Never>?

    init(
        snapshotStore: DashboardSnapshotStore,
        locationStore: CurrentLocationStore,
        settingsStore: AppSettingsStore,
        timeTracking: ProjectTimeTrackingController,
        life: NomadLifeController
    ) {
        self.snapshotStore = snapshotStore
        self.locationStore = locationStore
        self.settingsStore = settingsStore
        self.timeTracking = timeTracking
        self.life = life
        notifications = UserNotificationCenterNomadLifeDelivery()
        timeTracking.setInterfaceActive(false)
        snapshotStore.setDashboardInterfaceActive(false)
        snapshotStore.setAutomaticPlaceCollectionEnabled(life.preferences.isAutomaticCollectionEnabled)
        snapshotStore.$snapshot.sink { [weak self] snapshot in
            guard let self else { return }
            life.ingest(snapshot: snapshot, allowsVenueLookup: !snapshotStore.resourcePolicy.reducesBackgroundWork && !snapshotStore.resourcePolicy.isOffline)
            notifications.deliver(life.consumeAlerts())
        }.store(in: &observations)
        life.$preferences.dropFirst().removeDuplicates().sink { [weak self] preferences in
            guard let self else { return }
            snapshotStore.setAutomaticPlaceCollectionEnabled(preferences.isAutomaticCollectionEnabled)
            if preferences.areQuietAlertsEnabled {
                notifications.requestPermission()
            }
            refreshLocationIfAuthorized()
        }.store(in: &observations)
        locationStore.$currentLocation.removeDuplicates().sink { [weak self] location in
            guard let self else { return }
            snapshotStore.setCurrentLocation(location)
            locationRefreshTask?.cancel()
            guard location != nil else { return }
            locationRefreshTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                await self?.snapshotStore.refresh()
            }
        }.store(in: &observations)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification).sink { [weak self] _ in
            Task { @MainActor in await self?.prepareForSleepOrQuit() }
        }.store(in: &observations)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification).sink { [weak self] _ in
            Task { @MainActor in self?.snapshotStore.start()
                self?.refreshLocationIfAuthorized()
            }
        }.store(in: &observations)
        snapshotStore.start()
        refreshLocationIfAuthorized()
        locationTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(600)) } catch { return }
                self?.refreshLocationIfAuthorized()
            }
        }
    }

    deinit { locationTask?.cancel()
        locationRefreshTask?.cancel()
    }

    func setVisible(_ visible: Bool, surface: String) {
        if visible {
            visibleSurfaces.insert(surface)
        } else {
            visibleSurfaces.remove(surface)
        }
        snapshotStore.setDashboardInterfaceActive(visibleSurfaces.contains("dashboard"))
        timeTracking.setInterfaceActive(!visibleSurfaces.isDisjoint(with: ["dashboard", "time-tracking"]))
    }

    func quitApplication() {
        Task { @MainActor in
            await prepareForSleepOrQuit()
            NSApp.terminate(nil)
        }
    }

    private func prepareForSleepOrQuit() async {
        locationRefreshTask?.cancel()
        await snapshotStore.flushPersistence()
        await life.flush()
        snapshotStore.stop()
    }

    private func refreshLocationIfAuthorized() {
        guard settingsStore.settings.usesDeviceLocation || life.preferences.isAutomaticCollectionEnabled,
              locationStore.authorizationStatus.isNomadWeatherAuthorized,
              !locationStore.isRequestInProgress else { return }
        locationStore.refreshLocation()
    }
}
