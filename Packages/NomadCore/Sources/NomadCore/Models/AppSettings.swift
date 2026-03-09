import CoreLocation
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
    public var surfSpotName: String
    public var surfSpotLatitude: Double?
    public var surfSpotLongitude: Double?
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
        surfSpotName: String = "",
        surfSpotLatitude: Double? = nil,
        surfSpotLongitude: Double? = nil,
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
        self.surfSpotName = surfSpotName
        self.surfSpotLatitude = surfSpotLatitude
        self.surfSpotLongitude = surfSpotLongitude
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
        case surfSpotName
        case surfSpotLatitude
        case surfSpotLongitude
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
        surfSpotName = try container.decodeIfPresent(String.self, forKey: .surfSpotName) ?? ""
        surfSpotLatitude = try container.decodeIfPresent(Double.self, forKey: .surfSpotLatitude)
        surfSpotLongitude = try container.decodeIfPresent(Double.self, forKey: .surfSpotLongitude)
        latencyHosts = try container.decode([String].self, forKey: .latencyHosts)
    }
}

public struct SurfSpotConfiguration: Sendable, Equatable {
    public let name: String?
    public let latitude: Double?
    public let longitude: Double?
    public let coordinate: CLLocationCoordinate2D?
    public let isConfigured: Bool
    public let isValid: Bool

    public init(
        name: String?,
        latitude: Double?,
        longitude: Double?,
        coordinate: CLLocationCoordinate2D?,
        isConfigured: Bool,
        isValid: Bool
    ) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.coordinate = coordinate
        self.isConfigured = isConfigured
        self.isValid = isValid
    }

    public static func == (lhs: SurfSpotConfiguration, rhs: SurfSpotConfiguration) -> Bool {
        lhs.name == rhs.name
            && lhs.latitude == rhs.latitude
            && lhs.longitude == rhs.longitude
            && lhs.coordinate?.latitude == rhs.coordinate?.latitude
            && lhs.coordinate?.longitude == rhs.coordinate?.longitude
            && lhs.isConfigured == rhs.isConfigured
            && lhs.isValid == rhs.isValid
    }
}

public extension AppSettings {
    var surfSpotConfiguration: SurfSpotConfiguration {
        let normalizedName = surfSpotName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = normalizedName.isEmpty ? nil : normalizedName
        let hasAnyInput = resolvedName != nil || surfSpotLatitude != nil || surfSpotLongitude != nil
        let hasValidLatitude = surfSpotLatitude.map { (-90.0...90.0).contains($0) } ?? false
        let hasValidLongitude = surfSpotLongitude.map { (-180.0...180.0).contains($0) } ?? false
        let isValid = resolvedName != nil && hasValidLatitude && hasValidLongitude
        let coordinate: CLLocationCoordinate2D?

        if isValid, let surfSpotLatitude, let surfSpotLongitude {
            coordinate = CLLocationCoordinate2D(latitude: surfSpotLatitude, longitude: surfSpotLongitude)
        } else {
            coordinate = nil
        }

        return SurfSpotConfiguration(
            name: resolvedName,
            latitude: surfSpotLatitude,
            longitude: surfSpotLongitude,
            coordinate: coordinate,
            isConfigured: hasAnyInput,
            isValid: isValid
        )
    }
}
