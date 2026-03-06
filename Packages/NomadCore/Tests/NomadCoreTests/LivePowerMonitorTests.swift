import Foundation
@testable import NomadCore
import Testing

struct LivePowerMonitorTests {
    @Test
    func negativeTimeRemainingIsTreatedAsUnknown() {
        #expect(LivePowerMonitor.normalizedTimeRemainingMinutes(-1) == nil)
    }

    @Test
    func positiveTimeRemainingIsPreserved() {
        #expect(LivePowerMonitor.normalizedTimeRemainingMinutes(87) == 87)
    }

    @Test
    func missingBatteryEstimateDoesNotTriggerAttention() {
        let summary = DashboardHealthEvaluator.makeSummary(
            network: NetworkSectionSnapshot(
                throughput: NetworkThroughputSample(
                    downloadBytesPerSecond: 8_000_000,
                    uploadBytesPerSecond: 2_000_000,
                    activeInterface: "en0",
                    collectedAt: .now
                ),
                latency: LatencySample(host: "1.1.1.1", milliseconds: 24, jitterMilliseconds: 3, collectedAt: .now),
                downloadHistory: [],
                uploadHistory: [],
                latencyHistory: []
            ),
            power: PowerSectionSnapshot(
                snapshot: PowerSnapshot(
                    chargePercent: 0.84,
                    state: .battery,
                    timeRemainingMinutes: nil,
                    isLowPowerModeEnabled: false,
                    dischargeRateWatts: 9.8,
                    adapterWatts: nil,
                    collectedAt: .now
                ),
                chargeHistory: [],
                dischargeHistory: []
            ),
            travelContext: TravelContextSnapshot(
                wifi: WiFiSnapshot(interfaceName: "en0", ssid: "Nomad Hub", rssi: -55, noise: -92, transmitRateMbps: 720),
                vpn: VPNStatusSnapshot(isActive: false, interfaceNames: [], serviceNames: []),
                timeZoneIdentifier: "Europe/Madrid",
                publicIP: nil,
                location: nil
            ),
            appState: AppStatusSnapshot(lastRefresh: .now, updateState: .idle, issues: [])
        )

        #expect(summary.power.level == .ready)
        #expect(summary.overall.level == .ready)
    }
}
