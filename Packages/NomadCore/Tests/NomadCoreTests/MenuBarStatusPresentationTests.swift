import Foundation
import NomadCore
import Testing

struct MenuBarStatusPresentationTests {
    @Test
    func batteryBelowFiftyWinsOverOtherSignals() {
        let presentation = makeSnapshot(chargePercent: 0.49, latency: 28, weather: makeWeather()).menuBarStatusPresentation

        #expect(presentation.text == "49%")
        #expect(presentation.symbolName == "battery.50percent")
        #expect(presentation.branch == .battery)
    }

    @Test
    func batteryAtFiftyStillUsesBatteryBranch() {
        let presentation = makeSnapshot(chargePercent: 0.5, latency: 88, weather: makeWeather()).menuBarStatusPresentation

        #expect(presentation.text == "50%")
        #expect(presentation.symbolName == "battery.50percent")
        #expect(presentation.branch == .battery)
    }

    @Test
    func cautionLatencyBeatsWeatherAboveFiftyPercent() {
        let presentation = makeSnapshot(chargePercent: 0.51, latency: 88, weather: makeWeather()).menuBarStatusPresentation

        #expect(presentation.text == "88 ms")
        #expect(presentation.symbolName == "wifi")
        #expect(presentation.branch == .latencyCaution)
        #expect(presentation.tone == .standard)
    }

    @Test
    func attentionLatencyUsesExclamationIcon() {
        let presentation = makeSnapshot(chargePercent: 0.51, latency: 130, weather: makeWeather()).menuBarStatusPresentation

        #expect(presentation.text == "130 ms")
        #expect(presentation.symbolName == "wifi.exclamationmark")
        #expect(presentation.branch == .latencyAttention)
        #expect(presentation.tone == .standard)
    }

    @Test
    func weatherWinsWhenBatteryIsHealthyAndLatencyIsGood() {
        let presentation = makeSnapshot(chargePercent: 0.51, latency: 28, weather: makeWeather()).menuBarStatusPresentation

        #expect(presentation.text == "22°")
        #expect(presentation.symbolName == "sun.max.fill")
        #expect(presentation.branch == .weather)
    }

    @Test
    func offlineWinsOverLatencyAndWeather() {
        let presentation = makeSnapshot(
            chargePercent: 0.51,
            connectivity: ConnectivitySnapshot(pathAvailable: true, internetState: .offline, lastCheckedAt: .now),
            latency: 28,
            weather: makeWeather()
        ).menuBarStatusPresentation

        #expect(presentation.text == nil)
        #expect(presentation.symbolName == "wifi.slash")
        #expect(presentation.branch == .offline)
        #expect(presentation.tone == .attention)
    }

    @Test
    func batteryStillWinsOverOffline() {
        let presentation = makeSnapshot(
            chargePercent: 0.49,
            connectivity: ConnectivitySnapshot(pathAvailable: true, internetState: .offline, lastCheckedAt: .now),
            latency: 28,
            weather: makeWeather()
        ).menuBarStatusPresentation

        #expect(presentation.text == "49%")
        #expect(presentation.symbolName == "battery.50percent")
        #expect(presentation.branch == .battery)
        #expect(presentation.tone == .standard)
    }

    @Test
    func latencyFallsBackWhenWeatherIsUnavailable() {
        let presentation = makeSnapshot(chargePercent: 0.51, latency: 28, weather: nil).menuBarStatusPresentation

        #expect(presentation.text == "28 ms")
        #expect(presentation.symbolName == "wifi")
        #expect(presentation.branch == .latencyFallback)
    }

    @Test
    func nonLatencyNetworkIssuesDoNotBlockWeather() {
        let presentation = makeSnapshot(
            chargePercent: 0.51,
            latency: 28,
            weather: makeWeather(),
            rssi: -78,
            issues: [.publicIPLookupUnavailable]
        ).menuBarStatusPresentation

        #expect(presentation.text == "22°")
        #expect(presentation.symbolName == "sun.max.fill")
        #expect(presentation.branch == .weather)
    }

