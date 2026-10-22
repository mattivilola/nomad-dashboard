import CoreLocation
import Foundation
@testable import NomadCore
import Testing

@MainActor
struct DashboardSnapshotStoreTests {
    @Test
    func manualWeatherRefreshForcesProviderAndRetainsLastResultOnFailure() async throws {
        let settings = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        let weather = RecordingWeatherProvider()
        let store = DashboardSnapshotStore(settingsStore: settings, dependencies: makeDependencies(weatherProvider: weather))
        store.setCurrentLocation(CLLocation(latitude: 43, longitude: -1))
        await store.refresh()
        let saved = try #require(store.snapshot.weather)
        await store.refresh(section: .weather)
        #expect(await weather.requests == [false, true])
        #expect(store.snapshot.weather == saved)
        #expect(store.snapshot.appState.issues.contains(.weatherUnavailable))
        #expect(store.sectionActivity[.weather]?.message?.contains("Couldn't update") == true)
    }

    @Test
    func localAndIndependentCardsPublishBeforeSuspendedWeather() async throws {
        let settings = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        let weather = HeldWeatherProvider()
        let store = DashboardSnapshotStore(settingsStore: settings, dependencies: makeDependencies(weatherProvider: weather))
        store.setCurrentLocation(CLLocation(latitude: 60.17, longitude: 24.94))
        let task = Task { await store.refresh(manual: true) }
        await weather.waitUntilStarted()
        await waitForStore(store, "the independent cards to publish") {
            store.snapshot.power.snapshot != nil && store.snapshot.travelContext.publicIP != nil
        }
        #expect(store.snapshot.weather == nil)
        #expect(store.snapshot.network.throughput != nil)
        #expect(store.sectionActivity[.weather]?.isRefreshing == true)
        await weather.release()
        await task.value
        #expect(store.snapshot.weather != nil)
    }

    @Test
    func cancellationRejectsLateProviderResult() async throws {
        let settings = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        let weather = HeldWeatherProvider()
        let store = DashboardSnapshotStore(settingsStore: settings, dependencies: makeDependencies(weatherProvider: weather))
        let task = Task { await store.refresh(manual: true) }
        await weather.waitUntilStarted()
        store.stop()
        await task.value
        await weather.release()
        // The held call now returns its late result; the store must have nothing left to apply it to.
        await waitForIdle(store)
        #expect(store.snapshot.weather == nil)
        #expect(store.refreshActivity == .idle)
        #expect(store.sectionActivity.values.allSatisfy { !$0.isRefreshing })
    }

    @Test
    func reopeningUsesFreshProviderCachesWithoutForcingRequests() async throws {
        let settings = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        let ip = RecordingPublicIPProvider()
        let store = DashboardSnapshotStore(settingsStore: settings, dependencies: makeDependencies(publicIPProvider: ip))
        await store.refresh(manual: true)
        store.setDashboardInterfaceActive(false)
        store.setDashboardInterfaceActive(true)
        await store.refresh()
        #expect(await ip.callCount() == 1)
    }

    @Test
    func onDemandLatencyProbeFillsAMissingReadingWhileTheDashboardIsClosed() async throws {
        let settings = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        let store = DashboardSnapshotStore(settingsStore: settings, dependencies: makeDependencies())
        store.setDashboardInterfaceActive(false)
        await store.refresh()
        #expect(store.snapshot.network.latency == nil)

        await store.probeLatencyIfStale()

        #expect(store.snapshot.network.latency?.milliseconds == 22)
    }

    @Test
    func onDemandLatencyProbeReusesAFreshReadingAndRefreshesAnOldOne() async throws {
        let settings = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        // Every reading is a second newer than the one before, and the first is already ten seconds old, so
        // no test depends on how much wall-clock time passes between probes.
        let probe = SequencedLatencyProbe(firstReadingAge: 10, interval: 1)
        let store = DashboardSnapshotStore(settingsStore: settings, dependencies: makeDependencies(latencyProbe: probe))
        await store.refresh()
        let first = try #require(store.snapshot.network.latency)
        #expect(await probe.callCount() == 1)

        await store.probeLatencyIfStale()
        #expect(store.snapshot.network.latency == first)
        #expect(await probe.callCount() == 1)

        await store.probeLatencyIfStale(maximumAge: 5)
        #expect(try #require(store.snapshot.network.latency).collectedAt > first.collectedAt)
        #expect(await probe.callCount() == 2)
    }

    @Test
    func lowDataModeDefersLargeOptionalBackgroundCards() async throws {
        let settings = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settings.settings.dataUsageMode = .lowData
        settings.settings.localInfoEnabled = true
        settings.settings.fuelPricesEnabled = true
        let store = DashboardSnapshotStore(settingsStore: settings, dependencies: makeDependencies())
        store.setCurrentLocation(CLLocation(latitude: 60.17, longitude: 24.94))
        await store.refresh()
        #expect(store.resourcePolicy.isLowData)
        #expect(store.snapshot.weather != nil)
        #expect(store.snapshot.fuelPrices == nil)
        #expect(store.snapshot.localInfo == nil)
        await store.refresh(section: .localInfo)
        #expect(store.snapshot.localInfo != nil)
    }

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
        let throughputMonitor = GatedThroughputMonitor()
        let store = DashboardSnapshotStore(
            settingsStore: settingsStore,
            dependencies: makeDependencies(
                throughputMonitor: throughputMonitor,
                historyStore: InMemoryHistoryStore()
            )
        )

