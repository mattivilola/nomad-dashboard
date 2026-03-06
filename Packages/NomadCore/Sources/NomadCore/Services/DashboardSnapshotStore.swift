import Combine
import CoreLocation
import Foundation

@MainActor
public final class DashboardSnapshotStore: ObservableObject {
    @Published public private(set) var snapshot: DashboardSnapshot

    public let settingsStore: AppSettingsStore

    private let dependencies: DashboardDependencies
    private var refreshTask: Task<Void, Never>?
    private var currentCoordinate: CLLocationCoordinate2D?
    private var lastSlowRefresh: Date?

    public init(settingsStore: AppSettingsStore, dependencies: DashboardDependencies, initialSnapshot: DashboardSnapshot = .placeholder) {
        self.settingsStore = settingsStore
        self.dependencies = dependencies
        self.snapshot = initialSnapshot
    }

    deinit {
        refreshTask?.cancel()
    }

    public func start() {
        guard refreshTask == nil else {
            return
        }

        refreshTask = Task { [weak self] in
            guard let self else {
                return
            }

            await self.refresh(manual: true)

            while !Task.isCancelled {
                let interval = self.settingsStore.settings.refreshIntervalSeconds
                try? await Task.sleep(for: .seconds(interval))
                await self.refresh()
            }
        }
    }

    public func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    public func setWeatherCoordinate(_ coordinate: CLLocationCoordinate2D?) {
        currentCoordinate = coordinate
    }

    public func checkForUpdates() {
        Task {
            await dependencies.updateCoordinator.checkForUpdates()
            await refresh(manual: true)
        }
    }

    public func refresh(manual: Bool = false) async {
        let now = Date()
        let settings = settingsStore.settings
        let includeSlowMetrics = manual || shouldRefreshSlowMetrics(now: now, interval: settings.slowRefreshIntervalSeconds)
        var issues: [String] = []

        let throughputSample = await dependencies.throughputMonitor.currentSample()

        if let throughputSample {
            await appendHistory(from: throughputSample)
        }

        var latencySample = snapshot.network.latency
        var powerSnapshot = snapshot.power.snapshot
        var wifiSnapshot = snapshot.travelContext.wifi
        var vpnSnapshot = snapshot.travelContext.vpn
        var publicIPSnapshot = snapshot.travelContext.publicIP
        var locationSnapshot = snapshot.travelContext.location
        var weatherSnapshot = snapshot.weather

        if includeSlowMetrics {
            latencySample = await dependencies.latencyProbe.currentSample()
            powerSnapshot = await dependencies.powerMonitor.currentSnapshot()
            wifiSnapshot = await dependencies.wifiMonitor.currentSnapshot()
            vpnSnapshot = await dependencies.vpnStatusProvider.currentStatus()

            if let latencySample {
                try? await dependencies.historyStore.append(
                    MetricPoint(timestamp: latencySample.collectedAt, value: latencySample.milliseconds),
                    to: .latencyMilliseconds
                )
            }

            if let powerSnapshot {
                await appendHistory(from: powerSnapshot)
            }

            do {
                publicIPSnapshot = try await dependencies.publicIPProvider.currentIP(forceRefresh: manual)
            } catch {
                issues.append("Public IP lookup unavailable")
            }

            if settings.publicIPGeolocationEnabled, let publicIPSnapshot {
                do {
                    locationSnapshot = try await dependencies.publicIPLocationProvider.currentLocation(
                        for: publicIPSnapshot.address,
                        forceRefresh: manual
                    )
                } catch {
                    issues.append("IP location unavailable")
                }
            } else {
                locationSnapshot = nil
            }

            if settings.useCurrentLocationForWeather {
                do {
                    weatherSnapshot = try await dependencies.weatherProvider.weather(for: currentCoordinate)
                } catch {
                    issues.append("Weather unavailable until location is granted")
                }
            } else {
                weatherSnapshot = nil
            }

            lastSlowRefresh = now
        }

        let history = (try? await dependencies.historyStore.loadAll()) ?? [:]
        let updateState = await dependencies.updateCoordinator.currentState()
        let timeZoneIdentifier = locationSnapshot?.timeZone ?? TimeZone.current.identifier

        snapshot = DashboardSnapshot(
            network: NetworkSectionSnapshot(
                throughput: throughputSample ?? snapshot.network.throughput,
                latency: latencySample,
                downloadHistory: history[.downloadMbps] ?? snapshot.network.downloadHistory,
                uploadHistory: history[.uploadMbps] ?? snapshot.network.uploadHistory,
                latencyHistory: history[.latencyMilliseconds] ?? snapshot.network.latencyHistory
            ),
            power: PowerSectionSnapshot(
                snapshot: powerSnapshot,
                chargeHistory: history[.batteryChargePercent] ?? snapshot.power.chargeHistory,
                dischargeHistory: history[.batteryDischargeWatts] ?? snapshot.power.dischargeHistory
            ),
            travelContext: TravelContextSnapshot(
                wifi: wifiSnapshot,
                vpn: vpnSnapshot,
                timeZoneIdentifier: timeZoneIdentifier,
                publicIP: publicIPSnapshot,
                location: locationSnapshot
            ),
            weather: weatherSnapshot,
            appState: AppStatusSnapshot(
                lastRefresh: now,
                updateState: updateState,
                issues: issues
            )
        )
    }

    private func shouldRefreshSlowMetrics(now: Date, interval: TimeInterval) -> Bool {
        guard let lastSlowRefresh else {
            return true
        }

        return now.timeIntervalSince(lastSlowRefresh) >= interval
    }

    private func appendHistory(from throughputSample: NetworkThroughputSample) async {
        try? await dependencies.historyStore.append(
            MetricPoint(
                timestamp: throughputSample.collectedAt,
                value: throughputSample.downloadMegabitsPerSecond
            ),
            to: .downloadMbps
        )
        try? await dependencies.historyStore.append(
            MetricPoint(
                timestamp: throughputSample.collectedAt,
                value: throughputSample.uploadMegabitsPerSecond
            ),
            to: .uploadMbps
        )
    }

    private func appendHistory(from powerSnapshot: PowerSnapshot) async {
        if let chargePercent = powerSnapshot.chargePercent {
            try? await dependencies.historyStore.append(
                MetricPoint(timestamp: powerSnapshot.collectedAt, value: chargePercent * 100),
                to: .batteryChargePercent
            )
        }

        if let dischargeRateWatts = powerSnapshot.dischargeRateWatts {
            try? await dependencies.historyStore.append(
                MetricPoint(timestamp: powerSnapshot.collectedAt, value: dischargeRateWatts),
                to: .batteryDischargeWatts
            )
        }
    }
}

