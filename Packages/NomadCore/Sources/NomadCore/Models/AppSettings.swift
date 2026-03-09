import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var appearanceMode: AppAppearanceMode
    public var refreshIntervalSeconds: TimeInterval
    public var slowRefreshIntervalSeconds: TimeInterval
    public var historyRetentionHours: Int
    public var publicIPGeolocationEnabled: Bool
    public var automaticUpdateChecksEnabled: Bool
    public var launchAtLoginEnabled: Bool
    public var useCurrentLocationForWeather: Bool
    public var visitedPlacesEnabled: Bool
    public var travelAdvisoryEnabled: Bool
    public var travelWeatherAlertsEnabled: Bool
    public var regionalSecurityEnabled: Bool
    public var latencyHosts: [String]

    public init(
        appearanceMode: AppAppearanceMode = .system,
        refreshIntervalSeconds: TimeInterval = 2,
        slowRefreshIntervalSeconds: TimeInterval = 60,
        historyRetentionHours: Int = 24,
        publicIPGeolocationEnabled: Bool = true,
        automaticUpdateChecksEnabled: Bool = true,
        launchAtLoginEnabled: Bool = false,
        useCurrentLocationForWeather: Bool = true,
        visitedPlacesEnabled: Bool = true,
        travelAdvisoryEnabled: Bool = true,
        travelWeatherAlertsEnabled: Bool = false,
        regionalSecurityEnabled: Bool = false,
        latencyHosts: [String] = ["1.1.1.1:443", "8.8.8.8:443"]
    ) {
        self.appearanceMode = appearanceMode
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.slowRefreshIntervalSeconds = slowRefreshIntervalSeconds
        self.historyRetentionHours = historyRetentionHours
        self.publicIPGeolocationEnabled = publicIPGeolocationEnabled
        self.automaticUpdateChecksEnabled = automaticUpdateChecksEnabled
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.useCurrentLocationForWeather = useCurrentLocationForWeather
        self.visitedPlacesEnabled = visitedPlacesEnabled
        self.travelAdvisoryEnabled = travelAdvisoryEnabled
        self.travelWeatherAlertsEnabled = travelWeatherAlertsEnabled
        self.regionalSecurityEnabled = regionalSecurityEnabled
        self.latencyHosts = latencyHosts
    }

    enum CodingKeys: String, CodingKey {
        case appearanceMode
        case refreshIntervalSeconds
        case slowRefreshIntervalSeconds
        case historyRetentionHours
        case publicIPGeolocationEnabled
        case automaticUpdateChecksEnabled
        case launchAtLoginEnabled
        case useCurrentLocationForWeather
        case visitedPlacesEnabled
        case travelAdvisoryEnabled
        case travelWeatherAlertsEnabled
        case regionalSecurityEnabled
        case latencyHosts
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        appearanceMode = try container.decodeIfPresent(AppAppearanceMode.self, forKey: .appearanceMode) ?? .system
        refreshIntervalSeconds = try container.decode(TimeInterval.self, forKey: .refreshIntervalSeconds)
        slowRefreshIntervalSeconds = try container.decode(TimeInterval.self, forKey: .slowRefreshIntervalSeconds)
        historyRetentionHours = try container.decode(Int.self, forKey: .historyRetentionHours)
        publicIPGeolocationEnabled = try container.decode(Bool.self, forKey: .publicIPGeolocationEnabled)
        automaticUpdateChecksEnabled = try container.decode(Bool.self, forKey: .automaticUpdateChecksEnabled)
        launchAtLoginEnabled = try container.decode(Bool.self, forKey: .launchAtLoginEnabled)
        useCurrentLocationForWeather = try container.decode(Bool.self, forKey: .useCurrentLocationForWeather)
        visitedPlacesEnabled = try container.decodeIfPresent(Bool.self, forKey: .visitedPlacesEnabled) ?? false
        travelAdvisoryEnabled = try container.decodeIfPresent(Bool.self, forKey: .travelAdvisoryEnabled) ?? true
        travelWeatherAlertsEnabled = try container.decodeIfPresent(Bool.self, forKey: .travelWeatherAlertsEnabled) ?? false
        regionalSecurityEnabled = try container.decodeIfPresent(Bool.self, forKey: .regionalSecurityEnabled) ?? false
        latencyHosts = try container.decode([String].self, forKey: .latencyHosts)
    }
}
