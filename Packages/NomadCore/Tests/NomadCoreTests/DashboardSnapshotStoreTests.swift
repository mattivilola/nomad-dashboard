import CoreLocation
import Foundation
@testable import NomadCore
import Testing

@MainActor
struct DashboardSnapshotStoreTests {
    @Test
    func refreshBuildsSnapshotFromDependencies() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.publicIPGeolocationEnabled = true
        settingsStore.settings.surfSpotName = "Helsinki Beach"
        settingsStore.settings.surfSpotLatitude = 60.1699
        settingsStore.settings.surfSpotLongitude = 24.9384

        let historyStore = InMemoryHistoryStore()
        let dependencies = makeDependencies(historyStore: historyStore)

        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies)
        store.setWeatherCoordinate(CLLocationCoordinate2D(latitude: 60.1699, longitude: 24.9384))

        await store.refresh(manual: true)

        #expect(store.snapshot.travelContext.publicIP?.address == "198.51.100.12")
        #expect(store.snapshot.travelContext.location?.country == "Finland")
        #expect(store.snapshot.weather?.conditionDescription == "Clear")
        #expect(store.snapshot.marine?.spotName == "Helsinki Beach")
        #expect(store.snapshot.network.downloadHistory.isEmpty == false)
        #expect(store.snapshot.healthSummary.overall.level == .ready)
    }

    @Test
    func refreshStoresUniqueVisitedPlaceFromIPAndDeviceLocation() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.publicIPGeolocationEnabled = true
        settingsStore.settings.visitedPlacesEnabled = true

        let dependencies = makeDependencies()
        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies)
        store.setCurrentLocation(CLLocation(latitude: 60.1699, longitude: 24.9384))

        await store.refresh(manual: true)

        #expect(store.visitedPlaces.count == 1)
        #expect(store.visitedPlaces.first?.city == "Helsinki")
        #expect(store.visitedPlaces.first?.countryCode == "FI")
        #expect(Set(store.visitedPlaces.first?.sources ?? []) == Set([.publicIPGeolocation, .deviceLocation]))
        #expect(store.visitedPlaceSummary.citiesVisited == 1)
        #expect(store.visitedPlaceSummary.countriesVisited == 1)
    }

    @Test
    func refreshSkipsVisitedPlaceCaptureWhenHistoryIsDisabled() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.publicIPGeolocationEnabled = true
        settingsStore.settings.visitedPlacesEnabled = false

        let dependencies = makeDependencies()
        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies)
        store.setCurrentLocation(CLLocation(latitude: 60.1699, longitude: 24.9384))

        await store.refresh(manual: true)

        #expect(store.visitedPlaces.isEmpty)
        #expect(store.visitedPlaceSummary.citiesVisited == 0)
        #expect(store.visitedPlaceSummary.countriesVisited == 0)
    }

    @Test
    func refreshSkipsLocationLookupWhenGeolocationIsDisabled() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.publicIPGeolocationEnabled = false
        settingsStore.settings.useCurrentLocationForWeather = false

        let locationProvider = RecordingLocationProvider()
        let dependencies = makeDependencies(
            publicIPLocationProvider: locationProvider,
            historyStore: InMemoryHistoryStore()
        )

        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies)

        await store.refresh(manual: true)

        #expect(store.snapshot.travelContext.publicIP?.address == "198.51.100.12")
        #expect(store.snapshot.travelContext.location == nil)
        #expect(store.snapshot.travelContext.timeZoneIdentifier == TimeZone.current.identifier)
        #expect(await locationProvider.callCount() == 0)
        #expect(store.snapshot.appState.issues.contains(.ipLocationUnavailable) == false)
    }

    @Test
    func refreshKeepsPublicIPWhenLocationLookupFails() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.publicIPGeolocationEnabled = true
        settingsStore.settings.useCurrentLocationForWeather = false

        let dependencies = makeDependencies(
            publicIPLocationProvider: FailingLocationProvider(),
            historyStore: InMemoryHistoryStore()
        )

        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies)

        await store.refresh(manual: true)

        #expect(store.snapshot.travelContext.publicIP?.address == "198.51.100.12")
        #expect(store.snapshot.travelContext.location == nil)
        #expect(store.snapshot.appState.issues.contains(.ipLocationUnavailable))
    }

    @Test
    func refreshMarksWeatherLocationRequirementWhenCoordinateIsMissing() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        let dependencies = makeDependencies(
            weatherProvider: MissingCoordinateWeatherProvider(),
            historyStore: InMemoryHistoryStore()
        )

        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies)

        await store.refresh(manual: true)

        #expect(store.snapshot.weather == nil)
        #expect(store.snapshot.appState.issues.contains(.weatherLocationRequired))
    }

    @Test
    func refreshSkipsMarineLookupWhenSurfSpotIsBlank() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        let marineProvider = RecordingMarineProvider()
        let dependencies = makeDependencies(
            marineProvider: marineProvider,
            historyStore: InMemoryHistoryStore()
        )

        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies)

        await store.refresh(manual: true)

        #expect(store.snapshot.marine == nil)
        #expect(store.snapshot.appState.issues.contains(.marineSpotNotConfigured))
        #expect(await marineProvider.callCount() == 0)
    }

    @Test
    func refreshMarksMarineAsUnavailableWhenProviderFails() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.surfSpotName = "Helsinki Beach"
        settingsStore.settings.surfSpotLatitude = 60.1699
        settingsStore.settings.surfSpotLongitude = 24.9384

        let dependencies = makeDependencies(
            marineProvider: FailingMarineProvider(),
            historyStore: InMemoryHistoryStore()
        )

        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies)

        await store.refresh(manual: true)

        #expect(store.snapshot.weather?.conditionDescription == "Clear")
        #expect(store.snapshot.marine == nil)
        #expect(store.snapshot.appState.issues.contains(.marineUnavailable))
    }

    @Test
    func refreshKeepsMarineWhenWeatherFails() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.surfSpotName = "Helsinki Beach"
        settingsStore.settings.surfSpotLatitude = 60.1699
        settingsStore.settings.surfSpotLongitude = 24.9384

        let dependencies = makeDependencies(
            weatherProvider: MissingCoordinateWeatherProvider(),
            historyStore: InMemoryHistoryStore()
        )

        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies)

        await store.refresh(manual: true)

        #expect(store.snapshot.weather == nil)
        #expect(store.snapshot.marine?.spotName == "Helsinki Beach")
        #expect(store.snapshot.appState.issues.contains(.weatherLocationRequired))
    }

    @Test
    func refreshBuildsTravelAlertsFromEnabledProviders() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.publicIPGeolocationEnabled = true
        settingsStore.settings.travelAdvisoryEnabled = true
        settingsStore.settings.travelWeatherAlertsEnabled = true
        settingsStore.settings.regionalSecurityEnabled = true

        let dependencies = makeDependencies(historyStore: InMemoryHistoryStore())

        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies)
        store.setWeatherCoordinate(CLLocationCoordinate2D(latitude: 60.1699, longitude: 24.9384))

        #expect(store.snapshot.travelAlerts?.state(for: .advisory)?.status == .checking)
        #expect(store.snapshot.travelAlerts?.state(for: .weather)?.status == .checking)
        #expect(store.snapshot.travelAlerts?.state(for: .security)?.status == .checking)

        await store.refresh(manual: true)

        #expect(store.snapshot.travelAlerts?.enabledKinds == [.advisory, .weather, .security])
        #expect(store.snapshot.travelAlerts?.coverageCountryCodes == ["FI", "SE", "NO"])
        #expect(store.snapshot.travelAlerts?.state(for: .advisory)?.status == .ready)
        #expect(store.snapshot.travelAlerts?.state(for: .weather)?.status == .ready)
        #expect(store.snapshot.travelAlerts?.state(for: .security)?.status == .ready)
        #expect(store.snapshot.travelAlerts?.signal(for: .advisory)?.severity == .caution)
        #expect(store.snapshot.travelAlerts?.signal(for: .weather)?.severity == .warning)
        #expect(store.snapshot.travelAlerts?.signal(for: .security)?.severity == .info)
    }

    @Test
    func refreshMarksTravelWeatherAlertsLocationRequirementWhenCoordinateIsMissing() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.publicIPGeolocationEnabled = false
        settingsStore.settings.useCurrentLocationForWeather = false
        settingsStore.settings.travelWeatherAlertsEnabled = true

        let dependencies = makeDependencies(historyStore: InMemoryHistoryStore())

        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies)

        await store.refresh(manual: true)

        #expect(store.snapshot.travelAlerts?.signal(for: .weather) == nil)
        #expect(store.snapshot.travelAlerts?.state(for: .weather)?.status == .unavailable)
        #expect(store.snapshot.travelAlerts?.state(for: .weather)?.reason == .locationRequired)
        #expect(store.snapshot.travelAlerts?.state(for: .weather)?.sourceName == "WeatherKit")
    }

    @Test
    func refreshMarksRegionalSecurityConfigurationRequirementWhenSourceNeedsSetup() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.publicIPGeolocationEnabled = true
        settingsStore.settings.regionalSecurityEnabled = true

        let dependencies = makeDependencies(
            regionalSecurityProvider: MissingConfigurationRegionalSecurityProvider(),
            historyStore: InMemoryHistoryStore()
        )

        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies)

        await store.refresh(manual: true)

        #expect(store.snapshot.travelAlerts?.signal(for: .security) == nil)
        #expect(store.snapshot.travelAlerts?.state(for: .security)?.status == .unavailable)
        #expect(store.snapshot.travelAlerts?.state(for: .security)?.reason == .sourceConfigurationRequired)
        #expect(store.snapshot.travelAlerts?.state(for: .security)?.sourceName == "ReliefWeb")
        #expect(store.snapshot.travelAlerts?.state(for: .security)?.sourceURL == URL(string: "https://reliefweb.int"))
    }

    @Test
    func refreshPersistsRegionalSecurityDiagnosticSummaryWhenSourceReturnsHTTPError() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.publicIPGeolocationEnabled = true
        settingsStore.settings.regionalSecurityEnabled = true

        let dependencies = makeDependencies(
            regionalSecurityProvider: RateLimitedRegionalSecurityProvider(),
            historyStore: InMemoryHistoryStore()
        )

        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies)

        await store.refresh(manual: true)

        let securityState = store.snapshot.travelAlerts?.state(for: .security)
        #expect(securityState?.status == .unavailable)
        #expect(securityState?.reason == .sourceUnavailable)
        #expect(securityState?.diagnosticSummary == "ReliefWeb returned HTTP 429.")
    }

    @Test
    func refreshMarksReliefWebAppNameApprovalAsConfigurationRequirement() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.publicIPGeolocationEnabled = true
        settingsStore.settings.regionalSecurityEnabled = true

        let dependencies = makeDependencies(
            regionalSecurityProvider: UnapprovedAppNameRegionalSecurityProvider(),
            historyStore: InMemoryHistoryStore()
        )

        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies)

        await store.refresh(manual: true)

        let securityState = store.snapshot.travelAlerts?.state(for: .security)
        #expect(securityState?.status == .unavailable)
        #expect(securityState?.reason == .sourceConfigurationRequired)
        #expect(securityState?.diagnosticSummary == "ReliefWeb app name approval required.")
    }

    @Test
    func refreshPreservesLastKnownTravelAlertWhenSourceFailsAfterSuccess() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.publicIPGeolocationEnabled = true
        settingsStore.settings.travelWeatherAlertsEnabled = true

        let travelWeatherAlertsProvider = SequenceTravelWeatherAlertsProvider(
            responses: [
                .success(
                    TravelAlertSignalSnapshot(
                        kind: .weather,
                        severity: .warning,
                        title: "Weather alerts",
                        summary: "2 active weather alerts. Flood warning.",
                        sourceName: "WeatherKit",
                        sourceURL: URL(string: "https://developer.apple.com/weatherkit/"),
                        updatedAt: .now,
                        affectedCountryCodes: ["FI"],
                        itemCount: 2
                    )
                ),
                .failure(.invalidResponse)
            ]
        )

        let dependencies = makeDependencies(
            travelWeatherAlertsProvider: travelWeatherAlertsProvider,
            historyStore: InMemoryHistoryStore()
        )

        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies)
        store.setWeatherCoordinate(CLLocationCoordinate2D(latitude: 60.1699, longitude: 24.9384))

        await store.refresh(manual: true)

        let readyState = store.snapshot.travelAlerts?.state(for: .weather)
        #expect(readyState?.status == .ready)
        #expect(readyState?.signal?.severity == .warning)

        await store.refresh(manual: true)

        let staleState = store.snapshot.travelAlerts?.state(for: .weather)
        #expect(staleState?.status == .stale)
        #expect(staleState?.reason == .sourceUnavailable)
        #expect(staleState?.signal?.summary == "2 active weather alerts. Flood warning.")
        #expect(staleState?.lastSuccessAt != nil)
    }

    @Test
    func fastRefreshPreservesResolvedTravelAlertState() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.publicIPGeolocationEnabled = false
        settingsStore.settings.useCurrentLocationForWeather = false
        settingsStore.settings.travelWeatherAlertsEnabled = true

        let dependencies = makeDependencies(historyStore: InMemoryHistoryStore())

        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies)

        await store.refresh(manual: true)
        let unresolvedState = store.snapshot.travelAlerts?.state(for: .weather)

        await store.refresh(manual: false)

        let preservedState = store.snapshot.travelAlerts?.state(for: .weather)
        #expect(unresolvedState == preservedState)
    }

    @Test
    func settingsChangesRefreshTravelAlertsImmediately() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.publicIPGeolocationEnabled = true
        settingsStore.settings.travelAdvisoryEnabled = false
        let advisoryProvider = RecordingTravelAdvisoryProvider()

        let dependencies = makeDependencies(
            travelAdvisoryProvider: advisoryProvider,
            historyStore: InMemoryHistoryStore()
        )

        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies)
        await store.refresh(manual: true)
        #expect(await advisoryProvider.callCount() == 0)

        settingsStore.settings.travelAdvisoryEnabled = true

        try await waitForSettingsPropagation()
        #expect(await advisoryProvider.callCount() == 1)
        #expect(store.snapshot.travelAlerts?.state(for: .advisory)?.status == .ready)
        _ = store
    }

    @Test
    func settingsChangesRefreshMarineImmediately() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        let marineProvider = RecordingMarineProvider()
        let dependencies = makeDependencies(
            marineProvider: marineProvider,
            historyStore: InMemoryHistoryStore()
        )

        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies)
        await store.refresh(manual: true)
        #expect(await marineProvider.callCount() == 0)

        settingsStore.settings.surfSpotName = "Helsinki Beach"
        settingsStore.settings.surfSpotLatitude = 60.1699
        settingsStore.settings.surfSpotLongitude = 24.9384

        try await waitForSettingsPropagation()
        #expect(await marineProvider.callCount() >= 1)
        #expect(store.snapshot.marine?.spotName == "Helsinki Beach")
    }

    @Test
    func settingsChangesPropagateAutomaticUpdateChecks() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.automaticUpdateChecksEnabled = false
        let updateCoordinator = RecordingUpdateCoordinator()
        let dependencies = makeDependencies(
            historyStore: InMemoryHistoryStore(),
            updateCoordinator: updateCoordinator
        )

        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies)

        try await waitForSettingsPropagation()
        #expect(await updateCoordinator.automaticChecksHistory() == [false])

        settingsStore.settings.automaticUpdateChecksEnabled = true

        try await waitForSettingsPropagation()
        #expect(await updateCoordinator.automaticChecksHistory() == [false, true])
        _ = store
    }

    @Test
    func changingHistoryRetentionPrunesSnapshotHistoryImmediately() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.historyRetentionHours = 24

        let now = Date()
        let seededHistoryStore = InMemoryHistoryStore(
            values: [
                .downloadMbps: [
                    MetricPoint(timestamp: now.addingTimeInterval(-12 * 3_600), value: 18),
                    MetricPoint(timestamp: now.addingTimeInterval(-2 * 3_600), value: 22)
                ]
            ],
            retentionHours: 24
        )

        let dependencies = makeDependencies(
            throughputMonitor: NilThroughputMonitor(),
            historyStore: seededHistoryStore
        )

        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies)

        await store.refresh(manual: true)
        #expect(store.snapshot.network.downloadHistory.count == 2)

        settingsStore.settings.historyRetentionHours = 6

        try await waitForSettingsPropagation()
        #expect(store.snapshot.network.downloadHistory.count == 1)
        #expect(store.snapshot.network.downloadHistory.first?.value == 22)
    }

    private func waitForSettingsPropagation() async throws {
        try await Task.sleep(for: .milliseconds(50))
    }
}