    @Test
    func cautionHeadsUpBeatsLatencyAndWeather() {
        let presentation = makeSnapshot(chargePercent: 0.9, latency: 130, weather: makeWeather())
            .menuBarStatusPresentation(showMeteredUsage: false, headsUp: makeHeadsUp(severity: .caution))

        #expect(presentation.text == "Wind 45")
        #expect(presentation.symbolName == "wind")
        #expect(presentation.branch == .headsUp)
        #expect(presentation.tone == .standard)
    }

    @Test
    func attentionHeadsUpUsesAttentionTone() {
        let presentation = makeSnapshot(chargePercent: 0.9, latency: 28, weather: makeWeather())
            .menuBarStatusPresentation(showMeteredUsage: false, headsUp: makeHeadsUp(severity: .attention))

        #expect(presentation.text == "Wind 45")
        #expect(presentation.branch == .headsUp)
        #expect(presentation.tone == .attention)
    }

    @Test
    func infoHeadsUpIsIgnored() {
        let snapshot = makeSnapshot(chargePercent: 0.49, latency: 28, weather: makeWeather())
        let presentation = snapshot.menuBarStatusPresentation(showMeteredUsage: false, headsUp: makeHeadsUp(severity: .info))

        #expect(presentation == snapshot.menuBarStatusPresentation)
        #expect(presentation.branch == .battery)
    }

    @Test
    func batteryAtOrBelowFiftyPercentBeatsHeadsUp() {
        let presentation = makeSnapshot(chargePercent: 0.5, latency: 28, weather: makeWeather())
            .menuBarStatusPresentation(showMeteredUsage: false, headsUp: makeHeadsUp(severity: .attention))

        #expect(presentation.text == "50%")
        #expect(presentation.branch == .battery)

        let aboveFifty = makeSnapshot(chargePercent: 0.51, latency: 28, weather: makeWeather())
            .menuBarStatusPresentation(showMeteredUsage: false, headsUp: makeHeadsUp(severity: .attention))
        #expect(aboveFifty.branch == .headsUp)
    }

    @Test
    func batteryStillBeatsOfflineWithHeadsUp() {
        let presentation = makeSnapshot(
            chargePercent: 0.49,
            connectivity: ConnectivitySnapshot(pathAvailable: true, internetState: .offline, lastCheckedAt: .now),
            latency: 28,
            weather: makeWeather()
        ).menuBarStatusPresentation(showMeteredUsage: false, headsUp: makeHeadsUp(severity: .attention))

        #expect(presentation.branch == .battery)
    }

    @Test
    func offlineBeatsHeadsUp() {
        let presentation = makeSnapshot(
            chargePercent: 0.9,
            connectivity: ConnectivitySnapshot(pathAvailable: true, internetState: .offline, lastCheckedAt: .now),
            latency: 28,
            weather: makeWeather()
        ).menuBarStatusPresentation(showMeteredUsage: false, headsUp: makeHeadsUp(severity: .attention))

        #expect(presentation.text == nil)
        #expect(presentation.symbolName == "wifi.slash")
        #expect(presentation.branch == .offline)
        #expect(presentation.tone == .attention)
    }

    @Test
    func meteredUsageBeatsOfflineAndHeadsUp() {
        let snapshot = makeSnapshot(
            chargePercent: 0.2,
            connectivity: ConnectivitySnapshot(pathAvailable: true, internetState: .offline, lastCheckedAt: .now),
            latency: 28,
            weather: makeWeather(),
            meteredData: makeMetered()
        )
        let presentation = snapshot.menuBarStatusPresentation(showMeteredUsage: true, headsUp: makeHeadsUp(severity: .attention))

        #expect(presentation.branch == .latencyFallback)
        #expect(presentation.symbolName == "arrow.up.arrow.down.circle")

        let hidden = snapshot.menuBarStatusPresentation(showMeteredUsage: false, headsUp: makeHeadsUp(severity: .attention))
        #expect(hidden.branch == .battery)
    }

    @Test
    func missingHeadsUpKeepsDefaultLadder() {
        let snapshot = makeSnapshot(chargePercent: 0.49, latency: 28, weather: makeWeather())

        #expect(snapshot.menuBarStatusPresentation(showMeteredUsage: false) == snapshot.menuBarStatusPresentation)
        #expect(snapshot.menuBarStatusPresentation(showMeteredUsage: false, headsUp: nil).branch == .battery)
    }

