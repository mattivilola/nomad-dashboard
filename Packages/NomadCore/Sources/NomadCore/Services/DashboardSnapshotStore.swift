import Combine
import CoreLocation
import Foundation

@MainActor
public final class DashboardSnapshotStore: ObservableObject {
    @Published public private(set) var snapshot: DashboardSnapshot

    public let settingsStore: AppSettingsStore

    private let dependencies: DashboardDependencies
    private var refreshTask: Task<Void, Never>?
    private var settingsObservation: AnyCancellable?
    private var appliedSettings: AppSettings
    private var currentCoordinate: CLLocationCoordinate2D?
    private var lastSlowRefresh: Date?

    public init(settingsStore: AppSettingsStore, dependencies: DashboardDependencies, initialSnapshot: DashboardSnapshot = .placeholder) {
        self.settingsStore = settingsStore
        self.dependencies = dependencies
        self.snapshot = initialSnapshot
        self.appliedSettings = settingsStore.settings
        configureSettingsObservation()
        Task { [weak self] in
            await self?.applyInitialSettings()
        }
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
        var issues: [DashboardIssue] = []

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
        var travelAlertsSnapshot = snapshot.travelAlerts
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
                issues.append(.publicIPLookupUnavailable)
            }

            if settings.publicIPGeolocationEnabled, let publicIPSnapshot {
                do {
                    locationSnapshot = try await dependencies.publicIPLocationProvider.currentLocation(
                        for: publicIPSnapshot.address,
                        forceRefresh: manual
                    )
                } catch {
                    issues.append(.ipLocationUnavailable)
                }
            } else {
                locationSnapshot = nil
            }

            if settings.useCurrentLocationForWeather {
                do {
                    weatherSnapshot = try await dependencies.weatherProvider.weather(for: currentCoordinate)
                } catch ProviderError.missingCoordinate {
                    issues.append(.weatherLocationRequired)
                } catch {
                    issues.append(.weatherUnavailable)
                }
            } else {
                weatherSnapshot = nil
            }

            travelAlertsSnapshot = await refreshTravelAlerts(
                settings: settings,
                locationSnapshot: locationSnapshot,
                issues: &issues,
                manual: manual,
                now: now
            )

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
            travelAlerts: travelAlertsSnapshot,
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

    private func configureSettingsObservation() {
        settingsObservation = settingsStore.$settings
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] newSettings in
                guard let self else {
                    return
                }

                let previousSettings = self.appliedSettings
                self.appliedSettings = newSettings

                Task { [weak self] in
                    await self?.applySettingsChange(from: previousSettings, to: newSettings)
                }
            }
    }

    private func applyInitialSettings() async {
        try? await dependencies.historyStore.setRetentionHours(appliedSettings.historyRetentionHours)
        await dependencies.updateCoordinator.setAutomaticChecksEnabled(appliedSettings.automaticUpdateChecksEnabled)
    }

    private func applySettingsChange(from previousSettings: AppSettings, to newSettings: AppSettings) async {
        if previousSettings.automaticUpdateChecksEnabled != newSettings.automaticUpdateChecksEnabled {
            await dependencies.updateCoordinator.setAutomaticChecksEnabled(newSettings.automaticUpdateChecksEnabled)
        }

        var needsManualRefresh = false

        if previousSettings.historyRetentionHours != newSettings.historyRetentionHours {
            try? await dependencies.historyStore.setRetentionHours(newSettings.historyRetentionHours)
            needsManualRefresh = true
        }

        if previousSettings.publicIPGeolocationEnabled != newSettings.publicIPGeolocationEnabled {
            needsManualRefresh = true
        }

        if previousSettings.useCurrentLocationForWeather != newSettings.useCurrentLocationForWeather {
            needsManualRefresh = true
        }

        if previousSettings.travelAdvisoryEnabled != newSettings.travelAdvisoryEnabled {
            needsManualRefresh = true
        }

        if previousSettings.travelWeatherAlertsEnabled != newSettings.travelWeatherAlertsEnabled {
            needsManualRefresh = true
        }

        if previousSettings.regionalSecurityEnabled != newSettings.regionalSecurityEnabled {
            needsManualRefresh = true
        }

        if needsManualRefresh {
            await refresh(manual: true)
        }
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

    private func refreshTravelAlerts(
        settings: AppSettings,
        locationSnapshot: IPLocationSnapshot?,
        issues: inout [DashboardIssue],
        manual: Bool,
        now: Date
    ) async -> TravelAlertsSnapshot {
        let preferences = settings.travelAlertPreferences
        let enabledKinds = preferences.enabledKinds
        let primaryCountryCode = locationSnapshot?.countryCode?.uppercased()
        let primaryCountryName = locationSnapshot?.country
        let coverageCountryCodes = coverageCountryCodes(for: primaryCountryCode)
        var signals: [TravelAlertSignalSnapshot] = []

        if preferences.advisoryEnabled {
            if let primaryCountryCode {
                do {
                    let signal = try await dependencies.travelAdvisoryProvider.advisory(
                        for: coverageCountryCodes,
                        primaryCountryCode: primaryCountryCode,
                        forceRefresh: manual
                    )
                    signals.append(signal)
                } catch {
                    issues.append(.travelAdvisoryUnavailable)
                }
            } else {
                issues.append(.travelAdvisoryCountryRequired)
            }
        }

        if preferences.weatherEnabled {
            let weatherAlertCoordinate = currentCoordinate ?? locationSnapshot?.coordinate

            do {
                let signal = try await dependencies.travelWeatherAlertsProvider.alerts(
                    for: weatherAlertCoordinate,
                    forceRefresh: manual
                )
                signals.append(signal)
            } catch ProviderError.missingCoordinate {
                issues.append(.travelWeatherAlertsLocationRequired)
            } catch {
                issues.append(.travelWeatherAlertsUnavailable)
            }
        }

        if preferences.securityEnabled {
            if let primaryCountryCode {
                do {
                    let signal = try await dependencies.regionalSecurityProvider.security(
                        for: coverageCountryCodes,
                        primaryCountryCode: primaryCountryCode,
                        forceRefresh: manual
                    )
                    signals.append(signal)
                } catch ProviderError.missingConfiguration {
                    issues.append(.regionalSecurityUnavailable)
                } catch {
                    issues.append(.regionalSecurityUnavailable)
                }
            } else {
                issues.append(.regionalSecurityCountryRequired)
            }
        }

        return TravelAlertsSnapshot(
            enabledKinds: enabledKinds,
            primaryCountryCode: primaryCountryCode,
            primaryCountryName: primaryCountryName,
            coverageCountryCodes: coverageCountryCodes,
            signals: signals,
            fetchedAt: enabledKinds.isEmpty ? nil : now
        )
    }

    private func coverageCountryCodes(for primaryCountryCode: String?) -> [String] {
        guard let primaryCountryCode else {
            return []
        }

        return ([primaryCountryCode] + dependencies.neighborCountryResolver.neighboringCountryCodes(for: primaryCountryCode))
            .map { $0.uppercased() }
            .reduce(into: [String]()) { result, countryCode in
                if result.contains(countryCode) == false {
                    result.append(countryCode)
                }
            }
    }
}