private func makeDependencies(
    throughputMonitor: any ThroughputMonitor = FixedThroughputMonitor(),
    latencyProbe: any LatencyProbe = FixedLatencyProbe(),
    powerMonitor: any PowerMonitor = FixedPowerMonitor(),
    wifiMonitor: any WiFiMonitor = FixedWiFiMonitor(),
    vpnStatusProvider: any VPNStatusProvider = FixedVPNProvider(),
    publicIPProvider: any PublicIPProvider = FixedPublicIPProvider(),
    publicIPLocationProvider: any PublicIPLocationProvider = FixedLocationProvider(),
    reverseGeocodingProvider: any ReverseGeocodingProvider = FixedReverseGeocodingProvider(),
    weatherProvider: any WeatherProvider = FixedWeatherProvider(),
    marineProvider: any MarineProvider = FixedMarineProvider(),
    neighborCountryResolver: any NeighborCountryResolver = FixedNeighborCountryResolver(),
    travelAdvisoryProvider: any TravelAdvisoryProvider = FixedTravelAdvisoryProvider(),
    travelWeatherAlertsProvider: any TravelWeatherAlertsProvider = FixedTravelWeatherAlertsProvider(),
    regionalSecurityProvider: any RegionalSecurityProvider = FixedRegionalSecurityProvider(),
    visitedPlacesStore: any VisitedPlacesStore = InMemoryVisitedPlacesStore(),
    historyStore: any MetricHistoryStore = InMemoryHistoryStore(),
    updateCoordinator: any UpdateCoordinator = NoopUpdateCoordinator()
) -> DashboardDependencies {
    DashboardDependencies(
        throughputMonitor: throughputMonitor,
        latencyProbe: latencyProbe,
        powerMonitor: powerMonitor,
        wifiMonitor: wifiMonitor,
        vpnStatusProvider: vpnStatusProvider,
        publicIPProvider: publicIPProvider,
        publicIPLocationProvider: publicIPLocationProvider,
        reverseGeocodingProvider: reverseGeocodingProvider,
        weatherProvider: weatherProvider,
        marineProvider: marineProvider,
        neighborCountryResolver: neighborCountryResolver,
        travelAdvisoryProvider: travelAdvisoryProvider,
        travelWeatherAlertsProvider: travelWeatherAlertsProvider,
        regionalSecurityProvider: regionalSecurityProvider,
        visitedPlacesStore: visitedPlacesStore,
        historyStore: historyStore,
        updateCoordinator: updateCoordinator
    )
}

