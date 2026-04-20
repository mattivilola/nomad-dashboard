import Foundation
@testable import NomadCore
import Testing

struct LivePowerMonitorTests {
    @Test
    func negativeDischargeTimeRemainingIsTreatedAsUnknown() {
        #expect(LivePowerMonitor.normalizedEstimatedMinutes(-1) == nil)
    }

    @Test
    func positiveDischargeTimeRemainingIsPreserved() {
        #expect(LivePowerMonitor.normalizedEstimatedMinutes(87) == 87)
    }

    @Test
    func negativeChargeTimeRemainingIsTreatedAsUnknown() {
        #expect(LivePowerMonitor.normalizedEstimatedMinutes(-1) == nil)
    }

    @Test
    func positiveChargeTimeRemainingIsPreserved() {
        #expect(LivePowerMonitor.normalizedEstimatedMinutes(13) == 13)
    }

    @Test
    func wrappedBatteryCurrentIsNormalizedToSignedMilliAmps() {
        let wrappedCurrent = NSNumber(value: UInt64.max - 852)

        #expect(LivePowerMonitor.normalizedSignedMilliAmps(wrappedCurrent) == -853)
    }

    @Test
    func dischargeRateFallsBackToBatteryRegistryValues() {
        let watts = LivePowerMonitor.dischargeRateWatts(fromBatteryRegistryValues: [
            "InstantAmperage": NSNumber(value: UInt64.max - 852),
            "Voltage": NSNumber(value: 11_569)
        ])

        #expect(watts == 9.868357)
    }

    @Test
    func dischargeRatePrefersPowerSourceDescriptionWhenAvailable() {
        let watts = LivePowerMonitor.resolveDischargeRateWatts(
            state: .battery,
            description: [
                kIOPSCurrentKey: NSNumber(value: 1_200),
                kIOPSVoltageKey: NSNumber(value: 11_000)
            ],
            registryValues: [
                "InstantAmperage": NSNumber(value: UInt64.max - 852),
                "Voltage": NSNumber(value: 11_569)
            ]
        )

        #expect(watts == 13.2)
    }

    @Test
    func dischargeRateIsNotReportedWhenMachineIsNotOnBattery() {
        let watts = LivePowerMonitor.resolveDischargeRateWatts(
            state: .charging,
            description: [
                kIOPSCurrentKey: NSNumber(value: 1_200),
                kIOPSVoltageKey: NSNumber(value: 11_000)
            ],
            registryValues: [
                "InstantAmperage": NSNumber(value: UInt64.max - 852),
                "Voltage": NSNumber(value: 11_569)
            ]
        )

        #expect(watts == nil)
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
                    timeToFullChargeMinutes: nil,
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
                deviceLocation: nil,
                publicIP: nil,
                location: nil
            ),
            appState: AppStatusSnapshot(lastRefresh: .now, updateState: .idle, issues: [])
        )

        #expect(summary.power.level == .ready)
        #expect(summary.overall.level == .ready)
    }
}
