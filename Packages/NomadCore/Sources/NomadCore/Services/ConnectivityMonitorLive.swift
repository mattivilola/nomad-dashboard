import Foundation
import Network

public protocol PathAvailabilityReading: Sendable {
    func currentPathAvailable() -> Bool?
}

public final class NWPathAvailabilityReader: PathAvailabilityReading, @unchecked Sendable {
    private let monitor: NWPathMonitor
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var latestPathAvailable: Bool?

    public init(monitor: NWPathMonitor = NWPathMonitor()) {
        self.monitor = monitor
        queue = DispatchQueue(label: "NomadDashboard.ConnectivityPathMonitor")

        monitor.pathUpdateHandler = { [weak self] path in
            self?.store(pathAvailable: path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    public func currentPathAvailable() -> Bool? {
        lock.lock()
        defer {
            lock.unlock()
        }

        return latestPathAvailable
    }

    private func store(pathAvailable: Bool) {
        lock.lock()
        latestPathAvailable = pathAvailable
        lock.unlock()
    }
}

public actor LiveConnectivityMonitor: ConnectivityMonitor {
    private let pathReader: any PathAvailabilityReading
    private let endpoints: [LatencyEndpoint]
    private let connector: any LatencyConnecting
    private let throttleInterval: TimeInterval
    private let nowProvider: @Sendable () -> Date
    private var cachedSnapshot = ConnectivitySnapshot.checking

    public init(
        endpoints: [LatencyEndpoint],
        pathReader: any PathAvailabilityReading = NWPathAvailabilityReader(),
        connector: any LatencyConnecting = TCPConnectionLatencyConnector(),
        throttleInterval: TimeInterval = 5,
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.endpoints = endpoints.isEmpty ? [LatencyEndpoint(host: "1.1.1.1", port: 443)] : endpoints
        self.pathReader = pathReader
        self.connector = connector
        self.throttleInterval = throttleInterval
        self.nowProvider = nowProvider
    }

    public func currentSnapshot() async -> ConnectivitySnapshot {
        let now = nowProvider()
        let pathAvailable = pathReader.currentPathAvailable()

        guard let pathAvailable else {
            return cachedSnapshot.lastCheckedAt == nil ? .checking : cachedSnapshot
        }

        guard pathAvailable else {
            let snapshot = ConnectivitySnapshot(
                pathAvailable: false,
                internetState: .offline,
                lastCheckedAt: now
            )
            cachedSnapshot = snapshot
            return snapshot
        }

        if cachedSnapshot.pathAvailable == true,
           let lastCheckedAt = cachedSnapshot.lastCheckedAt,
           now.timeIntervalSince(lastCheckedAt) < throttleInterval
        {
            return cachedSnapshot
        }

        let internetReachable = await canReachInternet()
        let snapshot = ConnectivitySnapshot(
            pathAvailable: true,
            internetState: internetReachable ? .online : .offline,
            lastCheckedAt: now
        )
        cachedSnapshot = snapshot
        return snapshot
    }

    private func canReachInternet() async -> Bool {
        for endpoint in endpoints {
            if await connector.measureLatency(to: endpoint, timeout: 1.5) != nil {
                return true
            }
        }

        return false
    }
}
