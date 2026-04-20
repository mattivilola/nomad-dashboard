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
    private static let fuelLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "NomadDashboard",
        category: "FuelPrices"
    )

    @Published public private(set) var snapshot: DashboardSnapshot
    @Published public private(set) var visitedPlaces: [VisitedPlace] = []
    @Published public private(set) var visitedCountryDays: [VisitedCountryDay] = []
    @Published public private(set) var refreshActivity: DashboardRefreshActivity = .idle

    public let settingsStore: AppSettingsStore

    private let dependencies: DashboardDependencies
    private let analytics: AppAnalytics?
    private var refreshTask: Task<Void, Never>?
    private var settingsObservation: AnyCancellable?
    private var appliedSettings: AppSettings
    private var currentLocation: CLLocation?
    private var currentCoordinate: CLLocationCoordinate2D?
    private var pendingVisitedDeviceLocation: CLLocation?
    private var lastSlowRefresh: Date?
    private var refreshInFlight = false
    private var pendingAutomaticRefresh = false
    private var pendingManualRefresh = false

    public init(
        settingsStore: AppSettingsStore,
        dependencies: DashboardDependencies,
        initialSnapshot: DashboardSnapshot = .placeholder,
        analytics: AppAnalytics? = nil
    ) {
        self.settingsStore = settingsStore
        self.dependencies = dependencies
        self.analytics = analytics
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

    public var visitedCountryDayYears: [Int] {
        visitedCountryDays.availableYears
    }

    public func visitedCountryDaySummary(for year: Int) -> VisitedCountryDayYearSummary? {
        visitedCountryDays.yearSummary(for: year)
    }

    public func clearVisitedPlaces() {
        Task { [weak self] in
            guard let self else {
                return
            }

            try? await dependencies.visitedPlacesStore.reset()
            try? await dependencies.visitedCountryDaysStore.reset()
            await loadVisitedPlaces()
            await loadVisitedCountryDays()
        }
    }

    public func checkForUpdates() {
        Task {
            await dependencies.updateCoordinator.checkForUpdates()
            await refresh(manual: true)
        }
    }

    public func refresh(manual: Bool = false) async {
        if refreshInFlight {
            if manual {
                pendingManualRefresh = true
                pendingAutomaticRefresh = false
                refreshActivity = .manualInProgress
            } else if pendingManualRefresh == false {
                pendingAutomaticRefresh = true
            }
            return
        }

        refreshInFlight = true
        var nextRefreshIsManual = manual

        while true {
            let now = Date()
            let settings = settingsStore.settings
            let includeSlowMetrics = nextRefreshIsManual || shouldRefreshSlowMetrics(now: now, interval: settings.slowRefreshIntervalSeconds)
            refreshActivity = refreshActivity(forManual: nextRefreshIsManual, includeSlowMetrics: includeSlowMetrics)

            await performRefresh(
                manual: nextRefreshIsManual,
                now: now,
                settings: settings,
                includeSlowMetrics: includeSlowMetrics
            )

            if nextRefreshIsManual == false, includeSlowMetrics {
                analytics?.recordBackgroundActiveDay()
            }

            if pendingManualRefresh {
                pendingManualRefresh = false
                pendingAutomaticRefresh = false
                nextRefreshIsManual = true
                continue
            }

            if pendingAutomaticRefresh {
                pendingAutomaticRefresh = false
                nextRefreshIsManual = false
                continue
            }

            break
        }

        refreshInFlight = false
        refreshActivity = .idle
    }

    private func performRefresh(
        manual: Bool,
        now: Date,
        settings: AppSettings,
        includeSlowMetrics: Bool
    ) async {
        let surfSpotConfiguration = settings.surfSpotConfiguration
        var issues: [DashboardIssue] = []

        if surfSpotConfiguration.isConfigured == false {
            issues.append(.marineSpotNotConfigured)
        } else if surfSpotConfiguration.isValid == false {
            issues.append(.marineSpotInvalid)
        }

        let throughputSample = await dependencies.throughputMonitor.currentSample()
        let connectivitySnapshot = await dependencies.connectivityMonitor.currentSnapshot()

        if let throughputSample {
            await appendHistory(from: throughputSample)
        }

        var latencySample = snapshot.network.latency
        var powerSnapshot = snapshot.power.snapshot
        var wifiSnapshot = snapshot.travelContext.wifi
        var vpnSnapshot = snapshot.travelContext.vpn
        var deviceLocationSnapshot = snapshot.travelContext.deviceLocation
        var publicIPSnapshot = snapshot.travelContext.publicIP
        var locationSnapshot = snapshot.travelContext.location
        var travelAlertsSnapshot = synchronizedTravelAlertsSnapshot(
            previous: snapshot.travelAlerts,
            settings: settings,
            locationSnapshot: locationSnapshot
        )
        var weatherSnapshot = snapshot.weather
        var localInfoSnapshot = snapshot.localInfo
        var fuelPricesSnapshot = snapshot.fuelPrices
        var fuelDiagnosticsSnapshot = snapshot.fuelDiagnostics
        var emergencyCareSnapshot = snapshot.emergencyCare
        var marineSnapshot = surfSpotConfiguration.isValid ? snapshot.marine : nil
        var didUpdateVisitedHistory = false

        if includeSlowMetrics {
            latencySample = await dependencies.latencyProbe.currentSample()
            powerSnapshot = await dependencies.powerMonitor.currentSnapshot()
            wifiSnapshot = await dependencies.wifiMonitor.currentSnapshot()
            vpnSnapshot = await dependencies.vpnStatusProvider.currentStatus()

            if settings.usesDeviceLocation, let currentLocation {
                do {
                    deviceLocationSnapshot = try await makeDeviceLocationSnapshot(from: currentLocation, now: now)
                } catch {}
            } else {
                deviceLocationSnapshot = nil
            }

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

            if settings.localInfoEnabled {
                localInfoSnapshot = await refreshLocalInfo(
                    manual: manual,
                    ipLocationSnapshot: locationSnapshot
                )
            } else {
                localInfoSnapshot = nil
            }

            if settings.fuelPricesEnabled {
                let fuelRefresh = await refreshFuelPrices(manual: manual)
                fuelPricesSnapshot = fuelRefresh.snapshot
                fuelDiagnosticsSnapshot = fuelRefresh.diagnostics
            } else {
                fuelPricesSnapshot = nil
            }

            if settings.emergencyCareEnabled {
                emergencyCareSnapshot = await refreshEmergencyCare(manual: manual)
            } else {
                emergencyCareSnapshot = nil
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
                    didUpdateVisitedHistory = await recordVisitedPlace(from: locationSnapshot, visitedAt: now) || didUpdateVisitedHistory
                }

                didUpdateVisitedHistory = await recordPendingDeviceLocation(visitedAt: now) || didUpdateVisitedHistory
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

        if didUpdateVisitedHistory {
            await loadVisitedPlaces()
            await loadVisitedCountryDays()
        }

        let history = await (try? dependencies.historyStore.loadAll()) ?? [:]
        let projectedHistory = projectedDashboardHistory(history)
        let updateState = await dependencies.updateCoordinator.currentState()
        let timeZoneIdentifier = deviceLocationSnapshot?.timeZone
            ?? locationSnapshot?.timeZone
            ?? TimeZone.current.identifier

        snapshot = DashboardSnapshot(
            network: NetworkSectionSnapshot(
                throughput: throughputSample ?? snapshot.network.throughput,
                connectivity: connectivitySnapshot,
                latency: latencySample,
                downloadHistory: projectedHistory[.downloadMbps] ?? snapshot.network.downloadHistory,
                uploadHistory: projectedHistory[.uploadMbps] ?? snapshot.network.uploadHistory,
                latencyHistory: projectedHistory[.latencyMilliseconds] ?? snapshot.network.latencyHistory
            ),
            power: PowerSectionSnapshot(
                snapshot: powerSnapshot,
                chargeHistory: projectedHistory[.batteryChargePercent] ?? snapshot.power.chargeHistory,
                dischargeHistory: projectedHistory[.batteryDischargeWatts] ?? snapshot.power.dischargeHistory
            ),
            travelContext: TravelContextSnapshot(
                wifi: wifiSnapshot,
                vpn: vpnSnapshot,
                timeZoneIdentifier: timeZoneIdentifier,
                deviceLocation: deviceLocationSnapshot,
                publicIP: publicIPSnapshot,
                location: locationSnapshot
            ),
            travelAlerts: travelAlertsSnapshot,
            weather: weatherSnapshot,
            localInfo: localInfoSnapshot,
            fuelPrices: fuelPricesSnapshot,
            fuelDiagnostics: fuelDiagnosticsSnapshot,
            emergencyCare: emergencyCareSnapshot,
            marine: marineSnapshot,
            appState: AppStatusSnapshot(
                lastRefresh: now,
                updateState: updateState,
                issues: issues
            )
        )
    }

    private func refreshActivity(forManual manual: Bool, includeSlowMetrics: Bool) -> DashboardRefreshActivity {
        if manual {
            return .manualInProgress
        }

        if includeSlowMetrics {
            return .slowAutomaticInProgress
        }

        return .idle
    }

    private func shouldRefreshSlowMetrics(now: Date, interval: TimeInterval) -> Bool {
        guard let lastSlowRefresh else {
            return true
        }

        return now.timeIntervalSince(lastSlowRefresh) >= interval
    }

    private func projectedDashboardHistory(_ history: [MetricSeriesKind: [MetricPoint]]) -> [MetricSeriesKind: [MetricPoint]] {
        history.mapValues { projectedMetricHistory($0, maxPoints: dashboardChartPointLimit) }
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
        await loadVisitedCountryDays()
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

        if previousSettings.localInfoEnabled != newSettings.localInfoEnabled {
            needsManualRefresh = true
        }

        if previousSettings.fuelPricesEnabled != newSettings.fuelPricesEnabled {
            needsManualRefresh = true
        }

        if previousSettings.emergencyCareEnabled != newSettings.emergencyCareEnabled {
            needsManualRefresh = true
        }

        if previousSettings.tankerkonigAPIKey != newSettings.tankerkonigAPIKey {
            if let configurableFuelProvider = dependencies.fuelPriceProvider as? FuelPriceProviderConfigurationUpdating {
                await configurableFuelProvider.setTankerkonigAPIKey(
                    AppRuntimeConfiguration.resolveTankerkonigAPIKey(userSetting: newSettings.tankerkonigAPIKey)
                )
            }
            needsManualRefresh = true
        }

        if previousSettings.hudUserAPIToken != newSettings.hudUserAPIToken {
            if let configurableLocalInfoProvider = dependencies.localInfoProvider as? LocalPriceLevelProviderConfigurationUpdating {
                await configurableLocalInfoProvider.setHUDUserAPIToken(
                    AppRuntimeConfiguration.resolveHUDUserAPIToken(userSetting: newSettings.hudUserAPIToken)
                )
            }
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

    private func refreshLocalInfo(
        manual: Bool,
        ipLocationSnapshot: IPLocationSnapshot?
    ) async -> LocalInfoSnapshot {
        var resolvedCountryCode = normalizedValue(ipLocationSnapshot?.countryCode)?.uppercased()
        var resolvedCountryName = normalizedValue(ipLocationSnapshot?.country)
        var locality = normalizedValue(ipLocationSnapshot?.city)
        var administrativeRegion = normalizedValue(ipLocationSnapshot?.region)
        var timeZoneIdentifier = normalizedValue(ipLocationSnapshot?.timeZone)

        if let currentLocation {
            do {
                let reverseGeocodedLocation = try await dependencies.reverseGeocodingProvider.details(for: currentLocation)
                resolvedCountryCode = normalizedValue(reverseGeocodedLocation.countryCode)?.uppercased()
                resolvedCountryName = normalizedValue(reverseGeocodedLocation.country)
                locality = normalizedValue(reverseGeocodedLocation.city) ?? locality
                administrativeRegion = normalizedValue(reverseGeocodedLocation.region) ?? administrativeRegion
                timeZoneIdentifier = normalizedValue(reverseGeocodedLocation.timeZoneIdentifier) ?? timeZoneIdentifier
            } catch {
                // Keep the IP-derived country fallback when reverse geocoding is unavailable.
            }
        }

        guard let countryCode = resolvedCountryCode else {
            return LocalInfoSnapshot(
                status: .locationRequired,
                locality: locality,
                administrativeRegion: administrativeRegion,
                countryCode: nil,
                countryName: nil,
                timeZoneIdentifier: timeZoneIdentifier,
                subdivisionCode: nil,
                publicHolidayStatus: LocalHolidayStatus(
                    state: .unavailable,
                    currentPeriod: nil,
                    nextPeriod: nil,
                    note: "Allow current location or external IP location to look up local holiday information."
                ),
                schoolHolidayStatus: nil,
                localPriceLevel: nil,
                sources: [],
                fetchedAt: nil,
                detail: "Allow current location or external IP location to estimate local info.",
                note: nil
            )
        }

        let request = LocalInfoRequest(
            coordinate: currentLocation?.coordinate,
            countryCode: countryCode,
            countryName: resolvedCountryName,
            locality: locality,
            administrativeRegion: administrativeRegion,
            timeZoneIdentifier: timeZoneIdentifier
        )

        do {
            return try await dependencies.localInfoProvider.info(
                for: request,
                forceRefresh: manual
            )
        } catch {
            return LocalInfoSnapshot(
                status: .unavailable,
                locality: locality,
                administrativeRegion: administrativeRegion,
                countryCode: countryCode,
                countryName: resolvedCountryName,
                timeZoneIdentifier: timeZoneIdentifier,
                subdivisionCode: nil,
                publicHolidayStatus: LocalHolidayStatus(
                    state: .unavailable,
                    currentPeriod: nil,
                    nextPeriod: nil,
                    note: "Local holiday calendar is unavailable right now."
                ),
                schoolHolidayStatus: nil,
                localPriceLevel: nil,
                sources: [],
                fetchedAt: Date(),
                detail: "Local info is unavailable right now.",
                note: nil
            )
        }
    }

    private func refreshFuelPrices(manual: Bool) async -> (snapshot: FuelPriceSnapshot, diagnostics: FuelDiagnosticsSnapshot) {
        let radiusKilometers = 50.0
        let currentCoordinate = currentLocation?.coordinate
        let existingSourceName = snapshot.fuelPrices?.sourceName ?? "Nomad Fuel Prices"
        let existingSourceURL = snapshot.fuelPrices?.sourceURL
        var resolvedCountryCode: String?
        var resolvedCountryName: String?

        guard let currentLocation else {
            let fuelSnapshot = FuelPriceSnapshot(
                status: .locationRequired,
                sourceName: existingSourceName,
                sourceURL: nil,
                countryCode: nil,
                countryName: nil,
                searchRadiusKilometers: radiusKilometers,
                diesel: nil,
                gasoline: nil,
                fetchedAt: nil,
                detail: "Allow current location to look up nearby fuel prices.",
                note: nil
            )
            let diagnostics = FuelDiagnosticsSnapshot(
                status: .locationRequired,
                stage: .locationMissing,
                countryCode: nil,
                countryName: nil,
                latitude: currentCoordinate?.latitude,
                longitude: currentCoordinate?.longitude,
                searchRadiusKilometers: radiusKilometers,
                providerName: existingSourceName,
                sourceURL: existingSourceURL,
                startedAt: nil,
                finishedAt: Date(),
                elapsedMilliseconds: nil,
                summary: "Fuel lookup skipped because current location is unavailable.",
                error: nil
            )
            Self.fuelLogger.info("Fuel fetch skipped because current location is unavailable.")
            return (fuelSnapshot, diagnostics)
        }

        do {
            let reverseGeocodedLocation = try await dependencies.reverseGeocodingProvider.details(for: currentLocation)
            resolvedCountryName = reverseGeocodedLocation.country
            guard let countryCode = normalizedValue(reverseGeocodedLocation.countryCode)?.uppercased() else {
                let fuelSnapshot = FuelPriceSnapshot(
                    status: .unavailable,
                    sourceName: "Apple Reverse Geocoder",
                    sourceURL: nil,
                    countryCode: nil,
                    countryName: reverseGeocodedLocation.country,
                    searchRadiusKilometers: radiusKilometers,
                    diesel: nil,
                    gasoline: nil,
                    fetchedAt: Date(),
                    detail: "Current location country could not be resolved.",
                    note: nil
                )
                let diagnostics = FuelDiagnosticsSnapshot(
                    status: .unavailable,
                    stage: .reverseGeocoding,
                    countryCode: nil,
                    countryName: reverseGeocodedLocation.country,
                    latitude: currentLocation.coordinate.latitude,
                    longitude: currentLocation.coordinate.longitude,
                    searchRadiusKilometers: radiusKilometers,
                    providerName: "Apple Reverse Geocoder",
                    sourceURL: nil,
                    startedAt: nil,
                    finishedAt: fuelSnapshot.fetchedAt,
                    elapsedMilliseconds: nil,
                    summary: "Current location country could not be resolved.",
                    error: nil
                )
                Self.fuelLogger.error("Fuel fetch reverse geocoding resolved no country code for lat=\(currentLocation.coordinate.latitude, privacy: .public) lon=\(currentLocation.coordinate.longitude, privacy: .public)")
                return (fuelSnapshot, diagnostics)
            }
            resolvedCountryCode = countryCode

            let request = FuelSearchRequest(
                coordinate: currentLocation.coordinate,
                countryCode: countryCode,
                countryName: reverseGeocodedLocation.country,
                searchRadiusKilometers: radiusKilometers
            )
            Self.fuelLogger.info(
                "Fuel fetch start providerCountry=\(countryCode, privacy: .public) lat=\(request.coordinate.latitude, privacy: .public) lon=\(request.coordinate.longitude, privacy: .public) radiusKm=\(radiusKilometers, privacy: .public)"
            )

            let fuelSnapshot = try await dependencies.fuelPriceProvider.prices(
                for: request,
                forceRefresh: manual
            )
            let providerDiagnosticsProvider = dependencies.fuelPriceProvider as? FuelPriceDiagnosticsProviding
            let providerDiagnostics: FuelProviderRequestDiagnostics? = if let providerDiagnosticsProvider {
                await providerDiagnosticsProvider.latestRequestDiagnostics()
            } else {
                nil
            }
            let diagnostics = makeFuelDiagnostics(
                snapshot: fuelSnapshot,
                request: request,
                providerDiagnostics: providerDiagnostics
            )
            logFuelSuccess(snapshot: fuelSnapshot, diagnostics: diagnostics)
            return (fuelSnapshot, diagnostics)
        } catch let error as FuelPriceProviderError {
            let note = error.diagnosticSummary == "The operation could not be completed. (NomadCore.ProviderError error 0.)" ? nil : error.diagnosticSummary
            let fuelSnapshot = FuelPriceSnapshot(
                status: .unavailable,
                sourceName: error.sourceName,
                sourceURL: error.sourceURL,
                countryCode: nil,
                countryName: nil,
                searchRadiusKilometers: radiusKilometers,
                diesel: nil,
                gasoline: nil,
                fetchedAt: Date(),
                detail: "Nearby fuel prices are unavailable right now.",
                note: note
            )
            let providerDiagnosticsProvider = dependencies.fuelPriceProvider as? FuelPriceDiagnosticsProviding
            let providerDiagnostics: FuelProviderRequestDiagnostics? = if let providerDiagnosticsProvider {
                await providerDiagnosticsProvider.latestRequestDiagnostics()
            } else {
                nil
            }
            let diagnostics = FuelDiagnosticsSnapshot(
                status: .unavailable,
                stage: error.stage,
                countryCode: resolvedCountryCode,
                countryName: resolvedCountryName,
                latitude: currentLocation.coordinate.latitude,
                longitude: currentLocation.coordinate.longitude,
                searchRadiusKilometers: radiusKilometers,
                providerName: error.sourceName,
                sourceURL: error.sourceURL,
                startedAt: providerDiagnostics?.startedAt,
                finishedAt: providerDiagnostics?.finishedAt ?? Date(),
                elapsedMilliseconds: providerDiagnostics?.elapsedMilliseconds,
                summary: error.diagnosticSummary,
                error: error.details
            )
            logFuelFailure(error: error, diagnostics: diagnostics)
            return (fuelSnapshot, diagnostics)
        } catch {
            let diagnosticsError = makeDiagnosticsError(
                from: error,
                fallbackURL: nil,
                summary: "Fuel price request failed before the provider completed."
            )
            let fuelSnapshot = FuelPriceSnapshot(
                status: .unavailable,
                sourceName: snapshot.fuelPrices?.sourceName ?? "Nomad Fuel Prices",
                sourceURL: snapshot.fuelPrices?.sourceURL,
                countryCode: nil,
                countryName: nil,
                searchRadiusKilometers: radiusKilometers,
                diesel: nil,
                gasoline: nil,
                fetchedAt: Date(),
                detail: "Nearby fuel prices are unavailable right now.",
                note: diagnosticsError.preferredSummary
            )
            let diagnostics = FuelDiagnosticsSnapshot(
                status: .unavailable,
                stage: .reverseGeocoding,
                countryCode: resolvedCountryCode,
                countryName: resolvedCountryName,
                latitude: currentLocation.coordinate.latitude,
                longitude: currentLocation.coordinate.longitude,
                searchRadiusKilometers: radiusKilometers,
                providerName: fuelSnapshot.sourceName,
                sourceURL: fuelSnapshot.sourceURL,
                startedAt: nil,
                finishedAt: Date(),
                elapsedMilliseconds: nil,
                summary: diagnosticsError.preferredSummary,
                error: diagnosticsError
            )
            Self.fuelLogger.error("Fuel fetch failed before provider request: \(diagnosticsError.preferredSummary, privacy: .public)")
            return (fuelSnapshot, diagnostics)
        }
    }

    private func refreshEmergencyCare(manual: Bool) async -> EmergencyCareSnapshot {
        let radiusKilometers = 25.0

        guard let currentLocation else {
            return EmergencyCareSnapshot(
                status: .locationRequired,
                sourceName: "Apple Maps",
                sourceURL: URL(string: "https://maps.apple.com"),
                searchRadiusKilometers: radiusKilometers,
                hospitals: [],
                fetchedAt: nil,
                detail: "Allow current location to look up nearby emergency hospitals."
            )
        }

        do {
            return try await dependencies.emergencyCareProvider.nearbyHospitals(
                for: EmergencyCareSearchRequest(
                    coordinate: currentLocation.coordinate,
                    searchRadiusKilometers: radiusKilometers,
                    maximumResults: 3
                ),
                forceRefresh: manual
            )
        } catch {
            return EmergencyCareSnapshot(
                status: .unavailable,
                sourceName: "Apple Maps",
                sourceURL: URL(string: "https://maps.apple.com"),
                searchRadiusKilometers: radiusKilometers,
                hospitals: [],
                fetchedAt: Date(),
                detail: "Nearby emergency hospitals are unavailable right now."
            )
        }
    }

    private func makeFuelDiagnostics(
        snapshot: FuelPriceSnapshot,
        request: FuelSearchRequest,
        providerDiagnostics: FuelProviderRequestDiagnostics?
    ) -> FuelDiagnosticsSnapshot {
        FuelDiagnosticsSnapshot(
            status: snapshot.status,
            stage: providerDiagnostics?.stage ?? .bestPriceSelection,
            countryCode: snapshot.countryCode ?? request.countryCode,
            countryName: snapshot.countryName ?? request.countryName,
            latitude: request.coordinate.latitude,
            longitude: request.coordinate.longitude,
            searchRadiusKilometers: snapshot.searchRadiusKilometers,
            providerName: providerDiagnostics?.providerName ?? snapshot.sourceName,
            sourceURL: providerDiagnostics?.sourceURL ?? snapshot.sourceURL,
            startedAt: providerDiagnostics?.startedAt,
            finishedAt: providerDiagnostics?.finishedAt ?? snapshot.fetchedAt,
            elapsedMilliseconds: providerDiagnostics?.elapsedMilliseconds,
            summary: providerDiagnostics?.summary ?? snapshot.detail ?? "Fuel price lookup completed.",
            error: providerDiagnostics?.error
        )
    }

    private func logFuelSuccess(snapshot: FuelPriceSnapshot, diagnostics: FuelDiagnosticsSnapshot) {
        let diesel = snapshot.diesel.map {
            "\($0.stationName) \(String(format: "%.3f", $0.pricePerLiter)) \($0.currencyCode)/L \(String(format: "%.1f", $0.distanceKilometers))km"
        } ?? "n/a"
        let gasoline = snapshot.gasoline.map {
            "\($0.stationName) \(String(format: "%.3f", $0.pricePerLiter)) \($0.currencyCode)/L \(String(format: "%.1f", $0.distanceKilometers))km"
        } ?? "n/a"
        Self.fuelLogger.info(
            "Fuel fetch success status=\(snapshot.status.rawValue, privacy: .public) provider=\(snapshot.sourceName, privacy: .public) country=\(snapshot.countryCode ?? "n/a", privacy: .public) diesel=\(diesel, privacy: .public) gasoline=\(gasoline, privacy: .public) elapsedMs=\(diagnostics.elapsedMilliseconds ?? -1, privacy: .public)"
        )
    }

    private func logFuelFailure(error: FuelPriceProviderError, diagnostics: FuelDiagnosticsSnapshot) {
        Self.fuelLogger.error(
            "Fuel fetch failed provider=\(error.sourceName, privacy: .public) stage=\(diagnostics.stage.rawValue, privacy: .public) kind=\(error.failureKind?.rawValue ?? "unknown", privacy: .public) domain=\(error.underlyingDomain ?? "n/a", privacy: .public) code=\(error.underlyingCode ?? -1, privacy: .public) urlError=\(error.urlErrorSymbol ?? "n/a", privacy: .public) failingURL=\(error.failingURL?.absoluteString ?? "n/a", privacy: .public) httpStatus=\(error.httpStatusCode ?? -1, privacy: .public) mime=\(error.responseMIMEType ?? "n/a", privacy: .public) bytes=\(error.payloadByteCount ?? -1, privacy: .public) summary=\(diagnostics.summary, privacy: .public)"
        )
    }

    private func loadVisitedPlaces() async {
        visitedPlaces = await (try? dependencies.visitedPlacesStore.loadAll()) ?? []
    }

    private func loadVisitedCountryDays() async {
        visitedCountryDays = await (try? dependencies.visitedCountryDaysStore.loadAll()) ?? []
    }

    private func recordVisitedPlace(from snapshot: IPLocationSnapshot, visitedAt: Date) async -> Bool {
        guard let country = normalizedValue(snapshot.country) else {
            return false
        }

        let placeInput = VisitedPlaceInput(
            city: normalizedValue(snapshot.city),
            region: normalizedValue(snapshot.region),
            country: country,
            countryCode: normalizedValue(snapshot.countryCode)?.uppercased(),
            latitude: snapshot.latitude,
            longitude: snapshot.longitude,
            source: .publicIPGeolocation,
            visitedAt: visitedAt
        )
        let dayInput = VisitedCountryDayInput(
            day: VisitedCountryDayStamp(date: visitedAt, calendar: .autoupdatingCurrent),
            country: country,
            countryCode: normalizedValue(snapshot.countryCode)?.uppercased(),
            source: .publicIPGeolocation,
            observedAt: visitedAt
        )

        return await recordVisitedHistory(placeInput: placeInput, dayInput: dayInput)
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

            let placeInput = VisitedPlaceInput(
                city: normalizedValue(details.city),
                region: normalizedValue(details.region),
                country: country,
                countryCode: normalizedValue(details.countryCode)?.uppercased(),
                latitude: pendingVisitedDeviceLocation.coordinate.latitude,
                longitude: pendingVisitedDeviceLocation.coordinate.longitude,
                source: .deviceLocation,
                visitedAt: visitedAt
            )
            let dayInput = VisitedCountryDayInput(
                day: VisitedCountryDayStamp(date: visitedAt, calendar: .autoupdatingCurrent),
                country: country,
                countryCode: normalizedValue(details.countryCode)?.uppercased(),
                source: .deviceLocation,
                observedAt: visitedAt
            )
            return await recordVisitedHistory(placeInput: placeInput, dayInput: dayInput)
        } catch {
            return false
        }
    }

    private func recordVisitedHistory(
        placeInput: VisitedPlaceInput,
        dayInput: VisitedCountryDayInput
    ) async -> Bool {
        var didRecord = false

        do {
            try await dependencies.visitedPlacesStore.record(placeInput)
            didRecord = true
        } catch {}

        do {
            try await dependencies.visitedCountryDaysStore.record(dayInput)
            didRecord = true
        } catch {}

        return didRecord
    }

    private func makeDeviceLocationSnapshot(from location: CLLocation, now: Date) async throws -> IPLocationSnapshot {
        let details = try await dependencies.reverseGeocodingProvider.details(for: location)

        return IPLocationSnapshot(
            city: normalizedValue(details.city),
            region: normalizedValue(details.region),
            country: normalizedValue(details.country),
            countryCode: normalizedValue(details.countryCode)?.uppercased(),
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timeZone: normalizedValue(details.timeZoneIdentifier),
            provider: "Core Location",
            fetchedAt: now
        )
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
        case ReliefWebProviderError.appNameApprovalRequired, ReliefWebProviderError.appNameMissing:
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

public let dashboardChartPointLimit = 120

public func projectedMetricHistory(_ points: [MetricPoint], maxPoints: Int = 120) -> [MetricPoint] {
    guard maxPoints > 1, points.count > maxPoints else {
        return points
    }

    let scale = Double(points.count - 1) / Double(maxPoints - 1)

    return (0..<maxPoints).map { position in
        let index: Int
        if position == maxPoints - 1 {
            index = points.count - 1
        } else {
            index = Int((Double(position) * scale).rounded(.down))
        }

        return points[index]
    }
}