private actor InMemoryHistoryStore: MetricHistoryStore {
    private var values: [MetricSeriesKind: [MetricPoint]]
    private var retentionHours: Int

    init(values: [MetricSeriesKind: [MetricPoint]] = [:], retentionHours: Int = 24) {
        self.values = values
        self.retentionHours = retentionHours
    }

    func loadAll() async throws -> [MetricSeriesKind: [MetricPoint]] {
        trim(values)
    }

    func append(_ point: MetricPoint, to series: MetricSeriesKind) async throws {
        values[series, default: []].append(point)
        values = trim(values)
    }

    func reset() async throws {
        values = [:]
    }

    func setRetentionHours(_ retentionHours: Int) async throws {
        self.retentionHours = retentionHours
        values = trim(values)
    }

    private func trim(_ history: [MetricSeriesKind: [MetricPoint]]) -> [MetricSeriesKind: [MetricPoint]] {
        let earliestTimestamp = Date().addingTimeInterval(TimeInterval(-retentionHours * 3_600))
        return history.mapValues { points in
            points
                .filter { $0.timestamp >= earliestTimestamp }
                .sorted { $0.timestamp < $1.timestamp }
        }
    }
}

private actor InMemoryVisitedPlacesStore: VisitedPlacesStore {
    private var values: [VisitedPlace] = []

    func loadAll() async throws -> [VisitedPlace] {
        values.sorted { $0.lastVisitedAt > $1.lastVisitedAt }
    }

    func record(_ input: VisitedPlaceInput) async throws {
        let candidate = VisitedPlace(
            city: normalizedValue(input.city),
            region: normalizedValue(input.region),
            country: input.country.trimmingCharacters(in: .whitespacesAndNewlines),
            countryCode: normalizedValue(input.countryCode)?.uppercased(),
            latitude: input.latitude,
            longitude: input.longitude,
            firstVisitedAt: input.visitedAt,
            lastVisitedAt: input.visitedAt,
            sources: [input.source]
        )

        guard candidate.country.isEmpty == false else {
            return
        }

        if let index = values.firstIndex(where: { $0.id == candidate.id }) {
            let existing = values[index]
            let preferReplacement = input.source == .deviceLocation || existing.coordinate == nil
            values[index] = VisitedPlace(
                city: candidate.city ?? existing.city,
                region: candidate.region ?? existing.region,
                country: candidate.country.isEmpty == false ? candidate.country : existing.country,
                countryCode: candidate.countryCode ?? existing.countryCode,
                latitude: preferReplacement ? candidate.latitude ?? existing.latitude : existing.latitude ?? candidate.latitude,
                longitude: preferReplacement ? candidate.longitude ?? existing.longitude : existing.longitude ?? candidate.longitude,
                firstVisitedAt: min(existing.firstVisitedAt, input.visitedAt),
                lastVisitedAt: max(existing.lastVisitedAt, input.visitedAt),
                sources: uniquedSources(existing.sources + [input.source])
            )
        } else {
            values.append(candidate)
        }
    }

    func reset() async throws {
        values = []
    }

    private func normalizedValue(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), value.isEmpty == false else {
            return nil
        }

        return value
    }

    private func uniquedSources(_ values: [VisitedPlaceSource]) -> [VisitedPlaceSource] {
        var seen = Set<VisitedPlaceSource>()
        return values.filter { seen.insert($0).inserted }
    }
}

