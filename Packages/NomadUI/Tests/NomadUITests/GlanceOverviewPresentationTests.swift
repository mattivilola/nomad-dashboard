import Foundation
@testable import NomadCore
@testable import NomadUI
import Testing

struct GlanceOverviewPresentationTests {
    // MARK: Header

    @Test
    func headerHeadlineIsTheDeviceCityWithDetailVariantsFromLongToShort() {
        let presentation = DashboardHeaderPresentation(
            deviceLocation: makeLocation(city: "Saint-Jean-de-Luz", region: "Nouvelle-Aquitaine", country: "France"),
            ipLocation: makeLocation(city: "Paris", region: "Île-de-France", country: "France")
        )

        #expect(presentation.headline == "Saint-Jean-de-Luz")
        #expect(presentation.detailVariants == [
            .init(device: "Nouvelle-Aquitaine, France", ip: "Paris, France"),
            .init(device: "France", ip: "Paris, France"),
            .init(device: "France", ip: "Paris")
        ])
    }

    @Test
    func headerHeadlineFallsBackToIPCityAndShowsOnlyTheIPPart() {
        let presentation = DashboardHeaderPresentation(
            deviceLocation: nil,
            ipLocation: makeLocation(city: "Lisbon", country: "Portugal")
        )

        #expect(presentation.headline == "Lisbon")
        #expect(presentation.detailVariants == [
            .init(device: nil, ip: "Lisbon, Portugal"),
            .init(device: nil, ip: "Lisbon")
        ])
    }

    @Test
    func headerHeadlineFallsBackToGenericTextWithoutAnyLocation() {
        let presentation = DashboardHeaderPresentation(deviceLocation: nil, ipLocation: nil)

        #expect(presentation.headline == DashboardHeaderPresentation.fallbackHeadline)
        #expect(presentation.detailVariants.isEmpty)
    }

    @Test
    func headerDetailVariantsSkipPartsThatRepeatTheCityAndCollapseDuplicates() {
        let presentation = DashboardHeaderPresentation(
            deviceLocation: makeLocation(city: "Singapore", region: "Singapore", country: "Singapore"),
            ipLocation: makeLocation(city: "Singapore", country: "Singapore")
        )

        #expect(presentation.headline == "Singapore")
        #expect(presentation.detailVariants == [
            .init(device: nil, ip: "Singapore, Singapore"),
            .init(device: nil, ip: "Singapore")
        ])
    }

    @Test
    func headerDetailVariantsWithoutRegionStartAtTheCountry() {
        let presentation = DashboardHeaderPresentation(
            deviceLocation: makeLocation(city: "Tbilisi", country: "Georgia"),
            ipLocation: makeLocation(city: "Frankfurt", country: "Germany")
        )

        #expect(presentation.detailVariants == [
            .init(device: "Georgia", ip: "Frankfurt, Germany"),
            .init(device: "Georgia", ip: "Frankfurt")
        ])
    }

    @Test
    func headerIgnoresBlankLocationParts() {
        let presentation = DashboardHeaderPresentation(
            deviceLocation: makeLocation(city: "  ", region: nil, country: "Spain"),
            ipLocation: makeLocation(city: "Madrid", country: " ")
        )

        #expect(presentation.headline == "Madrid")
        #expect(presentation.detailVariants == [.init(device: "Spain", ip: "Madrid")])
    }

    // MARK: Verdict

    @Test
    func verdictReportsOfflineRegardlessOfHealth() {
        let verdict = GlanceVerdictPresentation(snapshot: makeSnapshot(), isOffline: true)

        #expect(verdict.title == "You're offline")
        #expect(verdict.detail == "Saved essentials are available")
        #expect(verdict.symbolName == "wifi.slash")
        #expect(verdict.level == .caution)
    }

    @Test
    func verdictOfflineDetectionUsesPolicyOrInternetState() {
        let online = makeSnapshot()
        let offline = makeSnapshot(internetState: .offline)

        #expect(GlanceVerdictPresentation.isOffline(snapshot: online, policy: .normal) == false)
        #expect(GlanceVerdictPresentation.isOffline(snapshot: offline, policy: .normal))
    }

    @Test
    func verdictIsReadyToWorkWithNetworkReasonAndVPN() {
        let plain = GlanceVerdictPresentation(snapshot: makeSnapshot(), isOffline: false)
        let withVPN = GlanceVerdictPresentation(snapshot: makeSnapshot(vpnActive: true), isOffline: false)

        #expect(plain.title == "Ready to work")
        #expect(plain.detail == "Stable on en0")
        #expect(plain.level == .ready)
        #expect(withVPN.detail == "Stable on en0 · VPN on")
    }

    @Test
    func verdictIsWorkableWithTheOverallReasonOnCaution() {
        let verdict = GlanceVerdictPresentation(snapshot: makeSnapshot(latencyMilliseconds: 80), isOffline: false)

        #expect(verdict.title == "Workable")
        #expect(verdict.detail == "Network: Latency 80 ms")
        #expect(verdict.level == .caution)
    }

    @Test
    func verdictNeedsAttentionWithTheOverallReason() {
        let verdict = GlanceVerdictPresentation(snapshot: makeSnapshot(latencyMilliseconds: 200), isOffline: false)

        #expect(verdict.title == "Needs attention")
        #expect(verdict.detail == "Network: Latency 200 ms")
        #expect(verdict.level == .attention)
    }

    @Test
    func verdictIsCheckingWhileConditionsAreUnknown() {
        let verdict = GlanceVerdictPresentation(snapshot: makeSnapshot(latencyMilliseconds: nil), isOffline: false)

        #expect(verdict.title == "Checking conditions")
        #expect(verdict.level == .unavailable)
    }

    // MARK: Clocks

    @Test
    func hereCityPrefersTheDeviceCityOverTheTimeZoneCity() {
        let device = makeLocation(city: "Saint-Jean-de-Luz", country: "France")

        #expect(GlanceClockPresentation.hereCity(deviceLocation: device, timeZoneIdentifier: "Europe/Paris") == "Saint-Jean-de-Luz")
        #expect(GlanceClockPresentation.hereCity(deviceLocation: nil, timeZoneIdentifier: "America/Los_Angeles") == "Los Angeles")
        #expect(GlanceClockPresentation.hereCity(deviceLocation: makeLocation(city: " "), timeZoneIdentifier: "Europe/Paris") == "Paris")
    }

    // MARK: Internet and power tiles

    @Test
    func internetTileShowsLatencyThroughputAndNetworkName() {
        let tile = GlanceVitalTilePresentation.internet(
            snapshot: makeSnapshot(ssid: "Cafe Wifi", downloadMegabits: 2, uploadMegabits: 0.5),
            isOffline: false
        )

        #expect(tile.title == "Internet")
        #expect(tile.titleDetail == "Cafe Wifi")
        #expect(tile.value == "20 ms")
        #expect(tile.secondary == "2.0 ↓ · 0.5 ↑ Mbps")
        #expect(tile.level == .ready)
        #expect(tile.scrollTarget == .connectivity)
    }

    @Test
    func internetTileFallsBackToTheInterfaceName() {
        let tile = GlanceVitalTilePresentation.internet(snapshot: makeSnapshot(), isOffline: false)

        #expect(tile.titleDetail == "en0")
    }

    @Test
    func internetTileShowsWaitingBeforeTheFirstLatencySample() {
        let tile = GlanceVitalTilePresentation.internet(snapshot: makeSnapshot(latencyMilliseconds: nil), isOffline: false)

        #expect(tile.value == "Waiting")
        #expect(tile.level == nil)
    }

    @Test
    func internetTileShowsOfflineAsAttention() {
        let tile = GlanceVitalTilePresentation.internet(snapshot: makeSnapshot(internetState: .offline), isOffline: true)

        #expect(tile.value == "Offline")
        #expect(tile.level == .attention)
        #expect(tile.secondary == "No network route")
    }

    @Test
    func powerTileShowsChargeAndSummaryWithHealthTone() {
        let onBattery = GlanceVitalTilePresentation.power(snapshot: makeSnapshot(power: makeGlancePower(state: .battery, charge: 0.72, minutes: 150)))
        let lowBattery = GlanceVitalTilePresentation.power(snapshot: makeSnapshot(power: makeGlancePower(state: .battery, charge: 0.1, minutes: 20)))
        let charging = GlanceVitalTilePresentation.power(snapshot: makeSnapshot(power: makeGlancePower(state: .charging, charge: 0.5, toFull: 13)))

        #expect(onBattery.value == "72%")
        #expect(onBattery.secondary == "2h 30m left")
        #expect(onBattery.scrollTarget == .power)
        #expect(lowBattery.level == .attention)
        #expect(charging.secondary == "Charging · 13m to full")
        #expect(charging.level == .ready)
    }

    @Test
    func powerTileHandlesMissingBatteryData() {
        let tile = GlanceVitalTilePresentation.power(snapshot: makeSnapshot(power: nil))

        #expect(tile.value == "—")
        #expect(tile.secondary == "Estimating")
        #expect(tile.level == nil)
    }

    // MARK: Data and VPN tiles

    @Test
    func dataTileShowsUsageAgainstTheCapWithProgress() {
        let metered = makeMetered(monitoring: true, usedBytes: 500_000_000, capBytes: 1_000_000_000, fraction: 0.5)
        let tile = GlanceVitalTilePresentation.dataOrVPN(snapshot: makeSnapshot(metered: metered))

        #expect(tile.kind == .data)
        #expect(tile.value == "\(MeteredUsageFormatting.byteCount(500_000_000)) / \(MeteredUsageFormatting.byteCount(1_000_000_000))")
        #expect(tile.progress == 0.5)
        #expect(tile.secondary == "Pixel Hotspot")
        #expect(tile.level == .ready)
        #expect(tile.scrollTarget == .meteredData)
    }

    @Test
    func dataTileShowsOnlyUsageWithoutACap() {
        let metered = makeMetered(monitoring: true, usedBytes: 250_000_000, capBytes: nil, fraction: nil)
        let tile = GlanceVitalTilePresentation.dataOrVPN(snapshot: makeSnapshot(metered: metered))

        #expect(tile.value == MeteredUsageFormatting.byteCount(250_000_000))
        #expect(tile.progress == nil)
    }

    @Test
    func dataTileToneFollowsTheCapThresholds() {
        func level(_ fraction: Double, reached: Bool = false) -> HealthLevel {
            makeMetered(monitoring: true, usedBytes: 0, capBytes: 100, fraction: fraction, capReached: reached).usageLevel
        }

        #expect(level(0.79) == .ready)
        #expect(level(0.8) == .caution)
        #expect(level(0.99) == .caution)
        #expect(level(1.0) == .attention)
        #expect(level(0.5, reached: true) == .attention)
    }

    @Test
    func dataTileClampsProgressAtTheCap() {
        let metered = makeMetered(monitoring: true, usedBytes: 1_200, capBytes: 1_000, fraction: 1.2)
        let tile = GlanceVitalTilePresentation.dataOrVPN(snapshot: makeSnapshot(metered: metered))

        #expect(tile.progress == 1)
        #expect(tile.level == .attention)
    }

    @Test
    func dataTileUsesTheSessionOrPeriodTotalForTheBillingPeriod() {
        let session = makeMetered(monitoring: true, usedBytes: 100, capBytes: nil, fraction: nil, period: .session)
        let month = makeMetered(monitoring: true, usedBytes: 100, capBytes: nil, fraction: nil, period: .calendarMonth)

        #expect(session.usedBytes == 100)
        #expect(month.usedBytes == 100)
    }

    @Test
    func dataTileShowsUnmeteredWhenEnabledButNotMonitoring() {
        let metered = makeMetered(monitoring: false, usedBytes: 0, capBytes: nil, fraction: nil)
        let tile = GlanceVitalTilePresentation.dataOrVPN(snapshot: makeSnapshot(metered: metered))

        #expect(tile.kind == .data)
        #expect(tile.value == "Unmetered")
        #expect(tile.level == nil)
        #expect(tile.secondary == "Pixel Hotspot")
        #expect(tile.progress == nil)
    }

    @Test
    func vpnTileReplacesDataWhenDataGuardIsDisabled() {
        let active = GlanceVitalTilePresentation.dataOrVPN(
            snapshot: makeSnapshot(vpnActive: true, ipLocation: makeLocation(city: "Zurich", country: "Switzerland"))
        )
        let inactive = GlanceVitalTilePresentation.dataOrVPN(snapshot: makeSnapshot(vpnActive: false))

        #expect(active.kind == .vpn)
        #expect(active.value == "On")
        #expect(active.secondary == "Zurich")
        #expect(active.level == .ready)
        #expect(active.scrollTarget == .travelContext)
        #expect(inactive.value == "Off")
        #expect(inactive.level == nil)
    }

    // MARK: Weather tile

    @Test
    func weatherTileShowsTemperatureConditionSymbolAndTodaysRange() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let weather = makeWeather(today: now)
        let tile = GlanceVitalTilePresentation.weather(snapshot: makeSnapshot(weather: weather), weatherAvailabilityExplanation: nil, now: now)

        #expect(tile.value == "18°")
        #expect(tile.valueSymbolName == "cloud.sun.fill")
        #expect(tile.secondary == "Partly Cloudy · 12° / 24°")
        #expect(tile.level == nil)
        #expect(tile.scrollTarget == .weather)
    }

    @Test
    func weatherTileDoesNotRepeatRainOrWindHeadsUp() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let weather = makeWeather(
            hourly: [makeSlot(now.addingTimeInterval(3_600), rain: 0.9)],
            windKph: 70,
            windDegrees: 270
        )

        #expect(GlanceVitalTilePresentation.weatherSecondary(weather, now: now) == "Partly Cloudy")
    }

    @Test
    func weatherTileUsesOnlyTheConditionWhenTodaysRangeIsUnknown() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let otherDay = makeWeather(today: now.addingTimeInterval(3 * 86_400))

        #expect(GlanceVitalTilePresentation.weatherSecondary(otherDay, now: now) == "Partly Cloudy")
    }

    @Test
    func weatherTileFallsBackToTomorrowWithoutACondition() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(GlanceVitalTilePresentation.weatherSecondary(makeWeather(condition: " "), now: now) == "Tomorrow · Sunny")
        #expect(GlanceVitalTilePresentation.weatherSecondary(makeWeather(condition: " ", includesTomorrow: false), now: now) == "Unavailable")
    }

    @Test
    func weatherTileExplainsWhyWeatherIsUnavailable() {
        let plain = GlanceVitalTilePresentation.weather(snapshot: makeSnapshot(), weatherAvailabilityExplanation: nil)
        let location = GlanceVitalTilePresentation.weather(snapshot: makeSnapshot(issues: [.weatherLocationRequired]), weatherAvailabilityExplanation: nil)
        let build = GlanceVitalTilePresentation.weather(snapshot: makeSnapshot(), weatherAvailabilityExplanation: "Missing entitlement")

        #expect(plain.value == "—")
        #expect(plain.secondary == "Unavailable")
        #expect(location.secondary == "Location needed")
        #expect(build.secondary == "WeatherKit unavailable")
    }

    @Test
    func tilesAreOrderedInternetPowerDataWeather() {
        let tiles = GlanceVitalTilePresentation.tiles(snapshot: makeSnapshot(), isOffline: false, weatherAvailabilityExplanation: nil)

        #expect(tiles.map(\.kind) == [.internet, .power, .vpn, .weather])
    }

    // MARK: Heads-up

    @Test
    func headsUpRowTintFollowsInsightSeverity() {
        #expect(GlanceHeadsUpRowPresentation.level(for: .attention) == .attention)
        #expect(GlanceHeadsUpRowPresentation.level(for: .caution) == .caution)
        #expect(GlanceHeadsUpRowPresentation.level(for: .info) == .ready)
        #expect(HealthLevel.attention.tint == NomadTheme.coral)
        #expect(HealthLevel.caution.tint == NomadTheme.sand)
        #expect(HealthLevel.ready.tint == NomadTheme.teal)
    }

    @Test
    func headsUpRowKeepsInsightContentAndExplainsItsTarget() {
        let insight = DashboardInsight(
            kind: .dataCap,
            severity: .caution,
            symbolName: "arrow.up.arrow.down.circle",
            title: "Data cap at 85%",
            detail: "850 MB of 1 GB used",
            relatedCard: .meteredData
        )
        let row = GlanceHeadsUpRowPresentation(insight: insight)

        #expect(row.id == .dataCap)
        #expect(row.title == "Data cap at 85%")
        #expect(row.detail == "850 MB of 1 GB used")
        #expect(row.relatedCard == .meteredData)
        #expect(row.accessibilityHint == "Shows the Data Guard card")
    }

    @Test
    func everyCardHasADisplayTitle() {
        #expect(DashboardCardID.allCases.allSatisfy { $0.displayTitle.isEmpty == false })
    }
}

