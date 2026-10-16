import Foundation
@testable import NomadCore
import Testing

struct MeteredDataTests {
    @Test func byteDeltaIgnoresCounterReset() {
        let previous = InterfaceByteTotals(receivedBytes: 1_000, sentBytes: 500)
        let current = InterfaceByteTotals(receivedBytes: 100, sentBytes: 50)
        let delta = InterfaceByteDeltaAccounting.delta(current: current, previous: previous)
        #expect(delta.receivedBytes == 0)
        #expect(delta.sentBytes == 0)
    }

    @Test func byteDeltaAccumulatesNormally() {
        let previous = InterfaceByteTotals(receivedBytes: 1_000, sentBytes: 500)
        let current = InterfaceByteTotals(receivedBytes: 1_500, sentBytes: 700)
        let delta = InterfaceByteDeltaAccounting.delta(current: current, previous: previous)
        #expect(delta.receivedBytes == 500)
        #expect(delta.sentBytes == 200)
    }

    @Test func networkKeyPrefersSSID() {
        let resolved = MeteredNetworkKeyResolver.resolve(
            ssid: "Matt's iPhone",
            interfaceName: "en0",
            isExpensive: false,
            isConstrained: false
        )
        #expect(resolved.key == "wifi:Matt's iPhone")
        #expect(resolved.displayName == "Matt's iPhone")
        #expect(resolved.source == .liveSSID)
    }

    @Test func networkKeyUsesCachedSSIDBeforeExpensiveFallback() {
        let cache = MeteredWiFiSSIDCacheEntry(ssid: "PocoMatti", interfaceName: "en0", lastSeenAt: .now)
        let resolved = MeteredNetworkKeyResolver.resolve(
            ssid: nil,
            interfaceName: "en0",
            isExpensive: true,
            isConstrained: false,
            cachedSSID: cache
        )
        #expect(resolved.key == "wifi:PocoMatti")
        #expect(resolved.source == .cachedSSID)
    }

    @Test func capReachedForcesLowDataPolicy() {
        let policy = DashboardResourcePolicy(
            mode: .standard,
            conditions: ResourceConditions(pathAvailable: true),
            isMeteredCapReached: true
        )
        #expect(policy.isLowData)
        #expect(policy.reducesBackgroundWork)
        #expect(policy.reason?.contains("Data cap reached") == true)
    }

    @Test func meteredControllerStartsSessionOnExpensivePath() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("metered-\(UUID().uuidString).json")
        let store = MeteredUsageStore(url: url)
        let counterReader = FixedDetailedInterfaceCounterReader(
            snapshots: [
                DetailedInterfaceCounterSnapshot(
                    perInterface: ["en0": InterfaceByteTotals(receivedBytes: 1_000, sentBytes: 100)],
                    receivedBytes: 1_000,
                    sentBytes: 100,
                    primaryInterface: "en0",
                    capturedAt: .now
                ),
                DetailedInterfaceCounterSnapshot(
                    perInterface: ["en0": InterfaceByteTotals(receivedBytes: 2_000, sentBytes: 300)],
                    receivedBytes: 2_000,
                    sentBytes: 300,
                    primaryInterface: "en0",
                    capturedAt: .now.addingTimeInterval(10)
                )
            ]
        )
        let routeReader = FixedDefaultRouteInterfaceReader(interfaceName: "en0")
        let controller = MeteredDataController(store: store, counterReader: counterReader, routeReader: routeReader)

        var settings = AppSettings()
        settings.meteredDataEnabled = true
        settings.autoEnableOnExpensivePath = true

        let first = await controller.tick(input: MeteredDataTickInput(
            settings: settings,
            wifiSSID: "Travel SIM",
            wifiInterfaceName: "en0",
            isExpensive: true,
            isConstrained: false
        ))
        #expect(first.isMonitoringActive)
        #expect(first.sessionBytesReceived == 0)

        let second = await controller.tick(input: MeteredDataTickInput(
            settings: settings,
            wifiSSID: "Travel SIM",
            wifiInterfaceName: "en0",
            isExpensive: true,
            isConstrained: false,
            now: .now.addingTimeInterval(10)
        ))
        #expect(second.sessionBytesReceived == 1_000)
        #expect(second.sessionBytesSent == 200)
    }
}

private final class FixedDetailedInterfaceCounterReader: DetailedInterfaceCounterReading, @unchecked Sendable {
    private let snapshots: [DetailedInterfaceCounterSnapshot]
    private var index = 0

    init(snapshots: [DetailedInterfaceCounterSnapshot]) {
        self.snapshots = snapshots
    }

    func read() -> DetailedInterfaceCounterSnapshot? {
        guard !snapshots.isEmpty else { return nil }
        let snapshot = index < snapshots.count ? snapshots[index] : snapshots[snapshots.count - 1]
        if index < snapshots.count {
            index += 1
        }
        return snapshot
    }
}

private struct FixedDefaultRouteInterfaceReader: DefaultRouteInterfaceReading {
    let interfaceName: String?

    func defaultInterfaceName() -> String? {
        interfaceName
    }
}
