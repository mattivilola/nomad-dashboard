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
        store.setCurrentLocation(CLLocation(latitude: 60.1699, longitude: 24.9384))
        store.setWeatherCoordinate(CLLocationCoordinate2D(latitude: 60.1699, longitude: 24.9384))

        await store.refresh(manual: true)

        #expect(store.snapshot.travelContext.deviceLocation?.city == "Helsinki")
        #expect(store.snapshot.travelContext.publicIP?.address == "198.51.100.12")
        #expect(store.snapshot.travelContext.location?.country == "Finland")
        #expect(store.snapshot.weather?.conditionDescription == "Clear")
        #expect(store.snapshot.marine?.spotName == "Helsinki Beach")
        #expect(store.snapshot.network.downloadHistory.isEmpty == false)
        #expect(store.snapshot.healthSummary.overall.level == .ready)
    }

    @Test
    func projectedMetricHistoryCapsLargeSeriesPreservingEndpoints() {
        let start = Date(timeIntervalSince1970: 10_000)
        let points = (0..<400).map { index in
            MetricPoint(timestamp: start.addingTimeInterval(Double(index)), value: Double(index))
        }

        let projected = projectedMetricHistory(points)

        #expect(projected.count == 120)
        #expect(projected.first == points.first)
        #expect(projected.last == points.last)
        #expect(zip(projected, projected.dropFirst()).allSatisfy { lhs, rhs in
            lhs.timestamp < rhs.timestamp
        })
    }

    @Test
    func manualRefreshPublishesVisibleActivityUntilCompletion() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        let store = DashboardSnapshotStore(
            settingsStore: settingsStore,
            dependencies: makeDependencies(
                throughputMonitor: SlowThroughputMonitor(),
                historyStore: InMemoryHistoryStore()
            )
        )

        let refreshTask = Task {
            await store.refresh(manual: true)
        }

        try await Task.sleep(for: .milliseconds(10))

        #expect(store.refreshActivity == .manualInProgress)

        await refreshTask.value

        #expect(store.refreshActivity == .idle)
    }

    @Test
    func automaticSlowRefreshPublishesVisibleActivityUntilCompletion() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        let store = DashboardSnapshotStore(
            settingsStore: settingsStore,
            dependencies: makeDependencies(
                throughputMonitor: SlowThroughputMonitor(),
                historyStore: InMemoryHistoryStore()
            )
        )

        let refreshTask = Task {
            await store.refresh(manual: false)
        }

        try await Task.sleep(for: .milliseconds(10))

        #expect(store.refreshActivity == .slowAutomaticInProgress)

        await refreshTask.value

        #expect(store.refreshActivity == .idle)
    }

    @Test
    func automaticFastRefreshKeepsVisibleActivityIdle() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.slowRefreshIntervalSeconds = 60

        let store = DashboardSnapshotStore(
            settingsStore: settingsStore,
            dependencies: makeDependencies(
                throughputMonitor: SlowThroughputMonitor(),
                historyStore: InMemoryHistoryStore()
            )
        )

        await store.refresh(manual: true)

        let refreshTask = Task {
            await store.refresh(manual: false)
        }

        try await Task.sleep(for: .milliseconds(10))

        #expect(store.refreshActivity == .idle)

        await refreshTask.value

        #expect(store.refreshActivity == .idle)
    }

    @Test
    func startupStartDoesNotEmitBackgroundActiveDayDuringInitialManualRefresh() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.refreshIntervalSeconds = 60
        let recorder = RecordingDashboardAnalyticsClient()
        let analytics = makeTestAnalytics(client: recorder, keyPrefix: "startup-start")
        let store = DashboardSnapshotStore(
            settingsStore: settingsStore,
            dependencies: makeDependencies(historyStore: InMemoryHistoryStore()),
            analytics: analytics
        )

        store.start()
        try await waitUntil { store.snapshot.appState.lastRefresh != nil }
        store.stop()

        #expect(recorder.events.map(\.event).contains(.appBackgroundActiveDay) == false)
    }

    @Test
    func firstAutomaticSlowRefreshEmitsBackgroundActiveDay() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.slowRefreshIntervalSeconds = 0
        let recorder = RecordingDashboardAnalyticsClient()
        let analytics = makeTestAnalytics(client: recorder, keyPrefix: "first-automatic-slow-refresh")
        let store = DashboardSnapshotStore(
            settingsStore: settingsStore,
            dependencies: makeDependencies(historyStore: InMemoryHistoryStore()),
            analytics: analytics
        )

        await store.refresh(manual: true)
        await store.refresh(manual: false)

        #expect(recorder.events.map(\.event) == [.appBackgroundActiveDay])
    }

    @Test
    func automaticSlowRefreshEmitsBackgroundActiveDayOncePerDay() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.slowRefreshIntervalSeconds = 0
        let recorder = RecordingDashboardAnalyticsClient()
        let analytics = makeTestAnalytics(client: recorder, keyPrefix: "once-per-day")
        let store = DashboardSnapshotStore(
            settingsStore: settingsStore,
            dependencies: makeDependencies(historyStore: InMemoryHistoryStore()),
            analytics: analytics
        )

        await store.refresh(manual: true)
        await store.refresh(manual: false)
        await store.refresh(manual: false)

        #expect(recorder.events.map(\.event) == [.appBackgroundActiveDay])
    }

    @Test
    func automaticSlowRefreshEmitsBackgroundActiveDayAgainOnNewDay() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.slowRefreshIntervalSeconds = 0
        let recorder = RecordingDashboardAnalyticsClient()
        let dateSource = MutableAnalyticsDateSource(current: Date(timeIntervalSince1970: 1_710_547_200))
        let analytics = makeTestAnalytics(
            client: recorder,
            keyPrefix: "new-day",
            dateSource: dateSource
        )
        let store = DashboardSnapshotStore(
            settingsStore: settingsStore,
            dependencies: makeDependencies(historyStore: InMemoryHistoryStore()),
            analytics: analytics
        )

        await store.refresh(manual: true)
        await store.refresh(manual: false)
        dateSource.current = dateSource.current.addingTimeInterval(24 * 60 * 60)
        await store.refresh(manual: false)

        #expect(recorder.events.map(\.event) == [
            .appBackgroundActiveDay,
            .appBackgroundActiveDay
        ])
    }

    @Test
    func automaticFastRefreshDoesNotEmitBackgroundActiveDay() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.slowRefreshIntervalSeconds = 60
        let recorder = RecordingDashboardAnalyticsClient()
        let analytics = makeTestAnalytics(client: recorder, keyPrefix: "automatic-fast-refresh")
        let store = DashboardSnapshotStore(
            settingsStore: settingsStore,
            dependencies: makeDependencies(historyStore: InMemoryHistoryStore()),
            analytics: analytics
        )

        await store.refresh(manual: true)
        await store.refresh(manual: false)

        #expect(recorder.events.isEmpty)
    }

    @Test
    func manualSlowRefreshDoesNotEmitBackgroundActiveDay() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.slowRefreshIntervalSeconds = 0
        let recorder = RecordingDashboardAnalyticsClient()
        let analytics = makeTestAnalytics(client: recorder, keyPrefix: "manual-slow-refresh")
        let store = DashboardSnapshotStore(
            settingsStore: settingsStore,
            dependencies: makeDependencies(historyStore: InMemoryHistoryStore()),
            analytics: analytics
        )

        await store.refresh(manual: true)

        #expect(recorder.events.isEmpty)
    }

    @Test
    func automaticSlowRefreshEmitsBackgroundActiveDayEvenWhenProvidersFail() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.slowRefreshIntervalSeconds = 0
        let recorder = RecordingDashboardAnalyticsClient()
        let analytics = makeTestAnalytics(client: recorder, keyPrefix: "provider-failure")
        let dependencies = makeDependencies(
            publicIPLocationProvider: FailingLocationProvider(),
            historyStore: InMemoryHistoryStore()
        )
        let store = DashboardSnapshotStore(
            settingsStore: settingsStore,
            dependencies: dependencies,
            analytics: analytics
        )

        await store.refresh(manual: true)
        await store.refresh(manual: false)

        #expect(recorder.events.map(\.event) == [.appBackgroundActiveDay])
        #expect(store.snapshot.appState.issues.contains(.ipLocationUnavailable))
    }

    @Test
    func overlappingRefreshesCoalesceIntoSingleManualFollowUp() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        let throughputMonitor = SlowThroughputMonitor()
        let publicIPProvider = RecordingPublicIPProvider()
        let dependencies = makeDependencies(
            throughputMonitor: throughputMonitor,
            publicIPProvider: publicIPProvider,
            historyStore: InMemoryHistoryStore()
        )

        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies)

        let firstRefresh = Task {
            await store.refresh(manual: true)
        }

        try await Task.sleep(for: .milliseconds(10))

        let overlappingRefreshes = [
            Task { await store.refresh(manual: false) },
            Task { await store.refresh(manual: true) },
            Task { await store.refresh(manual: true) }
        ]

        await firstRefresh.value
        for task in overlappingRefreshes {
            await task.value
        }

        #expect(await throughputMonitor.callCount() == 2)
        #expect(await publicIPProvider.callCount() == 2)
    }

    @Test
    func refreshStoresVisitedPlaceFromDeviceLocationBeforeIPGeolocation() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.publicIPGeolocationEnabled = true
        settingsStore.settings.visitedPlacesEnabled = true

        let dependencies = makeDependencies(publicIPLocationProvider: VPNLocationProvider())
        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies)
        store.setCurrentLocation(CLLocation(latitude: 60.1699, longitude: 24.9384))

        await store.refresh(manual: true)

        #expect(store.visitedPlaces.count == 1)
        #expect(store.visitedPlaces.first?.city == "Helsinki")
        #expect(store.visitedPlaces.first?.countryCode == "FI")
        #expect(store.visitedPlaces.first?.sources == [.deviceLocation])
        #expect(store.visitedPlaceSummary.citiesVisited == 1)
        #expect(store.visitedPlaceSummary.countriesVisited == 1)
        #expect(store.visitedPlaceEvents.count == 1)
        #expect(store.visitedPlaceEvents.first?.city == "Helsinki")
        #expect(store.visitedPlaceEvents.first?.countryCode == "FI")
        #expect(store.visitedPlaceEvents.first?.sources == [.deviceLocation])
        #expect(store.visitedPlaceEventYears.count == 1)
        #expect(store.visitedPlaceTravelStops(for: store.visitedPlaceEventYears[0]).count == 1)
        #expect(store.visitedCountryDays.count == 1)
        #expect(store.visitedCountryDays.first?.countryCode == "FI")
        #expect(store.visitedCountryDays.first?.source == .deviceLocation)
        #expect(store.visitedCountryDayYears.count == 1)
        #expect(store.visitedCountryDaySummary(for: store.visitedCountryDayYears[0])?.totalTrackedDays == 1)
    }

    @Test
    func refreshFallsBackToIPVisitedPlaceWhenDeviceLocationIsUnavailable() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.publicIPGeolocationEnabled = true
        settingsStore.settings.visitedPlacesEnabled = true

        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: makeDependencies())

        await store.refresh(manual: true)

        #expect(store.visitedPlaces.count == 1)
        #expect(store.visitedPlaces.first?.city == "Helsinki")
        #expect(store.visitedPlaces.first?.countryCode == "FI")
        #expect(store.visitedPlaces.first?.sources == [.publicIPGeolocation])
        #expect(store.visitedPlaceEvents.count == 1)
        #expect(store.visitedPlaceEvents.first?.sources == [.publicIPGeolocation])
        #expect(store.visitedCountryDays.first?.source == .publicIPGeolocation)
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
        #expect(store.visitedPlaceEvents.isEmpty)
        #expect(store.visitedPlaceSummary.citiesVisited == 0)
        #expect(store.visitedPlaceSummary.countriesVisited == 0)
        #expect(store.visitedCountryDays.isEmpty)
        #expect(store.visitedCountryDayYears.isEmpty)
    }

    @Test
    func clearVisitedPlacesResetsCountryDayDiary() async throws {
        let settingsStore = try AppSettingsStore(defaults: isolatedDefaults())
        settingsStore.settings.publicIPGeolocationEnabled = true
        settingsStore.settings.visitedPlacesEnabled = true

        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: makeDependencies())
        store.setCurrentLocation(CLLocation(latitude: 60.1699, longitude: 24.9384))

        await store.refresh(manual: true)
        #expect(store.visitedPlaces.isEmpty == false)
        #expect(store.visitedPlaceEvents.isEmpty == false)
        #expect(store.visitedCountryDays.isEmpty == false)

        store.clearVisitedPlaces()

        try await waitUntil {
            store.visitedPlaces.isEmpty && store.visitedPlaceEvents.isEmpty && store.visitedCountryDays.isEmpty
        }
        #expect(store.visitedCountryDayYears.isEmpty)
    }

    @Test
    func loadsVisitedCountryDayYearsAndSummary() async throws {
        let settingsStore = try AppSettingsStore(defaults: isolatedDefaults())
        let visitedCountryDaysStore = InMemoryVisitedCountryDaysStore(values: [
            .init(day: .init(year: 2025, month: 12, day: 30), country: "Spain", countryCode: "ES", source: .publicIPGeolocation, isInferred: false),
            .init(day: .init(year: 2026, month: 1, day: 1), country: "Finland", countryCode: "FI", source: .deviceLocation, isInferred: false),
            .init(day: .init(year: 2026, month: 1, day: 2), country: "Finland", countryCode: "FI", source: .deviceLocation, isInferred: true),
            .init(day: .init(year: 2026, month: 1, day: 3), country: "Sweden", countryCode: "SE", source: .deviceLocation, isInferred: false)
        ])

        let store = DashboardSnapshotStore(
            settingsStore: settingsStore,
            dependencies: makeDependencies(visitedCountryDaysStore: visitedCountryDaysStore)
        )

        try await waitUntil {
            store.visitedCountryDays.count == 4
        }

        #expect(store.visitedCountryDayYears == [2026, 2025])
        let summary = store.visitedCountryDaySummary(for: 2026)
        #expect(summary?.totalTrackedDays == 3)
        #expect(summary?.items.map(\.countryCode) == ["FI", "SE"])
        #expect(summary?.items.map(\.dayCount) == [2, 1])
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
    func refreshMarksFuelPricesLocationRequirementWhenCurrentLocationIsMissing() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.fuelPricesEnabled = true
        settingsStore.settings.useCurrentLocationForWeather = false

        let dependencies = makeDependencies(historyStore: InMemoryHistoryStore())
        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies)

        await store.refresh(manual: true)

        #expect(store.snapshot.fuelPrices?.status == .locationRequired)
        #expect(store.snapshot.fuelPrices?.detail == "Allow current location to look up nearby fuel prices.")
    }

    @Test
    func refreshLoadsLocalInfoFromProvider() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.localInfoEnabled = true
        settingsStore.settings.useCurrentLocationForWeather = false

        let dependencies = makeDependencies(historyStore: InMemoryHistoryStore())
        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies)

        await store.refresh(manual: true)

        #expect(store.snapshot.localInfo?.status == .partial)
        #expect(store.snapshot.localInfo?.localPriceLevel?.summaryBand == .medium)
        #expect(store.snapshot.localInfo?.localPriceLevel?.rows.map(\.kind) == [.mealOut, .groceries, .overall])
        #expect(store.snapshot.localInfo?.publicHolidayStatus.state == .upcoming)
    }

    @Test
    func refreshUpdatesLocalPriceProviderConfigurationWhenHUDTokenChanges() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.localInfoEnabled = true
        settingsStore.settings.useCurrentLocationForWeather = false

        let localPriceProvider = RecordingConfigurableLocalPriceLevelProvider()
        let dependencies = makeDependencies(
            localPriceLevelProvider: localPriceProvider,
            historyStore: InMemoryHistoryStore()
        )

        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies)

        await store.refresh(manual: true)
        #expect(store.snapshot.localInfo?.localPriceLevel?.status == .configurationRequired)

        settingsStore.settings.hudUserAPIToken = "hud-token-123"

        try? await Task.sleep(for: .milliseconds(50))

        #expect(await localPriceProvider.latestConfiguredToken() == "hud-token-123")
        #expect(store.snapshot.localInfo?.localPriceLevel?.status == .partial)
        #expect(store.snapshot.localInfo?.localPriceLevel?.rows.first?.kind == .rentOneBedroom)
    }

    @Test
    func refreshLoadsFuelPricesForSupportedCurrentCountry() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.fuelPricesEnabled = true
        settingsStore.settings.useCurrentLocationForWeather = false

        let fuelPriceProvider = RecordingFuelPriceProvider()
        let dependencies = makeDependencies(
            reverseGeocodingProvider: SpanishReverseGeocodingProvider(),
            fuelPriceProvider: fuelPriceProvider,
            historyStore: InMemoryHistoryStore()
        )

        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies)
        store.setCurrentLocation(CLLocation(latitude: 39.4699, longitude: -0.3763))

        await store.refresh(manual: true)

        #expect(store.snapshot.fuelPrices?.status == .ready)
        #expect(store.snapshot.fuelPrices?.diesel?.stationName == "Plenoil Valencia Puerto")
        #expect(await fuelPriceProvider.requestedCountryCodes() == ["ES"])
        #expect(store.snapshot.fuelDiagnostics?.status == .ready)
        #expect(store.snapshot.fuelDiagnostics?.stage == .bestPriceSelection)
        #expect(store.snapshot.fuelDiagnostics?.providerName == "Spanish Ministry Fuel Prices")
        #expect(store.snapshot.fuelDiagnostics?.elapsedMilliseconds == 800)
        #expect(store.snapshot.fuelDiagnostics?.error == nil)
    }

    @Test
    func refreshUpdatesFuelProviderConfigurationWhenTankerkonigKeyChanges() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.fuelPricesEnabled = true
        settingsStore.settings.useCurrentLocationForWeather = false

        let fuelPriceProvider = RecordingConfigurableFuelPriceProvider()
        let dependencies = makeDependencies(
            reverseGeocodingProvider: GermanReverseGeocodingProvider(),
            fuelPriceProvider: fuelPriceProvider,
            historyStore: InMemoryHistoryStore()
        )

        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies)
        store.setCurrentLocation(CLLocation(latitude: 52.52, longitude: 13.405))

        await store.refresh(manual: true)
        #expect(store.snapshot.fuelPrices?.status == .configurationRequired)

        settingsStore.settings.tankerkonigAPIKey = "user-key-123"

        try? await Task.sleep(for: .milliseconds(50))

        #expect(await fuelPriceProvider.latestConfiguredAPIKey() == "user-key-123")
        #expect(store.snapshot.fuelPrices?.status == .ready)
        #expect(store.snapshot.fuelPrices?.sourceName == "Tankerkönig")
    }

    @Test
    func refreshStoresFuelDiagnosticsWhenReverseGeocodingHasNoCountryCode() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.fuelPricesEnabled = true
        settingsStore.settings.useCurrentLocationForWeather = false

        let dependencies = makeDependencies(
            reverseGeocodingProvider: MissingFuelCountryReverseGeocodingProvider(),
            historyStore: InMemoryHistoryStore()
        )

        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies)
        store.setCurrentLocation(CLLocation(latitude: 39.4699, longitude: -0.3763))

        await store.refresh(manual: true)

        #expect(store.snapshot.fuelPrices?.status == .unavailable)
        #expect(store.snapshot.fuelDiagnostics?.stage == .reverseGeocoding)
        #expect(store.snapshot.fuelDiagnostics?.summary == "Current location country could not be resolved.")
        #expect(store.snapshot.fuelDiagnostics?.countryName == "Spain")
    }

    @Test
    func refreshPreservesStructuredFuelFailureDiagnostics() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.fuelPricesEnabled = true
        settingsStore.settings.useCurrentLocationForWeather = false

        let failure = FuelPriceProviderError(
            sourceName: "Spanish Ministry Fuel Prices",
            sourceURL: URL(string: "https://example.com/fuel"),
            stage: .requestStarted,
            details: FuelDiagnosticsError(
                failureKind: .tlsHandshake,
                domain: NSURLErrorDomain,
                code: URLError.secureConnectionFailed.rawValue,
                localizedDescription: "An SSL error has occurred and a secure connection to the server cannot be made.",
                failingURL: URL(string: "https://example.com/fuel"),
                responseMIMEType: "application/json",
                payloadByteCount: 0,
                urlErrorSymbol: "secureConnectionFailed",
                summary: "Fuel source TLS handshake failed."
            )
        )
        let dependencies = makeDependencies(
            reverseGeocodingProvider: SpanishReverseGeocodingProvider(),
            fuelPriceProvider: FailingFuelPriceProvider(failure: failure),
            historyStore: InMemoryHistoryStore()
        )

        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies)
        store.setCurrentLocation(CLLocation(latitude: 39.4699, longitude: -0.3763))

        await store.refresh(manual: true)

        #expect(store.snapshot.fuelPrices?.status == .unavailable)
        #expect(store.snapshot.fuelPrices?.note == "Fuel source TLS handshake failed.")
        #expect(store.snapshot.fuelDiagnostics?.stage == .requestStarted)
        #expect(store.snapshot.fuelDiagnostics?.error?.failureKind == .tlsHandshake)
        #expect(store.snapshot.fuelDiagnostics?.error?.urlErrorSymbol == "secureConnectionFailed")
        #expect(store.snapshot.fuelDiagnostics?.error?.failingURL?.absoluteString == "https://example.com/fuel")
    }

    @Test
    func fuelDiagnosticsReportTextIncludesProviderCountryAndNormalizedError() {
        let diagnostics = FuelDiagnosticsSnapshot(
            status: .unavailable,
            stage: .requestStarted,
            countryCode: "ES",
            countryName: "Spain",
            latitude: 39.4699,
            longitude: -0.3763,
            searchRadiusKilometers: 50,
            providerName: "Spanish Ministry Fuel Prices",
            sourceURL: URL(string: "https://example.com/fuel"),
            startedAt: .now.addingTimeInterval(-1),
            finishedAt: .now,
            elapsedMilliseconds: 1_000,
            summary: "Fuel source TLS handshake failed.",
            error: FuelDiagnosticsError(
                failureKind: .tlsHandshake,
                domain: NSURLErrorDomain,
                code: URLError.secureConnectionFailed.rawValue,
                localizedDescription: "An SSL error has occurred and a secure connection to the server cannot be made.",
                failingURL: URL(string: "https://example.com/fuel"),
                urlErrorSymbol: "secureConnectionFailed",
                summary: "Fuel source TLS handshake failed."
            )
        )

        let report = diagnostics.reportText(fuelPrices: nil)

        #expect(report.contains("Provider: Spanish Ministry Fuel Prices"))
        #expect(report.contains("Country: Spain · ES"))
        #expect(report.contains("Failure kind: TLS Handshake"))
        #expect(report.contains("URL error symbol: secureConnectionFailed"))
        #expect(report.contains("Summary: Fuel source TLS handshake failed."))
    }

    @Test
    func fuelStationMapDestinationBuildsGoogleMapsDirectionsURLFromCoordinates() throws {
        let destination = FuelStationMapDestination(
            fuelType: .diesel,
            stationName: "Cheap Diesel",
            address: "Harbor Road 12",
            locality: "Valencia",
            pricePerLiter: 1.429,
            latitude: 39.4699,
            longitude: -0.3763,
            updatedAt: nil
        )

        let url = try #require(destination.googleMapsURL)

        #expect(url.absoluteString.contains("https://www.google.com/maps/dir/"))
        #expect(url.absoluteString.contains("destination=39.4699,-0.3763"))
        #expect(url.absoluteString.contains("travelmode=driving"))
    }

    @Test
    func fuelStationMapDestinationFallsBackToSearchQueryWhenCoordinatesAreInvalid() throws {
        let destination = FuelStationMapDestination(
            fuelType: .gasoline,
            stationName: "Ballenoil Alfafar",
            address: "Avinguda del Port 3",
            locality: "Valencia",
            pricePerLiter: 1.519,
            latitude: 190,
            longitude: -500,
            updatedAt: nil
        )

        let url = try #require(destination.googleMapsURL)

        #expect(url.absoluteString.contains("https://www.google.com/maps/search/"))
        #expect(url.absoluteString.contains("Ballenoil"))
        #expect(destination.isCoordinateValid == false)
    }

    @Test
    func refreshMarksEmergencyCareLocationRequirementWhenCurrentLocationIsMissing() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.emergencyCareEnabled = true
        settingsStore.settings.useCurrentLocationForWeather = false

        let dependencies = makeDependencies(historyStore: InMemoryHistoryStore())
        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies)

        await store.refresh(manual: true)

        #expect(store.snapshot.emergencyCare?.status == .locationRequired)
        #expect(store.snapshot.emergencyCare?.detail == "Allow current location to look up nearby emergency hospitals.")
    }

    @Test
    func refreshLoadsEmergencyCareForCurrentLocation() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.emergencyCareEnabled = true
        settingsStore.settings.useCurrentLocationForWeather = false

        let emergencyCareProvider = RecordingEmergencyCareProvider()
        let dependencies = makeDependencies(
            emergencyCareProvider: emergencyCareProvider,
            historyStore: InMemoryHistoryStore()
        )

        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies)
        store.setCurrentLocation(CLLocation(latitude: 39.4699, longitude: -0.3763))

        await store.refresh(manual: true)

        #expect(store.snapshot.emergencyCare?.status == .ready)
        #expect(store.snapshot.emergencyCare?.hospitals.count == 3)
        #expect(store.snapshot.emergencyCare?.hospitals.first?.ownership == .public)
        #expect(await emergencyCareProvider.callCount() == 1)
    }

    @Test
    func refreshMarksEmergencyCareUnavailableWhenProviderFails() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.emergencyCareEnabled = true
        settingsStore.settings.useCurrentLocationForWeather = false

        let dependencies = makeDependencies(
            emergencyCareProvider: FailingEmergencyCareProvider(),
            historyStore: InMemoryHistoryStore()
        )

        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies)
        store.setCurrentLocation(CLLocation(latitude: 39.4699, longitude: -0.3763))

        await store.refresh(manual: true)

        #expect(store.snapshot.emergencyCare?.status == .unavailable)
        #expect(store.snapshot.emergencyCare?.detail == "Nearby emergency hospitals are unavailable right now.")
    }

    @Test
    func emergencyHospitalMapDestinationBuildsGoogleMapsDirectionsURLFromCoordinates() throws {
        let destination = EmergencyHospitalMapDestination(
            hospitalName: "Hospital Universitari i Politècnic La Fe",
            address: "Avinguda de Fernando Abril Martorell 106",
            locality: "Valencia",
            ownership: .public,
            latitude: 39.4468,
            longitude: -0.3762
        )

        let url = try #require(destination.googleMapsURL)

        #expect(url.absoluteString.contains("https://www.google.com/maps/dir/"))
        #expect(url.absoluteString.contains("destination=39.4468,-0.3762"))
        #expect(url.absoluteString.contains("travelmode=driving"))
    }

    @Test
    func emergencyHospitalMapDestinationFallsBackToSearchQueryWhenCoordinatesAreInvalid() throws {
        let destination = EmergencyHospitalMapDestination(
            hospitalName: "Hospital IMED Valencia Private",
            address: "Avinguda de la Ilustració 1",
            locality: "Burjassot",
            ownership: .private,
            latitude: 190,
            longitude: -500
        )

        let url = try #require(destination.googleMapsURL)

        #expect(url.absoluteString.contains("https://www.google.com/maps/search/"))
        #expect(url.absoluteString.contains("Hospital"))
        #expect(destination.isCoordinateValid == false)
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
    func settingsChangesRefreshFuelPricesImmediately() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.fuelPricesEnabled = false

        let fuelPriceProvider = RecordingFuelPriceProvider()
        let dependencies = makeDependencies(
            reverseGeocodingProvider: SpanishReverseGeocodingProvider(),
            fuelPriceProvider: fuelPriceProvider,
            historyStore: InMemoryHistoryStore()
        )

        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies)
        store.setCurrentLocation(CLLocation(latitude: 39.4699, longitude: -0.3763))

        await store.refresh(manual: true)
        #expect(await fuelPriceProvider.callCount() == 0)

        settingsStore.settings.fuelPricesEnabled = true

        try await waitForSettingsPropagation()
        #expect(await fuelPriceProvider.callCount() == 1)
        #expect(store.snapshot.fuelPrices?.status == .ready)
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
        #expect(await updateCoordinator.automaticChecksHistory().last == false)

        settingsStore.settings.automaticUpdateChecksEnabled = true

        try await waitForSettingsPropagation()
        #expect(await updateCoordinator.automaticChecksHistory().suffix(2) == [false, true])
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

    private func makeTestAnalytics(
        client: some AnalyticsClient,
        keyPrefix: String,
        dateSource: MutableAnalyticsDateSource = MutableAnalyticsDateSource(current: Date(timeIntervalSince1970: 1_710_547_200))
    ) -> AppAnalytics {
        AppAnalytics(
            client: client,
            defaults: try! isolatedDefaults(),
            keyPrefix: keyPrefix,
            calendar: Calendar(identifier: .gregorian),
            now: { dateSource.current }
        )
    }

    private func isolatedDefaults() throws -> UserDefaults {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        pollInterval: Duration = .milliseconds(10),
        condition: @escaping () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while condition() == false {
            if ContinuousClock.now >= deadline {
                Issue.record("Condition was not met before timeout.")
                return
            }

            try await Task.sleep(for: pollInterval)
        }
    }
}