// MARK: - Fixtures

private func makeLocation(
    city: String? = nil,
    region: String? = nil,
    country: String? = nil
) -> IPLocationSnapshot {
    IPLocationSnapshot(
        city: city,
        region: region,
        country: country,
        countryCode: nil,
        latitude: nil,
        longitude: nil,
        timeZone: nil,
        provider: "test",
        fetchedAt: .now
    )
}

private func makeGlancePower(
    state: PowerSourceState,
    charge: Double,
    minutes: Int? = nil,
    toFull: Int? = nil
) -> PowerSnapshot {
    PowerSnapshot(
        chargePercent: charge,
        state: state,
        timeRemainingMinutes: minutes,
        timeToFullChargeMinutes: toFull,
        isLowPowerModeEnabled: false,
        dischargeRateWatts: nil,
        adapterWatts: nil,
        collectedAt: .now
    )
}

private func makeMetered(
    monitoring: Bool,
    usedBytes: UInt64,
    capBytes: UInt64?,
    fraction: Double?,
    capReached: Bool = false,
    period: MeteredBillingPeriod = .session
) -> MeteredUsageSnapshot {
    MeteredUsageSnapshot(
        isFeatureEnabled: true,
        isMonitoringActive: monitoring,
        networkKey: "wifi:Pixel Hotspot",
        networkDisplayName: "Pixel Hotspot",
        meteredInterfaceName: "en0",
        sessionStartedAt: nil,
        sessionBytesReceived: usedBytes,
        sessionBytesSent: 0,
        periodBytesReceived: usedBytes,
        periodBytesSent: 0,
        capBytes: capBytes,
        usageFraction: fraction,
        isCapReached: capReached,
        billingPeriod: period,
        manualSessionEnabled: monitoring,
        isKnownMeteredNetwork: monitoring,
        networkNameSource: .liveSSID,
        isWiFiConnected: true,
        needsLocationForWiFiNames: false,
        statusMessage: nil,
        capAlertSignal: nil
    )
}