        let refreshTask = Task {
            await store.refresh(manual: true)
        }

        await throughputMonitor.waitForCall(1)

        #expect(store.refreshActivity == .manualInProgress)

        await throughputMonitor.release()
        await refreshTask.value

        #expect(store.refreshActivity == .idle)
    }

    @Test
    func automaticSlowRefreshPublishesVisibleActivityUntilCompletion() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        let throughputMonitor = GatedThroughputMonitor()
        let store = DashboardSnapshotStore(
            settingsStore: settingsStore,
            dependencies: makeDependencies(
                throughputMonitor: throughputMonitor,
                historyStore: InMemoryHistoryStore()
            )
        )

        let refreshTask = Task {
            await store.refresh(manual: false)
        }

        await throughputMonitor.waitForCall(1)

        #expect(store.refreshActivity == .slowAutomaticInProgress)

        await throughputMonitor.release()
        await refreshTask.value

        #expect(store.refreshActivity == .idle)
    }

    @Test
    func automaticFastRefreshKeepsVisibleActivityIdle() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.slowRefreshIntervalSeconds = 60

        let throughputMonitor = GatedThroughputMonitor(isHeld: false)
        let store = DashboardSnapshotStore(
            settingsStore: settingsStore,
            dependencies: makeDependencies(
                throughputMonitor: throughputMonitor,
                historyStore: InMemoryHistoryStore()
            )
        )

        await store.refresh(manual: true)
        await throughputMonitor.hold()

        let refreshTask = Task {
            await store.refresh(manual: false)
        }

        await throughputMonitor.waitForCall(2)

        #expect(store.refreshActivity == .idle)

        await throughputMonitor.release()
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
        // The startup refresh runs as a manual one; idle again means its external part has finished too, so
        // an event it wrongly emitted would already be recorded.
        await waitForStore(store, "the startup refresh to finish") {
            store.snapshot.appState.lastRefresh != nil && store.refreshActivity == .idle
        }
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
    func hiddenDashboardDefersSlowRefreshWorkEvenWhenUserCadenceIsAggressive() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.slowRefreshIntervalSeconds = 0
        let publicIPProvider = RecordingPublicIPProvider()
        let store = DashboardSnapshotStore(
            settingsStore: settingsStore,
            dependencies: makeDependencies(
                publicIPProvider: publicIPProvider,
                historyStore: InMemoryHistoryStore()
            )
        )

        await store.refresh(manual: true)
        store.setDashboardInterfaceActive(false)
        await store.refresh(manual: false)

        #expect(await publicIPProvider.callCount() == 1)
    }

    @Test
    func overlappingRefreshesShareCurrentWorkWithoutForcedFollowUp() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        let throughputMonitor = GatedThroughputMonitor()
        let publicIPProvider = GatedPublicIPProvider()
        let dependencies = makeDependencies(
            throughputMonitor: throughputMonitor,
            publicIPProvider: publicIPProvider,
            historyStore: InMemoryHistoryStore()
        )

        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies)

        let firstRefresh = Task {
            await store.refresh(manual: true)
        }

        await throughputMonitor.waitForCall(1)

        let (joins, continuation) = AsyncStream<Void>.makeStream()
        store.refreshJoinObserver = { continuation.yield() }
        defer { continuation.finish() }
        let overlappingRefreshes = [
            Task { await store.refresh(manual: false) },
            Task { await store.refresh(manual: true) },
            Task { await store.refresh(manual: true) }
        ]
        await waitForRefreshJoins(joins, count: overlappingRefreshes.count)

        // Both phases remain in flight until every overlapping request has joined.
        await throughputMonitor.release()
        await publicIPProvider.release()
        await firstRefresh.value
        for task in overlappingRefreshes {
            await task.value
        }

        #expect(await throughputMonitor.callCount() == 1)
        #expect(await publicIPProvider.callCount() == 1)
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

        await waitForStore(store, "the cleared diary to publish") {
            store.visitedPlaces.isEmpty && store.visitedPlaceEvents.isEmpty && store.visitedCountryDays.isEmpty
        }
        #expect(store.visitedCountryDayYears.isEmpty)
    }

    @Test
    func loadsVisitedCountryDayYearsAndSummary() async throws {
        let settingsStore = try AppSettingsStore(defaults: isolatedDefaults())
        let visitedCountryDaysStore = InMemoryVisitedCountryDaysStore(values: [
            .init(day: .init(year: 2_025, month: 12, day: 30), country: "Spain", countryCode: "ES", source: .publicIPGeolocation, isInferred: false),
            .init(day: .init(year: 2_026, month: 1, day: 1), country: "Finland", countryCode: "FI", source: .deviceLocation, isInferred: false),
            .init(day: .init(year: 2_026, month: 1, day: 2), country: "Finland", countryCode: "FI", source: .deviceLocation, isInferred: true),
            .init(day: .init(year: 2_026, month: 1, day: 3), country: "Sweden", countryCode: "SE", source: .deviceLocation, isInferred: false)
        ])

        let store = DashboardSnapshotStore(
            settingsStore: settingsStore,
            dependencies: makeDependencies(visitedCountryDaysStore: visitedCountryDaysStore)
        )

        await waitForStore(store, "the stored country days to load") {
            store.visitedCountryDays.count == 4
        }

        #expect(store.visitedCountryDayYears == [2_026, 2_025])
        let summary = store.visitedCountryDaySummary(for: 2_026)
        #expect(summary?.totalTrackedDays == 3)
        #expect(summary?.items.map(\.countryCode) == ["FI", "SE"])
        #expect(summary?.items.map(\.dayCount) == [2, 1])
    }

    @Test
    func recordsTheEffectiveTimeZoneInTheShiftHistory() async throws {
        let settingsStore = try AppSettingsStore(defaults: isolatedDefaults())
        settingsStore.settings.publicIPGeolocationEnabled = false
        settingsStore.settings.useCurrentLocationForWeather = false
        let shiftStore = InMemoryTimeZoneShiftStore()
        let earlier = TimeZoneShiftRecord(
            date: Date().addingTimeInterval(-20 * 86_400), identifier: "Pacific/Kiritimati", offsetSeconds: 50_400
        )
        try await shiftStore.record(earlier)

        let store = DashboardSnapshotStore(
            settingsStore: settingsStore,
            dependencies: makeDependencies(timeZoneShiftStore: shiftStore)
        )
        await store.refresh(manual: true)

        await waitForStore(store, "the time zone shift to be recorded") {
            store.timeZoneShifts.count == 2
        }
        #expect(store.timeZoneShifts.first == earlier)
        #expect(store.timeZoneShifts.last?.identifier == TimeZone.current.identifier)
        #expect(store.timeZoneShifts.last?.offsetSeconds == TimeZone.current.secondsFromGMT())

        // The same zone again adds nothing.
        await store.refresh(manual: true)
        #expect(try await shiftStore.loadAll().count == 2)

        store.clearVisitedPlaces()
        await waitForStore(store, "the cleared shift history to publish") {
            store.timeZoneShifts.isEmpty || store.timeZoneShifts.count == 1
        }
        #expect(store.timeZoneShifts.first != earlier)
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
    func changingTheHomeCountryOrCitizenshipRefreshesLocalInfoImmediately() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.localInfoEnabled = true
        settingsStore.settings.useCurrentLocationForWeather = false

        let localInfoProvider = RecordingHomeCountryLocalInfoProvider()
        let store = DashboardSnapshotStore(
            settingsStore: settingsStore,
            dependencies: makeDependencies(localInfoProvider: localInfoProvider, historyStore: InMemoryHistoryStore())
        )

        await store.refresh(manual: true)
        let initial = await localInfoProvider.requestedHomeCountryCodes()
        #expect(initial.isEmpty == false)
        #expect(initial.allSatisfy { $0 == nil })

        settingsStore.settings.citizenshipCountryCodes = ["FI"]
        await waitForSettingsToTakeEffect(store)
        #expect(await localInfoProvider.requestedHomeCountryCodes().last == "FI")

        settingsStore.settings.homeCountryCode = "SE"
        await waitForSettingsToTakeEffect(store)
        #expect(await localInfoProvider.requestedHomeCountryCodes().last == "SE")

        settingsStore.settings.homeCountryCode = nil
        await waitForSettingsToTakeEffect(store)
        #expect(await localInfoProvider.requestedHomeCountryCodes().last == "FI")
    }

    @Test
    func aSettingChangedMidRefreshGetsAFollowUpRefreshWithTheNewSettings() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.localInfoEnabled = true
        settingsStore.settings.useCurrentLocationForWeather = false
        settingsStore.settings.homeCountryCode = "FI"

        let throughputMonitor = GatedThroughputMonitor()
        let localInfoProvider = RecordingHomeCountryLocalInfoProvider()
        let store = DashboardSnapshotStore(
            settingsStore: settingsStore,
            dependencies: makeDependencies(
                throughputMonitor: throughputMonitor,
                localInfoProvider: localInfoProvider,
                historyStore: InMemoryHistoryStore()
            )
        )

        let running = Task { await store.refresh(manual: true) }
        await localInfoProvider.waitForRequests(1)
        await throughputMonitor.waitForCall(1)

        // The refresh is still collecting local metrics (the held monitor) when the setting changes.
        settingsStore.settings.homeCountryCode = "SE"
        await waitForSettingsChangesToRegister(store)
        await throughputMonitor.release()
        await running.value
        await waitForIdle(store)

        #expect(await localInfoProvider.requestedHomeCountryCodes() == ["FI", "SE"])
    }

    @Test
    func severalQuickSettingChangesShareOneFollowUpRefresh() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.localInfoEnabled = true
        settingsStore.settings.useCurrentLocationForWeather = false

        let throughputMonitor = GatedThroughputMonitor()
        let localInfoProvider = RecordingHomeCountryLocalInfoProvider()
        let store = DashboardSnapshotStore(
            settingsStore: settingsStore,
            dependencies: makeDependencies(
                throughputMonitor: throughputMonitor,
                localInfoProvider: localInfoProvider,
                historyStore: InMemoryHistoryStore()
            )
        )

        let running = Task { await store.refresh(manual: true) }
        await localInfoProvider.waitForRequests(1)
        await throughputMonitor.waitForCall(1)

        // Each change is applied and has asked for its refresh while the first one is still running.
        settingsStore.settings.homeCountryCode = "SE"
        await waitForSettingsChangesToRegister(store)
        settingsStore.settings.homeCountryCode = "NO"
        await waitForSettingsChangesToRegister(store)
        settingsStore.settings.homeCountryCode = "DK"
        await waitForSettingsChangesToRegister(store)
        await throughputMonitor.release()
        await running.value
        // Idle means every requested refresh has finished and none is left pending, so the counts are final.
        await waitForIdle(store)

        let requested = await localInfoProvider.requestedHomeCountryCodes()
        #expect(requested.count == 2)
        #expect(requested.last == "DK")
    }

    @Test
    func aTimerRefreshDuringARunningRefreshJoinsItWithoutAnotherFetch() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.localInfoEnabled = true
        settingsStore.settings.useCurrentLocationForWeather = false
        settingsStore.settings.refreshIntervalSeconds = 60

        let throughputMonitor = GatedThroughputMonitor()
        let localInfoProvider = RecordingHomeCountryLocalInfoProvider()
        let store = DashboardSnapshotStore(
            settingsStore: settingsStore,
            dependencies: makeDependencies(
                throughputMonitor: throughputMonitor,
                localInfoProvider: localInfoProvider,
                historyStore: InMemoryHistoryStore()
            )
        )

        let running = Task { await store.refresh(manual: true) }
        await localInfoProvider.waitForRequests(1)
        await throughputMonitor.waitForCall(1)

        // The periodic loop ticks while the refresh is still collecting local metrics.
        let (joins, continuation) = AsyncStream<Void>.makeStream()
        store.refreshJoinObserver = { continuation.yield() }
        defer { continuation.finish() }
        store.start()
        await waitForRefreshJoins(joins, count: 1)
        await throughputMonitor.release()
        await running.value
        await waitForIdle(store)
        store.stop()

        #expect(await throughputMonitor.callCount() == 1)
        #expect(await localInfoProvider.requestedHomeCountryCodes().count == 1)
    }

    @Test
    func aManualRefreshDuringAnAutomaticRefreshGetsAForcedFollowUp() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.localInfoEnabled = true
        settingsStore.settings.useCurrentLocationForWeather = false

        let throughputMonitor = GatedThroughputMonitor()
        let localInfoProvider = RecordingHomeCountryLocalInfoProvider()
        let store = DashboardSnapshotStore(
            settingsStore: settingsStore,
            dependencies: makeDependencies(
                throughputMonitor: throughputMonitor,
                localInfoProvider: localInfoProvider,
                historyStore: InMemoryHistoryStore()
            )
        )

        let automatic = Task { await store.refresh(manual: false) }
        await localInfoProvider.waitForRequests(1)
        await throughputMonitor.waitForCall(1)
        #expect(store.refreshActivity == .slowAutomaticInProgress)
        let manual = Task { await store.refresh(manual: true) }
        // A manual request shows as manual activity the moment it joins the running refresh.
        await waitForStore(store, "the manual request to join the running refresh") {
            store.refreshActivity == .manualInProgress
        }
        await throughputMonitor.release()
        await automatic.value
        await manual.value
        await waitForIdle(store)

        #expect(await localInfoProvider.requestedHomeCountryCodes().count == 2)
    }

    @Test
    func tripPreviewOnlineAsksTheServiceWithTheCurrentSettingsAndPolicy() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        let online = TripPreviewOnline(holidays: [], advisory: nil, fetchedAt: Date(timeIntervalSince1970: 1_791_806_400))
        let store = DashboardSnapshotStore(
            settingsStore: settingsStore,
            dependencies: makeDependencies(
                tripPreviewService: FixedTripPreviewService(result: online),
                historyStore: InMemoryHistoryStore()
            )
        )
        let trip = PlannedTrip(
            countryCode: "MA",
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            endDate: Date(timeIntervalSince1970: 1_800_500_000)
        )

        #expect(await store.tripPreviewOnline(for: trip) == online)
    }

    @Test
    func priceLevelIndicesAreNilWhenTheSourceFails() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        let indices: [LocalPriceIndicatorKind: Double] = [.overall: 80, .groceries: 70]
        let working = DashboardSnapshotStore(
            settingsStore: settingsStore,
            dependencies: makeDependencies(
                priceLevelIndexProvider: FixedPriceLevelIndexProvider(indices: ["PT": indices]),
                historyStore: InMemoryHistoryStore()
            )
        )
        let failing = DashboardSnapshotStore(
            settingsStore: settingsStore,
            dependencies: makeDependencies(
                priceLevelIndexProvider: FixedPriceLevelIndexProvider(failing: true),
                historyStore: InMemoryHistoryStore()
            )
        )

        #expect(await working.priceLevelIndices(forCountryCode: "PT") == indices)
        #expect(await working.priceLevelIndices(forCountryCode: "MA") == [:])
        #expect(await failing.priceLevelIndices(forCountryCode: "PT") == nil)
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

        await waitForSettingsToTakeEffect(store)

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

        await waitForSettingsToTakeEffect(store)

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

        await waitForSettingsToTakeEffect(store)
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

        await waitForSettingsToTakeEffect(store)
        #expect(await marineProvider.callCount() >= 1)
        #expect(store.snapshot.marine?.spotName == "Helsinki Beach")
    }

    @Test
    func refreshFetchesAirQualityForTheWeatherLocation() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        let airQualityProvider = RecordingAirQualityProvider()
        let store = DashboardSnapshotStore(
            settingsStore: settingsStore,
            dependencies: makeDependencies(airQualityProvider: airQualityProvider, historyStore: InMemoryHistoryStore())
        )
        store.setCurrentLocation(CLLocation(latitude: 60.1699, longitude: 24.9384))

        await store.refresh(manual: true)

        #expect(store.snapshot.airQuality?.europeanAQI == 42)
        #expect(store.sectionActivity[.airQuality]?.lastSuccessAt != nil)
        #expect(await airQualityProvider.requestedCoordinates().count == 1)
    }

    @Test
    func refreshSkipsAirQualityWhenItsSettingOrWeatherLocationIsOff() async throws {
        for configure in [
            { (settings: inout AppSettings) in settings.airQualityEnabled = false },
            { (settings: inout AppSettings) in settings.useCurrentLocationForWeather = false }
        ] {
            let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
            configure(&settingsStore.settings)
            let airQualityProvider = RecordingAirQualityProvider()
            let store = DashboardSnapshotStore(
                settingsStore: settingsStore,
                dependencies: makeDependencies(airQualityProvider: airQualityProvider, historyStore: InMemoryHistoryStore())
            )
            store.setCurrentLocation(CLLocation(latitude: 60.1699, longitude: 24.9384))

            await store.refresh(manual: true)

            #expect(store.snapshot.airQuality == nil)
            #expect(store.sectionActivity[.airQuality] == nil)
            #expect(await airQualityProvider.requestedCoordinates().isEmpty)
        }
    }

    @Test
    func airQualityFailureLeavesWeatherIntactAndReportsTheSection() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        let store = DashboardSnapshotStore(
            settingsStore: settingsStore,
            dependencies: makeDependencies(airQualityProvider: FailingAirQualityProvider(), historyStore: InMemoryHistoryStore())
        )
        store.setCurrentLocation(CLLocation(latitude: 60.1699, longitude: 24.9384))

        await store.refresh(manual: true)

        #expect(store.snapshot.weather?.conditionDescription == "Clear")
        #expect(store.snapshot.airQuality == nil)
        #expect(store.sectionActivity[.airQuality]?.message != nil)
        #expect(store.sectionActivity[.airQuality]?.isRefreshing == false)
    }

    @Test
    func turningAirQualityOffClearsTheSnapshot() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        let store = DashboardSnapshotStore(
            settingsStore: settingsStore,
            dependencies: makeDependencies(historyStore: InMemoryHistoryStore())
        )
        store.setCurrentLocation(CLLocation(latitude: 60.1699, longitude: 24.9384))
        await store.refresh(manual: true)
        #expect(store.snapshot.airQuality != nil)

        settingsStore.settings.airQualityEnabled = false

        await waitForSettingsToTakeEffect(store)
        #expect(store.snapshot.airQuality == nil)
        #expect(store.sectionActivity[.airQuality] == nil)
        #expect(store.snapshot.weather != nil)
    }

    @Test
    func turningAirQualityOnRefreshesImmediately() async throws {
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.airQualityEnabled = false
        let airQualityProvider = RecordingAirQualityProvider()
        let store = DashboardSnapshotStore(
            settingsStore: settingsStore,
            dependencies: makeDependencies(airQualityProvider: airQualityProvider, historyStore: InMemoryHistoryStore())
        )
        store.setCurrentLocation(CLLocation(latitude: 60.1699, longitude: 24.9384))
        await store.refresh(manual: true)
        #expect(await airQualityProvider.requestedCoordinates().isEmpty)

        settingsStore.settings.airQualityEnabled = true

        await waitForSettingsToTakeEffect(store)
        #expect(await airQualityProvider.requestedCoordinates().count >= 1)
        #expect(store.snapshot.airQuality != nil)
    }

    @Test
    func staleDeviceLocationIsNotReverseGeocodedOrRecordedAsCurrent() async throws {
        let reverseGeocoder = RecordingReverseGeocodingProvider()
        let dependencies = makeDependencies(
            reverseGeocodingProvider: reverseGeocoder,
            historyStore: InMemoryHistoryStore()
        )
        let settingsStore = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        settingsStore.settings.publicIPGeolocationEnabled = false
        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies)
        let staleLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 60.1699, longitude: 24.9384),
            altitude: 0,
            horizontalAccuracy: 10,
            verticalAccuracy: 10,
            timestamp: Date().addingTimeInterval(-16 * 60)
        )
        store.setCurrentLocation(staleLocation)

        await store.refresh(manual: true)

        #expect(await reverseGeocoder.callCount() == 0)
        #expect(store.snapshot.travelContext.deviceLocation == nil)
        #expect(store.visitedPlaces.isEmpty)
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

        await waitForSettingsToTakeEffect(store)
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

        // The initial settings reach the coordinator first, then the change.
        await updateCoordinator.waitForCalls(1)
        #expect(await updateCoordinator.automaticChecksHistory() == [false])

        settingsStore.settings.automaticUpdateChecksEnabled = true

        await waitForSettingsToTakeEffect(store)
        #expect(await updateCoordinator.automaticChecksHistory() == [false, true])
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

        await waitForSettingsToTakeEffect(store)
        #expect(store.snapshot.network.downloadHistory.count == 1)
        #expect(store.snapshot.network.downloadHistory.first?.value == 22)
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

    // MARK: Synchronisation

    // Nothing here waits for a duration to pass. Each wait ends on the event it names: a stub provider being
    // called, a published store value, or the store registering a settings change. `hangGuard` is the only
    // timeout, and it exists so a test that can never finish fails instead of hanging the whole run.

    /// Fails the test, instead of hanging it, when `operation` has not finished after `timeout`. It is a
    /// safety net for a missed event and never the thing a test relies on to make work happen.
    private func hangGuard(
        _ description: String,
        timeout: Duration = .seconds(10),
        sourceLocation: SourceLocation = #_sourceLocation,
        operation: @escaping @MainActor @Sendable () async -> Void
    ) async {
        let work = Task { @MainActor in await operation() }
        let watchdog = Task { @MainActor () -> Bool in
            do { try await Task.sleep(for: timeout) } catch { return false }
            work.cancel()
            return true
        }
        await work.value
        watchdog.cancel()
        if await watchdog.value {
            Issue.record("Timed out waiting for \(description).", sourceLocation: sourceLocation)
        }
    }

    /// Returns once `condition` holds, re-checking after every published change of the store.
    private func waitForStore(
        _ store: DashboardSnapshotStore,
        _ description: String,
        sourceLocation: SourceLocation = #_sourceLocation,
        until condition: @escaping @MainActor @Sendable () -> Bool
    ) async {
        await hangGuard(description, sourceLocation: sourceLocation) {
            // `objectWillChange.values` cannot be used: the publisher emits without demand, which traps.
            let (changes, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
            let subscription = store.objectWillChange.sink { continuation.yield() }
            defer { subscription.cancel() }
            if condition() {
                return
            }
            // A change is published before it is applied, but this only resumes after the main actor has
            // finished applying it, and a change that lands while waiting wakes the loop again.
            for await _ in changes {
                if condition() {
                    return
                }
            }
        }
    }

    /// Returns once no refresh is running or pending, so every provider call it makes has been made.
    private func waitForIdle(_ store: DashboardSnapshotStore, sourceLocation: SourceLocation = #_sourceLocation) async {
        await waitForStore(store, "the store to become idle", sourceLocation: sourceLocation) {
            store.refreshActivity == .idle
        }
    }

    /// Returns once every settings change made so far is applied and its refresh is registered, while that
    /// refresh may still be running.
    private func waitForSettingsChangesToRegister(_ store: DashboardSnapshotStore, sourceLocation: SourceLocation = #_sourceLocation) async {
        await hangGuard("the settings changes to register", sourceLocation: sourceLocation) {
            await store.waitForSettingsChangesToRegister()
        }
    }

    /// Returns once the settings changes made so far have been applied and the refreshes they caused have
    /// finished.
    private func waitForSettingsToTakeEffect(_ store: DashboardSnapshotStore, sourceLocation: SourceLocation = #_sourceLocation) async {
        await waitForSettingsChangesToRegister(store, sourceLocation: sourceLocation)
        await waitForIdle(store, sourceLocation: sourceLocation)
    }

    /// Waits for explicit join acknowledgements while the original refresh is held open.
    private func waitForRefreshJoins(_ joins: AsyncStream<Void>, count: Int) async {
        await hangGuard("\(count) refresh requests to join the running refresh") {
            var joined = 0
            for await _ in joins {
                joined += 1
                if joined == count {
                    return
                }
            }
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
    airQualityProvider: any AirQualityProvider = FixedAirQualityProvider(),
    neighborCountryResolver: any NeighborCountryResolver = FixedNeighborCountryResolver(),
    travelAdvisoryProvider: any TravelAdvisoryProvider = FixedTravelAdvisoryProvider(),
    travelWeatherAlertsProvider: any TravelWeatherAlertsProvider = FixedTravelWeatherAlertsProvider(),
    regionalSecurityProvider: any RegionalSecurityProvider = FixedRegionalSecurityProvider(),
    tripPreviewService: any TripPreviewService = FixedTripPreviewService(),
    priceLevelIndexProvider: any PriceLevelIndexProvider = FixedPriceLevelIndexProvider(),
    visitedPlacesStore: any VisitedPlacesStore = InMemoryVisitedPlacesStore(),
    visitedPlaceEventsStore: any VisitedPlaceEventsStore = InMemoryVisitedPlaceEventsStore(),
    visitedCountryDaysStore: any VisitedCountryDaysStore = InMemoryVisitedCountryDaysStore(),
    timeZoneShiftStore: any TimeZoneShiftStore = InMemoryTimeZoneShiftStore(),
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
        airQualityProvider: airQualityProvider,
        neighborCountryResolver: neighborCountryResolver,
        travelAdvisoryProvider: travelAdvisoryProvider,
        travelWeatherAlertsProvider: travelWeatherAlertsProvider,
        regionalSecurityProvider: regionalSecurityProvider,
        tripPreviewService: tripPreviewService,
        priceLevelIndexProvider: priceLevelIndexProvider,
        visitedPlacesStore: visitedPlacesStore,
        visitedPlaceEventsStore: visitedPlaceEventsStore,
        visitedCountryDaysStore: visitedCountryDaysStore,
        timeZoneShiftStore: timeZoneShiftStore,
        historyStore: historyStore,
        updateCoordinator: updateCoordinator,
        meteredDataController: MeteredDataController(
            store: MeteredUsageStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("metered-usage-test-\(UUID().uuidString).json"))
        )
    )
}

