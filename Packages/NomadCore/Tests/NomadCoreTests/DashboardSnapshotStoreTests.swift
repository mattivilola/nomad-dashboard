import CoreLocation
import Foundation
import NomadCore
import Testing

@MainActor
struct DashboardSnapshotStoreTests {
    @Test
    func refreshBuildsSnapshotFromDependencies() async throws {
        let settingsStore = AppSettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        settingsStore.settings.publicIPGeolocationEnabled = true

        let historyStore = InMemoryHistoryStore()
        let dependencies = DashboardDependencies(
            throughputMonitor: FixedThroughputMonitor(),
            latencyProbe: FixedLatencyProbe(),
            powerMonitor: FixedPowerMonitor(),
            wifiMonitor: FixedWiFiMonitor(),
            vpnStatusProvider: FixedVPNProvider(),
            publicIPProvider: FixedPublicIPProvider(),
            publicIPLocationProvider: FixedLocationProvider(),
            weatherProvider: FixedWeatherProvider(),
            historyStore: historyStore,
            updateCoordinator: NoopUpdateCoordinator()
        )

        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies)
        store.setWeatherCoordinate(CLLocationCoordinate2D(latitude: 60.1699, longitude: 24.9384))

        await store.refresh(manual: true)

        #expect(store.snapshot.travelContext.publicIP?.address == "198.51.100.12")
        #expect(store.snapshot.travelContext.location?.country == "Finland")
        #expect(store.snapshot.weather?.conditionDescription == "Clear")
        #expect(store.snapshot.network.downloadHistory.isEmpty == false)
        #expect(store.snapshot.healthSummary.overall.level == .ready)
    }

    @Test
    func refreshMarksWeatherLocationRequirementWhenCoordinateIsMissing() async throws {
        let settingsStore = AppSettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let dependencies = DashboardDependencies(
            throughputMonitor: FixedThroughputMonitor(),
            latencyProbe: FixedLatencyProbe(),
            powerMonitor: FixedPowerMonitor(),
            wifiMonitor: FixedWiFiMonitor(),
            vpnStatusProvider: FixedVPNProvider(),
            publicIPProvider: FixedPublicIPProvider(),
            publicIPLocationProvider: FixedLocationProvider(),
            weatherProvider: MissingCoordinateWeatherProvider(),
            historyStore: InMemoryHistoryStore(),
            updateCoordinator: NoopUpdateCoordinator()
        )

        let store = DashboardSnapshotStore(settingsStore: settingsStore, dependencies: dependencies)

        await store.refresh(manual: true)

        #expect(store.snapshot.weather == nil)
        #expect(store.snapshot.appState.issues.contains(.weatherLocationRequired))
    }

    @Test
    func settingsChangesPropagateAutomaticUpdateChecks() async throws {
        let settingsStore = AppSettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        settingsStore.settings.automaticUpdateChecksEnabled = false
        let updateCoordinator = RecordingUpdateCoordinator()
        let dependencies = DashboardDependencies(
            throughputMonitor: FixedThroughputMonitor(),
            latencyProbe: FixedLatencyProbe(),
            powerMonitor: FixedPowerMonitor(),
            wifiMonitor: FixedWiFiMonitor(),
            vpnStatusProvider: FixedVPNProvider(),
            publicIPProvider: FixedPublicIPProvider(),
            publicIPLocationProvider: FixedLocationProvider(),
            weatherProvider: FixedWeatherProvider(),
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
        let settingsStore = AppSettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
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

        let dependencies = DashboardDependencies(
            throughputMonitor: NilThroughputMonitor(),
            latencyProbe: FixedLatencyProbe(),
            powerMonitor: FixedPowerMonitor(),
            wifiMonitor: FixedWiFiMonitor(),
            vpnStatusProvider: FixedVPNProvider(),
            publicIPProvider: FixedPublicIPProvider(),
            publicIPLocationProvider: FixedLocationProvider(),
            weatherProvider: FixedWeatherProvider(),
            historyStore: seededHistoryStore,
            updateCoordinator: NoopUpdateCoordinator()
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
