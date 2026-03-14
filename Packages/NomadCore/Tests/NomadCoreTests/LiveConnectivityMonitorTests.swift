import Foundation
@testable import NomadCore
import Testing

struct LiveConnectivityMonitorTests {
    @Test
    func unsatisfiedPathReturnsOfflineWithoutRemoteProbe() async {
        let connector = RecordingLatencyConnector(resultsByHost: [:])
        let monitor = LiveConnectivityMonitor(
            endpoints: [LatencyEndpoint(host: "1.1.1.1", port: 443)],
            pathReader: FixedPathAvailabilityReader(pathAvailable: false),
            connector: connector
        )

        let snapshot = await monitor.currentSnapshot()

        #expect(snapshot.pathAvailable == false)
        #expect(snapshot.internetState == .offline)
        #expect(await connector.recordedHosts().isEmpty)
    }

    @Test
    func satisfiedPathAndSuccessfulProbeReturnsOnline() async {
        let connector = RecordingLatencyConnector(resultsByHost: ["1.1.1.1": 24])
        let monitor = LiveConnectivityMonitor(
            endpoints: [LatencyEndpoint(host: "1.1.1.1", port: 443)],
            pathReader: FixedPathAvailabilityReader(pathAvailable: true),
            connector: connector
        )

        let snapshot = await monitor.currentSnapshot()

        #expect(snapshot.pathAvailable == true)
        #expect(snapshot.internetState == .online)
        #expect(await connector.recordedHosts() == ["1.1.1.1"])
    }

    @Test
    func satisfiedPathAndFailedProbesReturnsOffline() async {
        let connector = RecordingLatencyConnector(resultsByHost: [:])
        let monitor = LiveConnectivityMonitor(
            endpoints: [
                LatencyEndpoint(host: "1.1.1.1", port: 443),
                LatencyEndpoint(host: "8.8.8.8", port: 443)
            ],
            pathReader: FixedPathAvailabilityReader(pathAvailable: true),
            connector: connector
        )

        let snapshot = await monitor.currentSnapshot()

        #expect(snapshot.pathAvailable == true)
        #expect(snapshot.internetState == .offline)
        #expect(await connector.recordedHosts() == ["1.1.1.1", "8.8.8.8"])
    }

    @Test
    func repeatedReadsWithinThrottleWindowReuseCachedRemoteStatus() async {
        let connector = RecordingLatencyConnector(resultsByHost: ["1.1.1.1": 18])
        let dates = LockedDateSequence(values: [
            Date(timeIntervalSince1970: 100),
            Date(timeIntervalSince1970: 102)
        ])
        let monitor = LiveConnectivityMonitor(
            endpoints: [LatencyEndpoint(host: "1.1.1.1", port: 443)],
            pathReader: FixedPathAvailabilityReader(pathAvailable: true),
            connector: connector,
            throttleInterval: 5,
            nowProvider: { dates.next() }
        )

        let first = await monitor.currentSnapshot()
        let second = await monitor.currentSnapshot()

        #expect(first.internetState == .online)
        #expect(second.internetState == .online)
        #expect(first.lastCheckedAt == second.lastCheckedAt)
        #expect(await connector.recordedHosts() == ["1.1.1.1"])
    }
}

private struct FixedPathAvailabilityReader: PathAvailabilityReading {
    let pathAvailable: Bool?

    func currentPathAvailable() -> Bool? {
        pathAvailable
    }
}

private actor RecordingLatencyConnector: LatencyConnecting {
    private let resultsByHost: [String: Double]
    private var hosts: [String] = []

    init(resultsByHost: [String: Double]) {
        self.resultsByHost = resultsByHost
    }

    func measureLatency(to endpoint: LatencyEndpoint, timeout: TimeInterval) async -> Double? {
        hosts.append(endpoint.host)
        return resultsByHost[endpoint.host]
    }

    func recordedHosts() -> [String] {
        hosts
    }
}

private final class LockedDateSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Date]

    init(values: [Date]) {
        self.values = values
    }

    func next() -> Date {
        lock.lock()
        defer {
            lock.unlock()
        }

        if values.isEmpty {
            return Date(timeIntervalSince1970: 0)
        }

        if values.count == 1 {
            return values[0]
        }

        return values.removeFirst()
    }
}
