import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var refreshIntervalSeconds: TimeInterval
    public var slowRefreshIntervalSeconds: TimeInterval
    public var historyRetentionHours: Int
    public var publicIPGeolocationEnabled: Bool
    public var automaticUpdateChecksEnabled: Bool
    public var launchAtLoginEnabled: Bool
    public var useCurrentLocationForWeather: Bool
    public var latencyHosts: [String]

    public init(
        refreshIntervalSeconds: TimeInterval = 2,
        slowRefreshIntervalSeconds: TimeInterval = 60,
        historyRetentionHours: Int = 24,
        publicIPGeolocationEnabled: Bool = false,
        automaticUpdateChecksEnabled: Bool = true,
        launchAtLoginEnabled: Bool = false,
        useCurrentLocationForWeather: Bool = true,
        latencyHosts: [String] = ["1.1.1.1:443", "8.8.8.8:443"]
    ) {
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.slowRefreshIntervalSeconds = slowRefreshIntervalSeconds
        self.historyRetentionHours = historyRetentionHours
        self.publicIPGeolocationEnabled = publicIPGeolocationEnabled
        self.automaticUpdateChecksEnabled = automaticUpdateChecksEnabled
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.useCurrentLocationForWeather = useCurrentLocationForWeather
        self.latencyHosts = latencyHosts
    }
}