private struct FixedThroughputMonitor: ThroughputMonitor {
    func currentSample() async -> NetworkThroughputSample? {
        NetworkThroughputSample(
            downloadBytesPerSecond: 8_000_000,
            uploadBytesPerSecond: 2_000_000,
            activeInterface: "en0",
            collectedAt: .now
        )
    }
}

private struct NilThroughputMonitor: ThroughputMonitor {
    func currentSample() async -> NetworkThroughputSample? {
        nil
    }
}

private struct FixedLatencyProbe: LatencyProbe {
    func currentSample() async -> LatencySample? {
        LatencySample(host: "1.1.1.1", milliseconds: 22, jitterMilliseconds: 2, collectedAt: .now)
    }
}

private struct FixedPowerMonitor: PowerMonitor {
    func currentSnapshot() async -> PowerSnapshot? {
        PowerSnapshot(
            chargePercent: 0.8,
            state: .battery,
            timeRemainingMinutes: 200,
            timeToFullChargeMinutes: nil,
            isLowPowerModeEnabled: false,
            dischargeRateWatts: 11,
            adapterWatts: nil,
            collectedAt: .now
        )
    }
}

private struct FixedWiFiMonitor: WiFiMonitor {
    func currentSnapshot() async -> WiFiSnapshot? {
        WiFiSnapshot(interfaceName: "en0", ssid: "Studio WiFi", rssi: -52, noise: -90, transmitRateMbps: 680)
    }
}