    @Test
    func emptyStateUsesDefaultIconWithoutText() {
        let presentation = makeSnapshot(chargePercent: nil, latency: nil, weather: nil).menuBarStatusPresentation

        #expect(presentation.text == nil)
        #expect(presentation.symbolName == "suitcase.rolling.fill")
        #expect(presentation.branch == .empty)
    }
}

private func makeSnapshot(
    chargePercent: Double?,
    connectivity: ConnectivitySnapshot = ConnectivitySnapshot(pathAvailable: true, internetState: .online, lastCheckedAt: .now),
    latency: Double?,
    weather: WeatherSnapshot?,
    rssi: Int? = -56,
    issues: [DashboardIssue] = [],
    meteredData: MeteredUsageSnapshot = .disabled
) -> DashboardSnapshot {
    DashboardSnapshot(
        network: NetworkSectionSnapshot(
            throughput: NetworkThroughputSample(
                downloadBytesPerSecond: 8_000_000,
                uploadBytesPerSecond: 2_000_000,
                activeInterface: "en0",
                collectedAt: .now
            ),
            connectivity: connectivity,
            latency: latency.map {
                LatencySample(host: "1.1.1.1", milliseconds: $0, jitterMilliseconds: 3, collectedAt: .now)
            },
            downloadHistory: [],
            uploadHistory: [],
            latencyHistory: []
        ),
        power: PowerSectionSnapshot(
            snapshot: PowerSnapshot(
                chargePercent: chargePercent,
                state: .battery,
                timeRemainingMinutes: 180,
                timeToFullChargeMinutes: nil,
                isLowPowerModeEnabled: false,
                dischargeRateWatts: 9.3,
                adapterWatts: nil,
                collectedAt: .now
            ),
            chargeHistory: [],
            dischargeHistory: []
        ),
        travelContext: TravelContextSnapshot(
            wifi: WiFiSnapshot(interfaceName: "en0", ssid: "Nomad Hub", rssi: rssi, noise: -91, transmitRateMbps: 720),
            vpn: VPNStatusSnapshot(isActive: true, interfaceNames: ["utun3"]),
            timeZoneIdentifier: "Europe/Madrid",
            deviceLocation: nil,
            publicIP: PublicIPSnapshot(address: "198.51.100.12", provider: "test", fetchedAt: .now),
            location: nil
        ),
        weather: weather,
        appState: AppStatusSnapshot(lastRefresh: .now, updateState: .idle, issues: issues),
        meteredData: meteredData
    )
}

private func makeHeadsUp(severity: DashboardInsightSeverity) -> DashboardInsight {
    DashboardInsight(
        kind: .strongWind,
        severity: severity,
        symbolName: "wind",
        title: "Wind up to 45 km/h",
        menuBarText: "Wind 45",
        detail: "From W now",
        relatedCard: .weather
    )
}

private func makeMetered() -> MeteredUsageSnapshot {
    MeteredUsageSnapshot(
        isFeatureEnabled: true,
        isMonitoringActive: true,
        networkKey: "wifi:Hotspot",
        networkDisplayName: "Hotspot",
        meteredInterfaceName: "en0",
        sessionStartedAt: nil,
        sessionBytesReceived: 500,
        sessionBytesSent: 0,
        periodBytesReceived: 500,
        periodBytesSent: 0,
        capBytes: 1_000,
        usageFraction: nil,
        isCapReached: false,
        billingPeriod: .session,
        manualSessionEnabled: false,
        isKnownMeteredNetwork: true,
        networkNameSource: .liveSSID,
        isWiFiConnected: true,
        needsLocationForWiFiNames: false,
        statusMessage: nil,
        capAlertSignal: nil
    )
}

private func makeWeather(
    temperatureCelsius: Double? = 22,
    symbolName: String = "sun.max.fill"
) -> WeatherSnapshot {
    WeatherSnapshot(
        currentTemperatureCelsius: temperatureCelsius,
        apparentTemperatureCelsius: 24,
        conditionDescription: "Clear",
        symbolName: symbolName,
        precipitationChance: nil,
        windSpeedKph: 8,
        windDirectionDegrees: 180,
        tomorrow: nil,
        fetchedAt: .now
    )
}
