import Foundation
import NomadCore
import Testing

struct DashboardHealthEvaluatorTests {
    @Test
    func healthyTelemetryProducesReadySummary() {
        let summary = makeSummary()

        #expect(summary.network.level == .ready)
        #expect(summary.power.level == .ready)
        #expect(summary.overall.level == .ready)
    }

    @Test
    func elevatedLatencyTriggersNetworkCaution() {
        let summary = makeSummary(latency: 85, jitter: 4)

        #expect(summary.network.level == .caution)
        #expect(summary.overall.level == .caution)
    }

    @Test
    func highJitterTriggersNetworkAttention() {
        let summary = makeSummary(latency: 28, jitter: 31)

        #expect(summary.network.level == .attention)
        #expect(summary.overall.level == .attention)
    }

    @Test
    func lowBatteryTriggersPowerAttention() {
        let summary = makeSummary(chargePercent: 0.2, timeRemainingMinutes: 38)

        #expect(summary.power.level == .attention)
        #expect(summary.overall.level == .attention)
    }

    @Test
    func missingSamplesStayUnavailableUntilDataArrives() {
        let summary = DashboardHealthEvaluator.makeSummary(
            network: NetworkSectionSnapshot(
                throughput: nil,
                latency: nil,
                downloadHistory: [],
                uploadHistory: [],
                latencyHistory: []
            ),
            power: PowerSectionSnapshot(snapshot: nil, chargeHistory: [], dischargeHistory: []),
            travelContext: TravelContextSnapshot(
                wifi: nil,
                vpn: nil,
                timeZoneIdentifier: "Europe/Madrid",
                publicIP: nil,
                location: nil
            ),
            appState: AppStatusSnapshot(lastRefresh: nil, updateState: .idle, issues: [])
        )

        #expect(summary.network.level == .unavailable)
        #expect(summary.power.level == .unavailable)
        #expect(summary.overall.level == .unavailable)
    }
}

private func makeSummary(
    activeInterface: String? = "en0",
    latency: Double? = 24,
    jitter: Double? = 3,
    rssi: Int? = -56,
    chargePercent: Double? = 0.81,
    timeRemainingMinutes: Int? = 210,
    lowPowerMode: Bool = false,
    issues: [DashboardIssue] = []
) -> DashboardHealthSummary {
    DashboardHealthEvaluator.makeSummary(
        network: NetworkSectionSnapshot(
            throughput: NetworkThroughputSample(
                downloadBytesPerSecond: 8_000_000,
                uploadBytesPerSecond: 2_000_000,
                activeInterface: activeInterface,
                collectedAt: .now
            ),
            latency: latency.map {
                LatencySample(host: "1.1.1.1", milliseconds: $0, jitterMilliseconds: jitter, collectedAt: .now)
            },
            downloadHistory: [],
            uploadHistory: [],
            latencyHistory: []
        ),
        power: PowerSectionSnapshot(
            snapshot: PowerSnapshot(
                chargePercent: chargePercent,
                state: .battery,
                timeRemainingMinutes: timeRemainingMinutes,
                timeToFullChargeMinutes: nil,
                isLowPowerModeEnabled: lowPowerMode,
                dischargeRateWatts: 11.2,
                adapterWatts: nil,
                collectedAt: .now
            ),
            chargeHistory: [],
            dischargeHistory: []
        ),
        travelContext: TravelContextSnapshot(
            wifi: WiFiSnapshot(interfaceName: activeInterface, ssid: "Nomad Hub", rssi: rssi, noise: -91, transmitRateMbps: 720),
            vpn: VPNStatusSnapshot(isActive: false, interfaceNames: []),
            timeZoneIdentifier: "Europe/Madrid",
            publicIP: PublicIPSnapshot(address: "198.51.100.12", provider: "test", fetchedAt: .now),
            location: nil
        ),
        appState: AppStatusSnapshot(lastRefresh: .now, updateState: .idle, issues: issues)
    )
}