private struct FixedVPNProvider: VPNStatusProvider {
    func currentStatus() async -> VPNStatusSnapshot {
        VPNStatusSnapshot(isActive: true, interfaceNames: [], serviceNames: ["Nomad VPN"])
    }
}

private struct FixedPublicIPProvider: PublicIPProvider {
    func currentIP(forceRefresh: Bool) async throws -> PublicIPSnapshot {
        PublicIPSnapshot(address: "198.51.100.12", provider: "test", fetchedAt: .now)
    }
}

private struct FixedLocationProvider: PublicIPLocationProvider {
    func currentLocation(for ipAddress: String, forceRefresh: Bool) async throws -> IPLocationSnapshot {
        IPLocationSnapshot(
            city: "Helsinki",
            region: "Uusimaa",
            country: "Finland",
            countryCode: "FI",
            latitude: 60.1699,
            longitude: 24.9384,
            timeZone: "Europe/Helsinki",
            provider: "test",
            fetchedAt: .now
        )
    }
}

private struct FixedReverseGeocodingProvider: ReverseGeocodingProvider {
    func details(for location: CLLocation) async throws -> ReverseGeocodedLocation {
        ReverseGeocodedLocation(
            city: "Helsinki",
            region: "Uusimaa",
            country: "Finland",
            countryCode: "FI",
            timeZoneIdentifier: "Europe/Helsinki"
        )
    }
}