private actor InMemoryTimeZoneShiftStore: TimeZoneShiftStore {
    private var values: [TimeZoneShiftRecord] = []

    func loadAll() async throws -> [TimeZoneShiftRecord] {
        values
    }

    func record(_ record: TimeZoneShiftRecord) async throws {
        if let latest = values.last, latest.identifier == record.identifier, latest.offsetSeconds == record.offsetSeconds {
            return
        }
        values.append(record)
    }

    func reset() async throws {
        values = []
    }
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

        if let index = values.indices.last, values[index].coalescingKey == event.coalescingKey {
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

/// Counts the events a stub sees and lets a test await the n-th one. Waiting ends when the event happens and
/// also when the waiting task is cancelled, so the hang guard can always end a wait that never completes.
private actor CallRecorder<Value: Sendable> {
    private(set) var values: [Value] = []
    private var waiters: [(count: Int, continuation: AsyncStream<Void>.Continuation)] = []

    func record(_ value: Value) {
        values.append(value)
        let ready = waiters.filter { $0.count <= values.count }
        waiters.removeAll { $0.count <= values.count }
        for waiter in ready {
            waiter.continuation.yield()
            waiter.continuation.finish()
        }
    }

    func waitForCount(_ count: Int) async {
        guard values.count < count else { return }
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        waiters.append((count, continuation))
        for await _ in stream {
            return
        }
    }
}

/// Holds callers until a test lets them through. Opening it also lets every later caller straight through,
/// so a test never has to guess whether the caller has arrived yet. Callers are not released by
/// cancellation, like a provider that ignores it.
private actor Gate {
    private var isOpen: Bool
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(isOpen: Bool) {
        self.isOpen = isOpen
    }

    func pass() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let released = waiters
        waiters = []
        for waiter in released {
            waiter.resume()
        }
    }

    func close() {
        isOpen = false
    }
}

/// A throughput monitor whose samples a test can hold open, so a refresh stays in its local metrics phase for
/// exactly as long as the test needs.
private final class GatedThroughputMonitor: ThroughputMonitor, Sendable {
    private let calls = CallRecorder<Void>()
    private let gate: Gate

    init(isHeld: Bool = true) {
        gate = Gate(isOpen: !isHeld)
    }

    func currentSample() async -> NetworkThroughputSample? {
        await calls.record(())
        await gate.pass()
        return await FixedThroughputMonitor().currentSample()
    }

    /// Returns once the monitor has been asked for its `number`-th sample.
    func waitForCall(_ number: Int) async {
        await calls.waitForCount(number)
    }

    func callCount() async -> Int {
        await calls.values.count
    }

    /// Holds the samples asked for from now on.
    func hold() async {
        await gate.close()
    }

    /// Lets the held samples, and all later ones, through.
    func release() async {
        await gate.open()
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

/// Reports readings with chosen timestamps instead of the time they were taken, so freshness and ordering
/// never depend on how long the test took to get from one probe to the next.
private actor SequencedLatencyProbe: LatencyProbe {
    private let firstReading: Date
    private let interval: TimeInterval
    private var calls = 0

    init(firstReadingAge: TimeInterval, interval: TimeInterval) {
        firstReading = Date().addingTimeInterval(-firstReadingAge)
        self.interval = interval
    }

    func currentSample() async -> LatencySample? {
        defer { calls += 1 }
        return LatencySample(
            host: "1.1.1.1",
            milliseconds: 22,
            jitterMilliseconds: 2,
            collectedAt: firstReading.addingTimeInterval(Double(calls) * interval)
        )
    }

    func callCount() -> Int {
        calls
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

private final class GatedPublicIPProvider: PublicIPProvider, Sendable {
    private let calls = CallRecorder<Void>()
    private let gate = Gate(isOpen: false)

    func currentIP(forceRefresh: Bool) async throws -> PublicIPSnapshot {
        await calls.record(())
        await gate.pass()
        return try await FixedPublicIPProvider().currentIP(forceRefresh: forceRefresh)
    }

    func callCount() async -> Int {
        await calls.values.count
    }

    func release() async {
        await gate.open()
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

private actor RecordingReverseGeocodingProvider: ReverseGeocodingProvider {
    private var calls = 0

    func details(for location: CLLocation) async throws -> ReverseGeocodedLocation {
        calls += 1
        return try await FixedReverseGeocodingProvider().details(for: location)
    }

    func callCount() -> Int {
        calls
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

private struct FixedPriceLevelIndexProvider: PriceLevelIndexProvider {
    var indices: [String: [LocalPriceIndicatorKind: Double]] = [:]
    var failing = false

    func indices(forCountryCode countryCode: String) async throws -> [LocalPriceIndicatorKind: Double] {
        if failing {
            throw ProviderError.missingCountryCode
        }
        return indices[countryCode] ?? [:]
    }
}

/// Records the home country of every local info request.
private actor RecordingHomeCountryLocalInfoProvider: LocalInfoProvider {
    private let requests = CallRecorder<String?>()

    func info(for request: LocalInfoRequest, forceRefresh: Bool) async throws -> LocalInfoSnapshot {
        await requests.record(request.homeCountryCode)
        return LocalInfoSnapshot(
            status: .partial,
            locality: request.locality,
            administrativeRegion: request.administrativeRegion,
            countryCode: request.countryCode,
            countryName: request.countryName,
            timeZoneIdentifier: request.timeZoneIdentifier,
            subdivisionCode: nil,
            publicHolidayStatus: LocalHolidayStatus(state: .unavailable, currentPeriod: nil, nextPeriod: nil, note: nil),
            schoolHolidayStatus: nil,
            localPriceLevel: nil,
            sources: [],
            fetchedAt: .now,
            detail: nil,
            note: nil
        )
    }

    func requestedHomeCountryCodes() async -> [String?] {
        await requests.values
    }

    /// Returns once the provider has been asked for local info `count` times.
    func waitForRequests(_ count: Int) async {
        await requests.waitForCount(count)
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

private actor RecordingWeatherProvider: WeatherProvider {
    var requests: [Bool] = []

    func weather(for coordinate: CLLocationCoordinate2D?) async throws -> WeatherSnapshot {
        try await weather(for: coordinate, forceRefresh: false)
    }

    func weather(for coordinate: CLLocationCoordinate2D?, forceRefresh: Bool) async throws -> WeatherSnapshot {
        requests.append(forceRefresh)
        if forceRefresh {
            throw ProviderError.invalidResponse
        }
        return try await FixedWeatherProvider().weather(for: coordinate)
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

private struct FixedAirQualityProvider: AirQualityProvider {
    func airQuality(for coordinate: CLLocationCoordinate2D) async throws -> AirQualitySnapshot {
        AirQualitySnapshot(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            sourceName: "Open-Meteo",
            europeanAQI: 42,
            mainPollutant: .pm2_5,
            pm2_5: 14,
            pm10: 22,
            ozone: 60,
            nitrogenDioxide: 12,
            forecastSlots: [],
            fetchedAt: .now
        )
    }
}

private actor RecordingAirQualityProvider: AirQualityProvider {
    private var coordinates: [CLLocationCoordinate2D] = []

    func airQuality(for coordinate: CLLocationCoordinate2D) async throws -> AirQualitySnapshot {
        coordinates.append(coordinate)
        return try await FixedAirQualityProvider().airQuality(for: coordinate)
    }

    func requestedCoordinates() -> [CLLocationCoordinate2D] {
        coordinates
    }
}

private struct FailingAirQualityProvider: AirQualityProvider {
    func airQuality(for coordinate: CLLocationCoordinate2D) async throws -> AirQualitySnapshot {
        throw ProviderError.invalidResponse
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
    private let history = CallRecorder<Bool>()

    func currentState() async -> UpdateStateSnapshot {
        UpdateStateSnapshot(kind: .idle, detail: "Testing", lastCheckedAt: nil)
    }

    func checkForUpdates() async {}

    func setAutomaticChecksEnabled(_ isEnabled: Bool) async {
        await history.record(isEnabled)
    }

    func automaticChecksHistory() async -> [Bool] {
        await history.values
    }

    /// Returns once the automatic update checks setting has been handed over `count` times.
    func waitForCalls(_ count: Int) async {
        await history.waitForCount(count)
    }
}

private actor HeldWeatherProvider: WeatherProvider {
    private let calls = CallRecorder<Void>()
    private let gate = Gate(isOpen: false)

    /// Returns once the provider has been asked for weather and is holding the request.
    func waitUntilStarted() async {
        await calls.waitForCount(1)
    }

    func weather(for coordinate: CLLocationCoordinate2D?) async throws -> WeatherSnapshot {
        await calls.record(())
        await gate.pass()
        return try await FixedWeatherProvider().weather(for: coordinate)
    }

    func release() async {
        await gate.open()
    }
}