private func makeSlot(_ date: Date, rain: Double) -> WeatherHourlyForecastSlot {
    WeatherHourlyForecastSlot(
        date: date,
        symbolName: "cloud.rain",
        conditionDescription: "Rain",
        temperatureCelsius: 15,
        precipitationChance: rain,
        windSpeedKph: nil,
        windDirectionDegrees: nil
    )
}

private func makeWeather(
    hourly: [WeatherHourlyForecastSlot] = [],
    windKph: Double? = nil,
    windDegrees: Double? = nil,
    condition: String = "Partly Cloudy",
    today: Date? = nil,
    includesTomorrow: Bool = true
) -> WeatherSnapshot {
    var days: [WeatherDaySummary] = []
    if let today {
        days.append(WeatherDaySummary(
            date: today,
            symbolName: "cloud.sun.fill",
            summary: "Partly Cloudy",
            temperatureMinCelsius: 12,
            temperatureMaxCelsius: 24,
            precipitationChance: 0
        ))
    }
    let tomorrow = includesTomorrow
        ? WeatherDaySummary(
            date: .now,
            symbolName: "sun.max.fill",
            summary: "Sunny",
            temperatureMinCelsius: 12,
            temperatureMaxCelsius: 22,
            precipitationChance: 0
        )
        : nil

    return WeatherSnapshot(
        currentTemperatureCelsius: 18,
        apparentTemperatureCelsius: 17,
        conditionDescription: condition,
        symbolName: "cloud.sun.fill",
        precipitationChance: 0.1,
        windSpeedKph: windKph,
        windDirectionDegrees: windDegrees,
        hourlyForecastSlots: hourly,
        dailyForecast: days,
        tomorrow: tomorrow,
        fetchedAt: .now
    )
}