private struct FixedNeighborCountryResolver: NeighborCountryResolver {
    func neighboringCountryCodes(for countryCode: String) -> [String] {
        switch countryCode {
        case "FI":
            ["SE", "NO"]
        case "ES":
            ["FR", "PT"]
        default:
            []
        }
    }
}

private actor RecordingTravelAdvisoryProvider: TravelAdvisoryProvider {
    nonisolated let sourceDescriptor = TravelAlertSourceDescriptor(
        name: "Smartraveller",
        url: URL(string: "https://www.smartraveller.gov.au")
    )

    private var calls = 0

    func advisory(for countryCodes: [String], primaryCountryCode: String, forceRefresh: Bool) async throws -> TravelAlertSignalSnapshot {
        calls += 1
        return try await FixedTravelAdvisoryProvider().advisory(for: countryCodes, primaryCountryCode: primaryCountryCode, forceRefresh: forceRefresh)
    }

    func callCount() -> Int {
        calls
    }
}

private struct FixedTravelAdvisoryProvider: TravelAdvisoryProvider {
    let sourceDescriptor = TravelAlertSourceDescriptor(
        name: "Smartraveller",
        url: URL(string: "https://www.smartraveller.gov.au")
    )

    func advisory(for countryCodes: [String], primaryCountryCode: String, forceRefresh: Bool) async throws -> TravelAlertSignalSnapshot {
        TravelAlertSignalSnapshot(
            kind: .advisory,
            severity: .caution,
            title: "Travel advisory",
            summary: "Sweden is at Level 2 nearby.",
            sourceName: "Smartraveller",
            sourceURL: URL(string: "https://www.smartraveller.gov.au"),
            updatedAt: .now,
            affectedCountryCodes: ["SE"]
        )
    }
}

