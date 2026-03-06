import CoreLocation
import Foundation

public struct LatencyEndpoint: Equatable, Sendable {
    public let host: String
    public let port: UInt16

    public init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }
}

public protocol ThroughputMonitor: Sendable {
    func currentSample() async -> NetworkThroughputSample?
}

public protocol LatencyProbe: Sendable {
    func currentSample() async -> LatencySample?
}

public protocol PowerMonitor: Sendable {
    func currentSnapshot() async -> PowerSnapshot?
}

public protocol WiFiMonitor: Sendable {
    func currentSnapshot() async -> WiFiSnapshot?
}

public protocol VPNStatusProvider: Sendable {
    func currentStatus() async -> VPNStatusSnapshot
}

public protocol PublicIPProvider: Sendable {
    func currentIP(forceRefresh: Bool) async throws -> PublicIPSnapshot
}

public protocol PublicIPLocationProvider: Sendable {
    func currentLocation(for ipAddress: String, forceRefresh: Bool) async throws -> IPLocationSnapshot
}

public protocol WeatherProvider: Sendable {
    func weather(for coordinate: CLLocationCoordinate2D?) async throws -> WeatherSnapshot
}

public protocol MetricHistoryStore: Sendable {
    func loadAll() async throws -> [MetricSeriesKind: [MetricPoint]]
    func append(_ point: MetricPoint, to series: MetricSeriesKind) async throws
    func reset() async throws
    func setRetentionHours(_ retentionHours: Int) async throws
}

public protocol UpdateCoordinator: Sendable {
    func currentState() async -> UpdateStateSnapshot
    func checkForUpdates() async
    func setAutomaticChecksEnabled(_ isEnabled: Bool) async
}