private func makeSnapshot(
    internetState: InternetReachabilityState = .online,
    latencyMilliseconds: Double? = 20,
    ssid: String? = nil,
    downloadMegabits: Double = 2,
    uploadMegabits: Double = 0.5,
    power: PowerSnapshot? = makeGlancePower(state: .charged, charge: 1),
    vpnActive: Bool = false,
    ipLocation: IPLocationSnapshot? = nil,
    weather: WeatherSnapshot? = nil,
    metered: MeteredUsageSnapshot = .disabled,
    issues: [DashboardIssue] = []
) -> DashboardSnapshot {
    DashboardSnapshot(
        network: NetworkSectionSnapshot(
            throughput: NetworkThroughputSample(
                downloadBytesPerSecond: downloadMegabits * 1_000_000 / 8,
                uploadBytesPerSecond: uploadMegabits * 1_000_000 / 8,
                activeInterface: "en0",
                collectedAt: .now
            ),
            connectivity: ConnectivitySnapshot(pathAvailable: internetState != .offline, internetState: internetState, lastCheckedAt: .now),
            latency: latencyMilliseconds.map {
                LatencySample(host: "1.1.1.1", milliseconds: $0, jitterMilliseconds: nil, collectedAt: .now)
            },
            downloadHistory: [],
            uploadHistory: [],
            latencyHistory: []
        ),
        power: PowerSectionSnapshot(snapshot: power, chargeHistory: [], dischargeHistory: []),
        travelContext: TravelContextSnapshot(
            wifi: ssid.map { WiFiSnapshot(interfaceName: "en0", ssid: $0, rssi: -50, noise: nil, transmitRateMbps: nil) },
            vpn: VPNStatusSnapshot(isActive: vpnActive, interfaceNames: []),
            timeZoneIdentifier: "Europe/Paris",
            deviceLocation: nil,
            publicIP: nil,
            location: ipLocation
        ),
        weather: weather,
        appState: AppStatusSnapshot(lastRefresh: .now, updateState: .idle, issues: issues),
        meteredData: metered
    )
}