private struct FixedTravelWeatherAlertsProvider: TravelWeatherAlertsProvider {
    let sourceDescriptor = TravelAlertSourceDescriptor(
        name: "WeatherKit",
        url: URL(string: "https://developer.apple.com/weatherkit/")
    )

    func alerts(for coordinate: CLLocationCoordinate2D?, forceRefresh: Bool) async throws -> TravelAlertSignalSnapshot {
        guard coordinate != nil else {
            throw ProviderError.missingCoordinate
        }

        return TravelAlertSignalSnapshot(
            kind: .weather,
            severity: .warning,
            title: "Weather alerts",
            summary: "2 active weather alerts. Flood warning.",
            sourceName: "WeatherKit",
            sourceURL: URL(string: "https://developer.apple.com/weatherkit/"),
            updatedAt: .now,
            affectedCountryCodes: ["FI"],
            itemCount: 2
        )
    }
}

private struct FixedRegionalSecurityProvider: RegionalSecurityProvider {
    let sourceDescriptor = TravelAlertSourceDescriptor(
        name: "ReliefWeb",
        url: URL(string: "https://reliefweb.int")
    )

    func security(for countryCodes: [String], primaryCountryCode: String, forceRefresh: Bool) async throws -> TravelAlertSignalSnapshot {
        TravelAlertSignalSnapshot(
            kind: .security,
            severity: .info,
            title: "Regional security",
            summary: "A nearby security bulletin was published within the last 72 hours.",
            sourceName: "ReliefWeb",
            sourceURL: URL(string: "https://reliefweb.int"),
            updatedAt: .now,
            affectedCountryCodes: ["SE"],
            itemCount: 1
        )
    }
}

private struct MissingConfigurationRegionalSecurityProvider: RegionalSecurityProvider {
    let sourceDescriptor = TravelAlertSourceDescriptor(
        name: "ReliefWeb",
        url: URL(string: "https://reliefweb.int")
    )

    func security(for countryCodes: [String], primaryCountryCode: String, forceRefresh: Bool) async throws -> TravelAlertSignalSnapshot {
        throw ProviderError.missingConfiguration
    }
}

private struct RateLimitedRegionalSecurityProvider: RegionalSecurityProvider {
    let sourceDescriptor = TravelAlertSourceDescriptor(
        name: "ReliefWeb",
        url: URL(string: "https://reliefweb.int")
    )

    func security(for countryCodes: [String], primaryCountryCode: String, forceRefresh: Bool) async throws -> TravelAlertSignalSnapshot {
        throw ReliefWebProviderError.unexpectedStatus(429, bodySnippet: "{\"message\":\"rate limited\"}")
    }
}

private struct UnapprovedAppNameRegionalSecurityProvider: RegionalSecurityProvider {
    let sourceDescriptor = TravelAlertSourceDescriptor(
        name: "ReliefWeb",
        url: URL(string: "https://reliefweb.int")
    )

    func security(for countryCodes: [String], primaryCountryCode: String, forceRefresh: Bool) async throws -> TravelAlertSignalSnapshot {
        throw ReliefWebProviderError.appNameApprovalRequired(
            "You are not using an approved appname. Kindly request an appname from ReliefWeb here: https://apidoc.reliefweb.int/parameters#appname"
        )
    }
}

private actor SequenceTravelWeatherAlertsProvider: TravelWeatherAlertsProvider {
    enum Response {
        case success(TravelAlertSignalSnapshot)
        case failure(ProviderError)
    }

    nonisolated let sourceDescriptor = TravelAlertSourceDescriptor(
        name: "WeatherKit",
        url: URL(string: "https://developer.apple.com/weatherkit/")
    )

    private var responses: [Response]

    init(responses: [Response]) {
        self.responses = responses
    }

    func alerts(for coordinate: CLLocationCoordinate2D?, forceRefresh: Bool) async throws -> TravelAlertSignalSnapshot {
        guard coordinate != nil else {
            throw ProviderError.missingCoordinate
        }

        guard responses.isEmpty == false else {
            throw ProviderError.invalidResponse
        }

        let response = responses.removeFirst()
        switch response {
        case let .success(snapshot):
            return snapshot
        case let .failure(error):
            throw error
        }
    }
}

