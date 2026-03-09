import Combine
import CoreLocation
import Foundation
import OSLog

@MainActor
public final class DashboardSnapshotStore: ObservableObject {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "NomadDashboard",
        category: "TravelAlerts"
    )

    @Published public private(set) var snapshot: DashboardSnapshot
    @Published public private(set) var visitedPlaces: [VisitedPlace] = []

    public let settingsStore: AppSettingsStore

    private let dependencies: DashboardDependencies
    private var refreshTask: Task<Void, Never>?
    private var settingsObservation: AnyCancellable?
    private var appliedSettings: AppSettings
    private var currentLocation: CLLocation?
    private var currentCoordinate: CLLocationCoordinate2D?
    private var pendingVisitedDeviceLocation: CLLocation?
    private var lastSlowRefresh: Date?

    public init(settingsStore: AppSettingsStore, dependencies: DashboardDependencies, initialSnapshot: DashboardSnapshot = .placeholder) {
        self.settingsStore = settingsStore
        self.dependencies = dependencies
        snapshot = initialSnapshot
        appliedSettings = settingsStore.settings
        snapshot = snapshot.replacingTravelAlerts(
            synchronizedTravelAlertsSnapshot(
                previous: initialSnapshot.travelAlerts,
                settings: settingsStore.settings,
                locationSnapshot: initialSnapshot.travelContext.location
            )
        )
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

            await refresh(manual: true)

            while !Task.isCancelled {
                let interval = settingsStore.settings.refreshIntervalSeconds
                try? await Task.sleep(for: .seconds(interval))
                await refresh()
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

    public func setCurrentLocation(_ location: CLLocation?) {
        currentLocation = location
        currentCoordinate = location?.coordinate
        pendingVisitedDeviceLocation = location
    }

    public var visitedPlaceSummary: VisitedPlaceSummary {
        visitedPlaces.visitedPlaceSummary
    }

    public func clearVisitedPlaces() {
        Task { [weak self] in
            guard let self else {
                return
            }

            try? await dependencies.visitedPlacesStore.reset()
            await loadVisitedPlaces()
        }
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
        let surfSpotConfiguration = settings.surfSpotConfiguration
        let includeSlowMetrics = manual || shouldRefreshSlowMetrics(now: now, interval: settings.slowRefreshIntervalSeconds)
        var issues: [DashboardIssue] = []

        if surfSpotConfiguration.isConfigured == false {
            issues.append(.marineSpotNotConfigured)
        } else if surfSpotConfiguration.isValid == false {
            issues.append(.marineSpotInvalid)
        }

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
        var travelAlertsSnapshot = synchronizedTravelAlertsSnapshot(
            previous: snapshot.travelAlerts,
            settings: settings,
            locationSnapshot: locationSnapshot
        )
        var weatherSnapshot = snapshot.weather
        var marineSnapshot = surfSpotConfiguration.isValid ? snapshot.marine : nil
        var didUpdateVisitedPlaces = false

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

            if surfSpotConfiguration.isValid,
               let surfSpotName = surfSpotConfiguration.name,
               let coordinate = surfSpotConfiguration.coordinate
            {
                do {
                    marineSnapshot = try await dependencies.marineProvider.marine(
                        for: MarineSpot(name: surfSpotName, coordinate: coordinate)
                    )
                } catch {
                    marineSnapshot = nil
                    issues.append(.marineUnavailable)
                }
            } else {
                marineSnapshot = nil
            }

            if settings.visitedPlacesEnabled {
                if let locationSnapshot {
                    didUpdateVisitedPlaces = await recordVisitedPlace(from: locationSnapshot, visitedAt: now) || didUpdateVisitedPlaces
                }

                didUpdateVisitedPlaces = await recordPendingDeviceLocation(visitedAt: now) || didUpdateVisitedPlaces
            } else {
                pendingVisitedDeviceLocation = nil
            }

            travelAlertsSnapshot = synchronizedTravelAlertsSnapshot(
                previous: travelAlertsSnapshot,
                settings: settings,
                locationSnapshot: locationSnapshot
            )
            travelAlertsSnapshot = await refreshTravelAlerts(
                settings: settings,
                locationSnapshot: locationSnapshot,
                previousSnapshot: travelAlertsSnapshot,
                manual: manual,
                now: now
            )

            lastSlowRefresh = now
        }

        if didUpdateVisitedPlaces {
            await loadVisitedPlaces()
        }

        let history = await (try? dependencies.historyStore.loadAll()) ?? [:]
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
            marine: marineSnapshot,
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

                let previousSettings = appliedSettings
                appliedSettings = newSettings

                Task { [weak self] in
                    await self?.applySettingsChange(from: previousSettings, to: newSettings)
                }
            }
    }

    private func applyInitialSettings() async {
        try? await dependencies.historyStore.setRetentionHours(appliedSettings.historyRetentionHours)
        await dependencies.updateCoordinator.setAutomaticChecksEnabled(appliedSettings.automaticUpdateChecksEnabled)
        await loadVisitedPlaces()
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

        if previousSettings.surfSpotName != newSettings.surfSpotName
            || previousSettings.surfSpotLatitude != newSettings.surfSpotLatitude
            || previousSettings.surfSpotLongitude != newSettings.surfSpotLongitude
        {
            needsManualRefresh = true
        }

        if previousSettings.visitedPlacesEnabled != newSettings.visitedPlacesEnabled {
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

        if previousSettings.travelAlertPreferences != newSettings.travelAlertPreferences {
            snapshot = snapshot.replacingTravelAlerts(
                synchronizedTravelAlertsSnapshot(
                    previous: snapshot.travelAlerts,
                    settings: newSettings,
                    locationSnapshot: snapshot.travelContext.location
                )
            )
        }

        if needsManualRefresh {
            await refresh(manual: true)
        }
    }

    private func loadVisitedPlaces() async {
        visitedPlaces = await (try? dependencies.visitedPlacesStore.loadAll()) ?? []
    }

    private func recordVisitedPlace(from snapshot: IPLocationSnapshot, visitedAt: Date) async -> Bool {
        guard let country = normalizedValue(snapshot.country) else {
            return false
        }

        let input = VisitedPlaceInput(
            city: normalizedValue(snapshot.city),
            region: normalizedValue(snapshot.region),
            country: country,
            countryCode: normalizedValue(snapshot.countryCode)?.uppercased(),
            latitude: snapshot.latitude,
            longitude: snapshot.longitude,
            source: .publicIPGeolocation,
            visitedAt: visitedAt
        )

        do {
            try await dependencies.visitedPlacesStore.record(input)
            return true
        } catch {
            return false
        }
    }

    private func recordPendingDeviceLocation(visitedAt: Date) async -> Bool {
        guard let pendingVisitedDeviceLocation else {
            return false
        }

        self.pendingVisitedDeviceLocation = nil

        do {
            let details = try await dependencies.reverseGeocodingProvider.details(for: pendingVisitedDeviceLocation)
            guard let country = normalizedValue(details.country) else {
                return false
            }

            let input = VisitedPlaceInput(
                city: normalizedValue(details.city),
                region: normalizedValue(details.region),
                country: country,
                countryCode: normalizedValue(details.countryCode)?.uppercased(),
                latitude: pendingVisitedDeviceLocation.coordinate.latitude,
                longitude: pendingVisitedDeviceLocation.coordinate.longitude,
                source: .deviceLocation,
                visitedAt: visitedAt
            )
            try await dependencies.visitedPlacesStore.record(input)
            return true
        } catch {
            return false
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
        previousSnapshot: TravelAlertsSnapshot?,
        manual: Bool,
        now: Date
    ) async -> TravelAlertsSnapshot {
        let preferences = settings.travelAlertPreferences
        let enabledKinds = preferences.enabledKinds
        let primaryCountryCode = locationSnapshot?.countryCode?.uppercased()
        let primaryCountryName = locationSnapshot?.country
        let coverageCountryCodes = coverageCountryCodes(for: primaryCountryCode)
        var states: [TravelAlertSignalState] = []

        guard enabledKinds.isEmpty == false else {
            return TravelAlertsSnapshot(
                enabledKinds: [],
                primaryCountryCode: primaryCountryCode,
                primaryCountryName: primaryCountryName,
                coverageCountryCodes: coverageCountryCodes,
                states: [],
                fetchedAt: nil
            )
        }

        if preferences.advisoryEnabled {
            await states.append(
                refreshAlertState(
                    kind: .advisory,
                    previous: previousSnapshot?.state(for: .advisory),
                    source: dependencies.travelAdvisoryProvider.sourceDescriptor,
                    attemptedAt: now,
                    prerequisiteFailure: primaryCountryCode == nil ? .countryRequired : nil
                ) {
                    guard let primaryCountryCode else {
                        throw ProviderError.missingCountryCode
                    }

                    return try await dependencies.travelAdvisoryProvider.advisory(
                        for: coverageCountryCodes,
                        primaryCountryCode: primaryCountryCode,
                        forceRefresh: manual
                    )
                }
            )
        }

        if preferences.weatherEnabled {
            let weatherAlertCoordinate = currentCoordinate ?? locationSnapshot?.coordinate
            await states.append(
                refreshAlertState(
                    kind: .weather,
                    previous: previousSnapshot?.state(for: .weather),
                    source: dependencies.travelWeatherAlertsProvider.sourceDescriptor,
                    attemptedAt: now,
                    prerequisiteFailure: weatherAlertCoordinate == nil ? .locationRequired : nil
                ) {
                    try await dependencies.travelWeatherAlertsProvider.alerts(
                        for: weatherAlertCoordinate,
                        forceRefresh: manual
                    )
                }
            )
        }

        if preferences.securityEnabled {
            await states.append(
                refreshAlertState(
                    kind: .security,
                    previous: previousSnapshot?.state(for: .security),
                    source: dependencies.regionalSecurityProvider.sourceDescriptor,
                    attemptedAt: now,
                    prerequisiteFailure: primaryCountryCode == nil ? .countryRequired : nil
                ) {
                    guard let primaryCountryCode else {
                        throw ProviderError.missingCountryCode
                    }

                    return try await dependencies.regionalSecurityProvider.security(
                        for: coverageCountryCodes,
                        primaryCountryCode: primaryCountryCode,
                        forceRefresh: manual
                    )
                }
            )
        }

        return TravelAlertsSnapshot(
            enabledKinds: enabledKinds,
            primaryCountryCode: primaryCountryCode,
            primaryCountryName: primaryCountryName,
            coverageCountryCodes: coverageCountryCodes,
            states: states,
            fetchedAt: now
        )
    }

    private func synchronizedTravelAlertsSnapshot(
        previous: TravelAlertsSnapshot?,
        settings: AppSettings,
        locationSnapshot: IPLocationSnapshot?
    ) -> TravelAlertsSnapshot {
        let enabledKinds = settings.travelAlertPreferences.enabledKinds
        let primaryCountryCode = locationSnapshot?.countryCode?.uppercased()
        let primaryCountryName = locationSnapshot?.country
        let coverageCountryCodes = coverageCountryCodes(for: primaryCountryCode)

        return TravelAlertsSnapshot(
            enabledKinds: enabledKinds,
            primaryCountryCode: primaryCountryCode,
            primaryCountryName: primaryCountryName,
            coverageCountryCodes: coverageCountryCodes,
            states: enabledKinds.map { kind in
                previous?.state(for: kind) ?? checkingAlertState(for: kind)
            },
            fetchedAt: enabledKinds.isEmpty ? nil : previous?.fetchedAt
        )
    }

    private func checkingAlertState(for kind: TravelAlertKind) -> TravelAlertSignalState {
        let source = sourceDescriptor(for: kind)
        return TravelAlertSignalState(
            kind: kind,
            status: .checking,
            signal: nil,
            reason: nil,
            sourceName: source.name,
            sourceURL: source.url,
            lastAttemptedAt: nil,
            lastSuccessAt: nil
        )
    }

    private func refreshAlertState(
        kind: TravelAlertKind,
        previous: TravelAlertSignalState?,
        source: TravelAlertSourceDescriptor,
        attemptedAt: Date,
        prerequisiteFailure: TravelAlertUnavailableReason?,
        fetch: () async throws -> TravelAlertSignalSnapshot
    ) async -> TravelAlertSignalState {
        let retainedSourceName = previous?.sourceName ?? source.name
        let retainedSourceURL = previous?.sourceURL ?? source.url

        if let prerequisiteFailure {
            return TravelAlertSignalState(
                kind: kind,
                status: .unavailable,
                signal: nil,
                reason: prerequisiteFailure,
                diagnosticSummary: nil,
                sourceName: retainedSourceName,
                sourceURL: retainedSourceURL,
                lastAttemptedAt: attemptedAt,
                lastSuccessAt: previous?.lastSuccessAt
            )
        }

        do {
            let signal = try await fetch()
            return TravelAlertSignalState(
                kind: kind,
                status: .ready,
                signal: signal,
                reason: nil,
                diagnosticSummary: nil,
                sourceName: signal.sourceName.isEmpty ? retainedSourceName : signal.sourceName,
                sourceURL: signal.sourceURL ?? retainedSourceURL,
                lastAttemptedAt: attemptedAt,
                lastSuccessAt: attemptedAt
            )
        } catch {
            let reason = unavailableReason(for: error)
            let diagnosticSummary = diagnosticSummary(for: error)
            logTravelAlertFailure(
                kind: kind,
                sourceName: retainedSourceName,
                reason: reason,
                diagnosticSummary: diagnosticSummary,
                error: error
            )

            if let previousSignal = previous?.signal {
                return TravelAlertSignalState(
                    kind: kind,
                    status: .stale,
                    signal: previousSignal,
                    reason: reason,
                    diagnosticSummary: diagnosticSummary,
                    sourceName: retainedSourceName,
                    sourceURL: retainedSourceURL,
                    lastAttemptedAt: attemptedAt,
                    lastSuccessAt: previous?.lastSuccessAt
                )
            }

            return TravelAlertSignalState(
                kind: kind,
                status: .unavailable,
                signal: nil,
                reason: reason,
                diagnosticSummary: diagnosticSummary,
                sourceName: retainedSourceName,
                sourceURL: retainedSourceURL,
                lastAttemptedAt: attemptedAt,
                lastSuccessAt: previous?.lastSuccessAt
            )
        }
    }

    private func sourceDescriptor(for kind: TravelAlertKind) -> TravelAlertSourceDescriptor {
        switch kind {
        case .advisory:
            dependencies.travelAdvisoryProvider.sourceDescriptor
        case .weather:
            dependencies.travelWeatherAlertsProvider.sourceDescriptor
        case .security:
            dependencies.regionalSecurityProvider.sourceDescriptor
        }
    }

    private func unavailableReason(for error: Error) -> TravelAlertUnavailableReason {
        switch error {
        case ProviderError.missingCountryCode:
            .countryRequired
        case ProviderError.missingCoordinate:
            .locationRequired
        case ProviderError.missingConfiguration:
            .sourceConfigurationRequired
        default:
            .sourceUnavailable
        }
    }

    private func diagnosticSummary(for error: Error) -> String? {
        switch error {
        case let error as TravelAlertDiagnosticError:
            error.diagnosticSummary
        default:
            nil
        }
    }

    private func logTravelAlertFailure(
        kind: TravelAlertKind,
        sourceName: String,
        reason: TravelAlertUnavailableReason,
        diagnosticSummary: String?,
        error: Error
    ) {
        let summary = diagnosticSummary ?? unavailableSummary(for: reason)
        Self.logger.error(
            "Travel alert fetch failed kind=\(kind.rawValue, privacy: .public) source=\(sourceName, privacy: .public) summary=\(summary, privacy: .public) error=\(String(describing: error), privacy: .public)"
        )
    }

    private func unavailableSummary(for reason: TravelAlertUnavailableReason) -> String {
        switch reason {
        case .countryRequired:
            "Country needed for nearby alerts"
        case .locationRequired:
            "Location needed for local alerts"
        case .sourceUnavailable:
            "Source unavailable"
        case .sourceConfigurationRequired:
            "Source setup required"
        }
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

    private func normalizedValue(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), value.isEmpty == false else {
            return nil
        }

        return value
    }
}