private func makeDependencies(
    throughputMonitor: any ThroughputMonitor = FixedThroughputMonitor(),
    connectivityMonitor: any ConnectivityMonitor = FixedConnectivityMonitor(),
    latencyProbe: any LatencyProbe = FixedLatencyProbe(),
    powerMonitor: any PowerMonitor = FixedPowerMonitor(),
    wifiMonitor: any WiFiMonitor = FixedWiFiMonitor(),
    vpnStatusProvider: any VPNStatusProvider = FixedVPNProvider(),
    publicIPProvider: any PublicIPProvider = FixedPublicIPProvider(),
    publicIPLocationProvider: any PublicIPLocationProvider = FixedLocationProvider(),
    reverseGeocodingProvider: any ReverseGeocodingProvider = FixedReverseGeocodingProvider(),
    weatherProvider: any WeatherProvider = FixedWeatherProvider(),
    localInfoProvider: (any LocalInfoProvider)? = nil,
    localPriceLevelProvider: any LocalPriceLevelProvider = FixedLocalPriceLevelProvider(),
    fuelPriceProvider: any FuelPriceProvider = FixedFuelPriceProvider(),
    emergencyCareProvider: any EmergencyCareProvider = FixedEmergencyCareProvider(),
    marineProvider: any MarineProvider = FixedMarineProvider(),
    neighborCountryResolver: any NeighborCountryResolver = FixedNeighborCountryResolver(),
    travelAdvisoryProvider: any TravelAdvisoryProvider = FixedTravelAdvisoryProvider(),
    travelWeatherAlertsProvider: any TravelWeatherAlertsProvider = FixedTravelWeatherAlertsProvider(),
    regionalSecurityProvider: any RegionalSecurityProvider = FixedRegionalSecurityProvider(),
    visitedPlacesStore: any VisitedPlacesStore = InMemoryVisitedPlacesStore(),
    visitedPlaceEventsStore: any VisitedPlaceEventsStore = InMemoryVisitedPlaceEventsStore(),
    visitedCountryDaysStore: any VisitedCountryDaysStore = InMemoryVisitedCountryDaysStore(),
    historyStore: any MetricHistoryStore = InMemoryHistoryStore(),
    updateCoordinator: any UpdateCoordinator = NoopUpdateCoordinator()
) -> DashboardDependencies {
    DashboardDependencies(
        throughputMonitor: throughputMonitor,
        connectivityMonitor: connectivityMonitor,
        latencyProbe: latencyProbe,
        powerMonitor: powerMonitor,
        wifiMonitor: wifiMonitor,
        vpnStatusProvider: vpnStatusProvider,
        publicIPProvider: publicIPProvider,
        publicIPLocationProvider: publicIPLocationProvider,
        reverseGeocodingProvider: reverseGeocodingProvider,
        weatherProvider: weatherProvider,
        localInfoProvider: localInfoProvider ?? FixedLocalInfoProvider(localPriceLevelProvider: localPriceLevelProvider),
        fuelPriceProvider: fuelPriceProvider,
        emergencyCareProvider: emergencyCareProvider,
        marineProvider: marineProvider,
        neighborCountryResolver: neighborCountryResolver,
        travelAdvisoryProvider: travelAdvisoryProvider,
        travelWeatherAlertsProvider: travelWeatherAlertsProvider,
        regionalSecurityProvider: regionalSecurityProvider,
        visitedPlacesStore: visitedPlacesStore,
        visitedPlaceEventsStore: visitedPlaceEventsStore,
        visitedCountryDaysStore: visitedCountryDaysStore,
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

private actor InMemoryVisitedPlaceEventsStore: VisitedPlaceEventsStore {
    private var values: [VisitedPlaceEvent] = []

    func loadAll() async throws -> [VisitedPlaceEvent] {
        values.sorted { $0.firstObservedAt < $1.firstObservedAt }
    }

    func record(_ input: VisitedPlaceEventInput) async throws {
        guard let event = VisitedPlaceEvent.from(input) else {
            return
        }

        if let index = values.firstIndex(where: { $0.id == event.id }) {
            values[index] = values[index].merging(input: input)
        } else {
            values.append(event)
        }
    }

    func reset() async throws {
        values = []
    }
}

private actor InMemoryVisitedCountryDaysStore: VisitedCountryDaysStore {
    private var values: [VisitedCountryDay]

    init(values: [VisitedCountryDay] = []) {
        self.values = values.sorted { $0.day < $1.day }
    }

    func loadAll() async throws -> [VisitedCountryDay] {
        values.sorted { $0.day < $1.day }
    }

    func record(_ input: VisitedCountryDayInput) async throws {
        guard let entry = VisitedCountryDay.from(input) else {
            return
        }

        if let existingIndex = values.firstIndex(where: { $0.day == entry.day }) {
            let existing = values[existingIndex]
            if existing.isInferred || (existing.source == .publicIPGeolocation && entry.source == .deviceLocation) {
                values[existingIndex] = entry
                values = rebuiltEntries(from: values)
            }
            return
        }

        values.append(entry)
        values = rebuiltEntries(from: values)
    }

    func reset() async throws {
        values = []
    }

    private func gapDays(from start: VisitedCountryDayStamp, to end: VisitedCountryDayStamp) -> Int {
        dayDistance(from: start, to: end) - 1
    }

    private func rebuiltEntries(from entries: [VisitedCountryDay]) -> [VisitedCountryDay] {
        let observedEntries = entries
            .filter { $0.isInferred == false }
            .sorted { $0.day < $1.day }

        guard let firstEntry = observedEntries.first else {
            return []
        }

        var rebuiltEntries = [firstEntry]

        for index in observedEntries.indices.dropFirst() {
            let previous = observedEntries[index - 1]
            let current = observedEntries[index]
            let gapDays = gapDays(from: previous.day, to: current.day)
            guard gapDays > 0 else {
                rebuiltEntries.append(current)
                continue
            }

            let usesSameCountry = previous.countryCode == current.countryCode
                || (
                    previous.countryCode == nil
                        && current.countryCode == nil
                        && previous.country.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                            == current.country.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                )
            let previousCountryCount = usesSameCountry ? gapDays : (gapDays + 1) / 2

            let inferredEntries = (1...gapDays).compactMap { offset -> VisitedCountryDay? in
                guard let day = offsetDay(previous.day, by: offset) else {
                    return nil
                }

                let template = offset <= previousCountryCount ? previous : current
                return VisitedCountryDay(
                    day: day,
                    country: template.country,
                    countryCode: template.countryCode,
                    source: template.source,
                    isInferred: true
                )
            }

            rebuiltEntries.append(contentsOf: inferredEntries)
            rebuiltEntries.append(current)
        }

        return rebuiltEntries
    }

    private func dayDistance(from start: VisitedCountryDayStamp, to end: VisitedCountryDayStamp) -> Int {
        guard let startDate = date(for: start), let endDate = date(for: end) else {
            return 0
        }

        return Self.calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0
    }

    private func offsetDay(_ day: VisitedCountryDayStamp, by value: Int) -> VisitedCountryDayStamp? {
        guard
            let date = date(for: day),
            let offsetDate = Self.calendar.date(byAdding: .day, value: value, to: date)
        else {
            return nil
        }

        return VisitedCountryDayStamp(date: offsetDate, calendar: Self.calendar)
    }

    private func date(for day: VisitedCountryDayStamp) -> Date? {
        Self.calendar.date(from: DateComponents(
            calendar: Self.calendar,
            timeZone: Self.calendar.timeZone,
            year: day.year,
            month: day.month,
            day: day.day,
            hour: 12
        ))
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
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

private struct FixedConnectivityMonitor: ConnectivityMonitor {
    func currentSnapshot() async -> ConnectivitySnapshot {
        ConnectivitySnapshot(pathAvailable: true, internetState: .online, lastCheckedAt: .now)
    }
}

private actor SlowThroughputMonitor: ThroughputMonitor {
    private var calls = 0

    func currentSample() async -> NetworkThroughputSample? {
        calls += 1
        try? await Task.sleep(for: .milliseconds(50))
        return await FixedThroughputMonitor().currentSample()
    }

    func callCount() -> Int {
        calls
    }
}

private final class MutableAnalyticsDateSource: @unchecked Sendable {
    var current: Date

    init(current: Date) {
        self.current = current
    }
}

@MainActor
private final class RecordingDashboardAnalyticsClient: @unchecked Sendable, AnalyticsClient {
    struct EventRecord: Sendable, Equatable {
        let event: AnalyticsEvent
        let properties: [String: String]
    }

    private(set) var events: [EventRecord] = []

    func track(_ event: AnalyticsEvent, properties: [String: String]) {
        events.append(EventRecord(event: event, properties: properties))
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

private actor RecordingPublicIPProvider: PublicIPProvider {
    private var calls = 0

    func currentIP(forceRefresh: Bool) async throws -> PublicIPSnapshot {
        calls += 1
        return try await FixedPublicIPProvider().currentIP(forceRefresh: forceRefresh)
    }

    func callCount() -> Int {
        calls
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

private struct VPNLocationProvider: PublicIPLocationProvider {
    func currentLocation(for ipAddress: String, forceRefresh: Bool) async throws -> IPLocationSnapshot {
        IPLocationSnapshot(
            city: "Amsterdam",
            region: "North Holland",
            country: "Netherlands",
            countryCode: "NL",
            latitude: 52.3676,
            longitude: 4.9041,
            timeZone: "Europe/Amsterdam",
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

private struct FixedLocalPriceLevelProvider: LocalPriceLevelProvider {
    func prices(for request: LocalPriceSearchRequest, forceRefresh: Bool) async throws -> LocalPriceLevelSnapshot {
        LocalPriceLevelSnapshot(
            status: .ready,
            summaryBand: .medium,
            countryCode: request.countryCode,
            countryName: request.countryName,
            rows: [
                LocalPriceIndicatorRow(
                    kind: .mealOut,
                    value: "Moderate",
                    detail: "4% below EU average · Country fallback · 2024",
                    precision: .countryFallback,
                    source: LocalPriceSourceAttribution(name: "Eurostat", url: URL(string: "https://ec.europa.eu"))
                ),
                LocalPriceIndicatorRow(
                    kind: .groceries,
                    value: "Moderate",
                    detail: "4% below EU average · Country fallback · 2024",
                    precision: .countryFallback,
                    source: LocalPriceSourceAttribution(name: "Eurostat", url: URL(string: "https://ec.europa.eu"))
                ),
                LocalPriceIndicatorRow(
                    kind: .overall,
                    value: "Moderate",
                    detail: "1% below EU average · Country fallback · 2024",
                    precision: .countryFallback,
                    source: LocalPriceSourceAttribution(name: "Eurostat", url: URL(string: "https://ec.europa.eu"))
                )
            ],
            sources: [
                LocalPriceSourceAttribution(name: "Eurostat", url: URL(string: "https://ec.europa.eu"))
            ],
            fetchedAt: Date(),
            detail: "Country fallback snapshot.",
            note: nil
        )
    }
}

private struct FixedLocalInfoProvider: LocalInfoProvider, LocalPriceLevelProviderConfigurationUpdating {
    let localPriceLevelProvider: any LocalPriceLevelProvider

    func info(for request: LocalInfoRequest, forceRefresh: Bool) async throws -> LocalInfoSnapshot {
        let localPriceLevel = try await localPriceLevelProvider.prices(
            for: LocalPriceSearchRequest(
                coordinate: request.coordinate,
                countryCode: request.countryCode,
                countryName: request.countryName,
                locality: request.locality
            ),
            forceRefresh: forceRefresh
        )

        return LocalInfoSnapshot(
            status: .partial,
            locality: request.locality,
            administrativeRegion: request.administrativeRegion,
            countryCode: request.countryCode,
            countryName: request.countryName,
            timeZoneIdentifier: request.timeZoneIdentifier,
            subdivisionCode: nil,
            publicHolidayStatus: LocalHolidayStatus(
                state: .upcoming,
                currentPeriod: nil,
                nextPeriod: HolidayPeriodSnapshot(
                    name: "Midsummer Day",
                    startDate: .now.addingTimeInterval(86_400 * 10),
                    endDate: .now.addingTimeInterval(86_400 * 10)
                ),
                note: nil
            ),
            schoolHolidayStatus: nil,
            localPriceLevel: localPriceLevel,
            sources: [
                HolidaySourceAttribution(name: "Nager.Date", url: URL(string: "https://date.nager.at/")),
                HolidaySourceAttribution(name: "Eurostat", url: URL(string: "https://ec.europa.eu"))
            ],
            fetchedAt: .now,
            detail: "Some local signals are limited right now.",
            note: "School holiday coverage needs a confident regional match."
        )
    }

    func setHUDUserAPIToken(_ token: String?) async {
        if let configurableProvider = localPriceLevelProvider as? LocalPriceLevelProviderConfigurationUpdating {
            await configurableProvider.setHUDUserAPIToken(token)
        }
    }
}

private actor RecordingConfigurableLocalPriceLevelProvider: LocalPriceLevelProvider, LocalPriceLevelProviderConfigurationUpdating {
    private var configuredToken: String?

    func prices(for request: LocalPriceSearchRequest, forceRefresh: Bool) async throws -> LocalPriceLevelSnapshot {
        if configuredToken == nil {
            return LocalPriceLevelSnapshot(
                status: .configurationRequired,
                summaryBand: nil,
                countryCode: "US",
                countryName: "United States",
                rows: [],
                sources: [],
                fetchedAt: nil,
                detail: "Add a HUD token.",
                note: nil
            )
        }

        return LocalPriceLevelSnapshot(
            status: .partial,
            summaryBand: .limited,
            countryCode: "US",
            countryName: "United States",
            rows: [
                LocalPriceIndicatorRow(
                    kind: .rentOneBedroom,
                    value: "$1,900/mo",
                    detail: "Metro benchmark · Seattle metro · 2024",
                    precision: .metroBenchmark,
                    source: LocalPriceSourceAttribution(name: "HUD USER", url: URL(string: "https://www.huduser.gov"))
                )
            ],
            sources: [
                LocalPriceSourceAttribution(name: "HUD USER", url: URL(string: "https://www.huduser.gov"))
            ],
            fetchedAt: Date(),
            detail: "US rent-only snapshot.",
            note: nil
        )
    }

    func setHUDUserAPIToken(_ token: String?) async {
        configuredToken = token
    }

    func latestConfiguredToken() async -> String? {
        configuredToken
    }
}

private struct FixedFuelPriceProvider: FuelPriceProvider {
    func prices(for request: FuelSearchRequest, forceRefresh: Bool) async throws -> FuelPriceSnapshot {
        if request.countryCode == "ES" {
            return FuelPriceSnapshot(
                status: .ready,
                sourceName: "Spanish Ministry Fuel Prices",
                sourceURL: URL(string: "https://example.com/spain-fuel"),
                countryCode: "ES",
                countryName: request.countryName,
                searchRadiusKilometers: request.searchRadiusKilometers,
                diesel: FuelStationPrice(
                    fuelType: .diesel,
                    stationName: "Plenoil Valencia Puerto",
                    address: "Harbor Road 12",
                    locality: "Valencia",
                    pricePerLiter: 1.429,
                    distanceKilometers: 4.8,
                    latitude: request.coordinate.latitude,
                    longitude: request.coordinate.longitude,
                    updatedAt: .now
                ),
                gasoline: FuelStationPrice(
                    fuelType: .gasoline,
                    stationName: "Ballenoil Alfafar",
                    address: "Avinguda del Port 3",
                    locality: "Valencia",
                    pricePerLiter: 1.519,
                    distanceKilometers: 8.6,
                    latitude: request.coordinate.latitude,
                    longitude: request.coordinate.longitude,
                    updatedAt: .now
                ),
                fetchedAt: .now,
                detail: "Cheapest prices within 50 km.",
                note: nil
            )
        }

        return FuelPriceSnapshot(
            status: .unsupported,
            sourceName: "Nomad Fuel Prices",
            sourceURL: nil,
            countryCode: request.countryCode,
            countryName: request.countryName,
            searchRadiusKilometers: request.searchRadiusKilometers,
            diesel: nil,
            gasoline: nil,
            fetchedAt: .now,
            detail: "Fuel prices are not supported in \(request.countryName ?? request.countryCode) yet.",
            note: nil
        )
    }
}

extension FixedFuelPriceProvider: FuelPriceDiagnosticsProviding {
    func latestRequestDiagnostics() async -> FuelProviderRequestDiagnostics? {
        FuelProviderRequestDiagnostics(
            stage: .bestPriceSelection,
            providerName: "Spanish Ministry Fuel Prices",
            sourceURL: URL(string: "https://example.com/spain-fuel"),
            startedAt: Date().addingTimeInterval(-0.8),
            finishedAt: .now,
            elapsedMilliseconds: 800,
            responseMIMEType: "application/json",
            payloadByteCount: 2_048,
            httpStatusCode: 200,
            summary: "Fuel prices loaded successfully.",
            error: nil
        )
    }
}

private struct FixedEmergencyCareProvider: EmergencyCareProvider {
    func nearbyHospitals(
        for request: EmergencyCareSearchRequest,
        forceRefresh: Bool
    ) async throws -> EmergencyCareSnapshot {
        EmergencyCareSnapshot(
            status: .ready,
            sourceName: "Apple Maps",
            sourceURL: URL(string: "https://maps.apple.com"),
            searchRadiusKilometers: request.searchRadiusKilometers,
            hospitals: [
                EmergencyHospital(
                    name: "Hospital Universitari i Politècnic La Fe",
                    address: "Avinguda de Fernando Abril Martorell 106",
                    locality: "Valencia",
                    distanceKilometers: 3.2,
                    latitude: 39.4468,
                    longitude: -0.3762,
                    ownership: .public
                ),
                EmergencyHospital(
                    name: "Hospital IMED Valencia Private",
                    address: "Avinguda de la Ilustració 1",
                    locality: "Burjassot",
                    distanceKilometers: 6.8,
                    latitude: 39.5092,
                    longitude: -0.4188,
                    ownership: .private
                ),
                EmergencyHospital(
                    name: "Hospital Casa de Salut",
                    address: "Carrer del Doctor Manuel Candela 41",
                    locality: "Valencia",
                    distanceKilometers: 2.4,
                    latitude: 39.4662,
                    longitude: -0.3473,
                    ownership: .unknown
                )
            ],
            fetchedAt: .now,
            detail: "Nearby emergency hospitals within \(Int(request.searchRadiusKilometers)) km."
        )
    }
}

private actor RecordingEmergencyCareProvider: EmergencyCareProvider {
    private var calls = 0

    func nearbyHospitals(
        for request: EmergencyCareSearchRequest,
        forceRefresh: Bool
    ) async throws -> EmergencyCareSnapshot {
        calls += 1
        return try await FixedEmergencyCareProvider().nearbyHospitals(for: request, forceRefresh: forceRefresh)
    }

    func callCount() -> Int {
        calls
    }
}

private struct FailingEmergencyCareProvider: EmergencyCareProvider {
    struct Failure: Error {}

    func nearbyHospitals(
        for request: EmergencyCareSearchRequest,
        forceRefresh: Bool
    ) async throws -> EmergencyCareSnapshot {
        throw Failure()
    }
}

private actor RecordingFuelPriceProvider: FuelPriceProvider, FuelPriceDiagnosticsProviding {
    private var requests: [FuelSearchRequest] = []
    private var latestDiagnosticsValue: FuelProviderRequestDiagnostics?

    func prices(for request: FuelSearchRequest, forceRefresh: Bool) async throws -> FuelPriceSnapshot {
        requests.append(request)
        latestDiagnosticsValue = await FixedFuelPriceProvider().latestRequestDiagnostics()
        return try await FixedFuelPriceProvider().prices(for: request, forceRefresh: forceRefresh)
    }

    func callCount() -> Int {
        requests.count
    }

    func requestedCountryCodes() -> [String] {
        requests.map(\.countryCode)
    }

    func latestRequestDiagnostics() async -> FuelProviderRequestDiagnostics? {
        latestDiagnosticsValue
    }
}

private actor RecordingConfigurableFuelPriceProvider: FuelPriceProvider, FuelPriceDiagnosticsProviding, FuelPriceProviderConfigurationUpdating {
    private var apiKey: String?
    private var latestDiagnosticsValue: FuelProviderRequestDiagnostics?

    func prices(for request: FuelSearchRequest, forceRefresh: Bool) async throws -> FuelPriceSnapshot {
        if request.countryCode == "DE", apiKey == nil {
            latestDiagnosticsValue = FuelProviderRequestDiagnostics(
                stage: .providerSelection,
                providerName: "Tankerkönig",
                sourceURL: URL(string: "https://creativecommons.tankerkoenig.de/"),
                startedAt: nil,
                finishedAt: .now,
                elapsedMilliseconds: nil,
                responseMIMEType: nil,
                payloadByteCount: nil,
                httpStatusCode: nil,
                summary: "Germany needs your Tankerkönig API key in Settings.",
                error: nil
            )
            return FuelPriceSnapshot(
                status: .configurationRequired,
                sourceName: "Tankerkönig",
                sourceURL: URL(string: "https://creativecommons.tankerkoenig.de/"),
                countryCode: request.countryCode,
                countryName: request.countryName,
                searchRadiusKilometers: request.searchRadiusKilometers,
                diesel: nil,
                gasoline: nil,
                fetchedAt: .now,
                detail: "Germany needs your Tankerkönig API key in Settings.",
                note: "Germany uses the free Tankerkönig API."
            )
        }

        latestDiagnosticsValue = FuelProviderRequestDiagnostics(
            stage: .bestPriceSelection,
            providerName: "Tankerkönig",
            sourceURL: URL(string: "https://creativecommons.tankerkoenig.de/"),
            startedAt: .now.addingTimeInterval(-0.4),
            finishedAt: .now,
            elapsedMilliseconds: 400,
            responseMIMEType: "application/json",
            payloadByteCount: 1_024,
            httpStatusCode: 200,
            summary: "Fuel prices loaded successfully.",
            error: nil
        )
        return FuelPriceSnapshot(
            status: .ready,
            sourceName: "Tankerkönig",
            sourceURL: URL(string: "https://creativecommons.tankerkoenig.de/"),
            countryCode: request.countryCode,
            countryName: request.countryName,
            searchRadiusKilometers: request.searchRadiusKilometers,
            diesel: FuelStationPrice(
                fuelType: .diesel,
                stationName: "Berlin Diesel",
                address: "Alexanderplatz 1",
                locality: "Berlin",
                pricePerLiter: 1.649,
                distanceKilometers: 3.2,
                latitude: request.coordinate.latitude,
                longitude: request.coordinate.longitude,
                updatedAt: .now
            ),
            gasoline: nil,
            fetchedAt: .now,
            detail: "Cheapest prices within 50 km.",
            note: "Germany uses the free Tankerkönig API."
        )
    }

    func latestRequestDiagnostics() async -> FuelProviderRequestDiagnostics? {
        latestDiagnosticsValue
    }

    func setTankerkonigAPIKey(_ apiKey: String?) async {
        self.apiKey = apiKey
    }

    func latestConfiguredAPIKey() -> String? {
        apiKey
    }
}

private struct SpanishReverseGeocodingProvider: ReverseGeocodingProvider {
    func details(for location: CLLocation) async throws -> ReverseGeocodedLocation {
        ReverseGeocodedLocation(
            city: "Valencia",
            region: "Valencian Community",
            country: "Spain",
            countryCode: "ES",
            timeZoneIdentifier: "Europe/Madrid"
        )
    }
}

private struct GermanReverseGeocodingProvider: ReverseGeocodingProvider {
    func details(for location: CLLocation) async throws -> ReverseGeocodedLocation {
        ReverseGeocodedLocation(
            city: "Berlin",
            region: "Berlin",
            country: "Germany",
            countryCode: "DE",
            timeZoneIdentifier: "Europe/Berlin"
        )
    }
}

private struct MissingFuelCountryReverseGeocodingProvider: ReverseGeocodingProvider {
    func details(for location: CLLocation) async throws -> ReverseGeocodedLocation {
        ReverseGeocodedLocation(
            city: "Valencia",
            region: "Valencian Community",
            country: "Spain",
            countryCode: nil,
            timeZoneIdentifier: "Europe/Madrid"
        )
    }
}

private actor FailingFuelPriceProvider: FuelPriceProvider, FuelPriceDiagnosticsProviding {
    private let failure: FuelPriceProviderError

    init(failure: FuelPriceProviderError) {
        self.failure = failure
    }

    func prices(for request: FuelSearchRequest, forceRefresh: Bool) async throws -> FuelPriceSnapshot {
        throw failure
    }

    func latestRequestDiagnostics() async -> FuelProviderRequestDiagnostics? {
        FuelProviderRequestDiagnostics(
            stage: failure.stage,
            providerName: failure.sourceName,
            sourceURL: failure.sourceURL,
            startedAt: Date().addingTimeInterval(-1),
            finishedAt: .now,
            elapsedMilliseconds: 1_000,
            responseMIMEType: failure.responseMIMEType,
            payloadByteCount: failure.payloadByteCount,
            httpStatusCode: failure.httpStatusCode,
            summary: failure.diagnosticSummary,
            error: failure.details
        )
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
            windDirectionDegrees: 315,
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
                MarineForecastSlot(date: Date().addingTimeInterval(3 * 3_600), waveHeightMeters: 1.4, swellHeightMeters: 1.0, windSpeedKph: 16, windDirectionDegrees: 300),
                MarineForecastSlot(date: Date().addingTimeInterval(6 * 3_600), waveHeightMeters: 1.3, swellHeightMeters: 0.9, windSpeedKph: 13, windDirectionDegrees: 285),
                MarineForecastSlot(date: Date().addingTimeInterval(12 * 3_600), waveHeightMeters: 1.1, swellHeightMeters: 0.8, windSpeedKph: 10, windDirectionDegrees: 270),
                MarineForecastSlot(date: Date().addingTimeInterval(24 * 3_600), waveHeightMeters: 0.9, swellHeightMeters: 0.7, windSpeedKph: 8, windDirectionDegrees: 255)
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