private actor RecordingLocationProvider: PublicIPLocationProvider {
    private var requestedAddresses: [String] = []

    func currentLocation(for ipAddress: String, forceRefresh: Bool) async throws -> IPLocationSnapshot {
        requestedAddresses.append(ipAddress)
        return try await FixedLocationProvider().currentLocation(for: ipAddress, forceRefresh: forceRefresh)
    }

    func callCount() -> Int {
        requestedAddresses.count
    }
}

private struct FailingLocationProvider: PublicIPLocationProvider {
    func currentLocation(for ipAddress: String, forceRefresh: Bool) async throws -> IPLocationSnapshot {
        throw ProviderError.invalidResponse
    }
}

private struct FixedWeatherProvider: WeatherProvider {
    func weather(for coordinate: CLLocationCoordinate2D?) async throws -> WeatherSnapshot {
        WeatherSnapshot(
            currentTemperatureCelsius: 12,
            apparentTemperatureCelsius: 10,
            conditionDescription: "Clear",
            symbolName: "sun.max.fill",
            precipitationChance: 0.05,
            windSpeedKph: 12,
            tomorrow: WeatherDaySummary(
                date: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now,
                symbolName: "cloud.sun.fill",
                summary: "Cool with light clouds",
                temperatureMinCelsius: 7,
                temperatureMaxCelsius: 14,
                precipitationChance: 0.12
            ),
            fetchedAt: .now
        )
    }
}

private struct FixedMarineProvider: MarineProvider {
    func marine(for spot: MarineSpot) async throws -> MarineSnapshot {
        MarineSnapshot(
            spotName: spot.name,
            coordinate: spot.coordinate,
            sourceName: "Open-Meteo",
            waveHeightMeters: 1.6,
            wavePeriodSeconds: 11,
            swellHeightMeters: 1.2,
            swellPeriodSeconds: 10,
            swellDirectionDegrees: 67.5,
            windSpeedKph: 18,
            windGustKph: 24,
            windDirectionDegrees: 315,
            seaSurfaceTemperatureCelsius: 9,
            forecastSlots: [
                MarineForecastSlot(date: .now, waveHeightMeters: 1.6, swellHeightMeters: 1.2, windSpeedKph: 18, windDirectionDegrees: 315),
                MarineForecastSlot(date: Date().addingTimeInterval(3 * 3_600), waveHeightMeters: 1.4, swellHeightMeters: 1.0, windSpeedKph: 16, windDirectionDegrees: 300),
                MarineForecastSlot(date: Date().addingTimeInterval(6 * 3_600), waveHeightMeters: 1.3, swellHeightMeters: 0.9, windSpeedKph: 13, windDirectionDegrees: 285),
                MarineForecastSlot(date: Date().addingTimeInterval(12 * 3_600), waveHeightMeters: 1.1, swellHeightMeters: 0.8, windSpeedKph: 10, windDirectionDegrees: 270)
            ],
            fetchedAt: .now
        )
    }
}

private struct FailingMarineProvider: MarineProvider {
    func marine(for spot: MarineSpot) async throws -> MarineSnapshot {
        throw ProviderError.invalidResponse
    }
}

private actor RecordingMarineProvider: MarineProvider {
    private var calls = 0

    func marine(for spot: MarineSpot) async throws -> MarineSnapshot {
        calls += 1
        return try await FixedMarineProvider().marine(for: spot)
    }

    func callCount() -> Int {
        calls
    }
}

private struct MissingCoordinateWeatherProvider: WeatherProvider {
    func weather(for coordinate: CLLocationCoordinate2D?) async throws -> WeatherSnapshot {
        throw ProviderError.missingCoordinate
    }
}

private actor RecordingUpdateCoordinator: UpdateCoordinator {
    private var history: [Bool] = []

    func currentState() async -> UpdateStateSnapshot {
        UpdateStateSnapshot(kind: .idle, detail: "Testing", lastCheckedAt: nil)
    }

    func checkForUpdates() async {}

    func setAutomaticChecksEnabled(_ isEnabled: Bool) async {
        history.append(isEnabled)
    }

    func automaticChecksHistory() -> [Bool] {
        history
    }
}
