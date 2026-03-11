import CoreLocation
import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var appearanceMode: AppAppearanceMode
    public var dashboardCardOrder: [DashboardCardID]
    public var dashboardCardWidthModes: [DashboardCardID: DashboardCardWidthMode]
    public var refreshIntervalSeconds: TimeInterval
    public var slowRefreshIntervalSeconds: TimeInterval
    public var historyRetentionHours: Int
    public var publicIPGeolocationEnabled: Bool
    public var automaticUpdateChecksEnabled: Bool
    public var launchAtLoginEnabled: Bool
    public var useCurrentLocationForWeather: Bool
    public var fuelPricesEnabled: Bool
    public var visitedPlacesEnabled: Bool
    public var travelAdvisoryEnabled: Bool
    public var travelWeatherAlertsEnabled: Bool
    public var regionalSecurityEnabled: Bool
    public var tankerkonigAPIKey: String
    public var surfSpotName: String
    public var surfSpotLatitude: Double?
    public var surfSpotLongitude: Double?
    public var latencyHosts: [String]

    public init(
        appearanceMode: AppAppearanceMode = .system,
        dashboardCardOrder: [DashboardCardID] = DashboardCardID.defaultOrder,
        dashboardCardWidthModes: [DashboardCardID: DashboardCardWidthMode] = DashboardCardID.defaultWidthModes,
        refreshIntervalSeconds: TimeInterval = 2,
        slowRefreshIntervalSeconds: TimeInterval = 60,
        historyRetentionHours: Int = 24,
        publicIPGeolocationEnabled: Bool = true,
        automaticUpdateChecksEnabled: Bool = true,
        launchAtLoginEnabled: Bool = false,
        useCurrentLocationForWeather: Bool = true,
        fuelPricesEnabled: Bool = false,
        visitedPlacesEnabled: Bool = true,
        travelAdvisoryEnabled: Bool = true,
        travelWeatherAlertsEnabled: Bool = false,
        regionalSecurityEnabled: Bool = false,
        tankerkonigAPIKey: String = "",
        surfSpotName: String = "",
        surfSpotLatitude: Double? = nil,
        surfSpotLongitude: Double? = nil,
        latencyHosts: [String] = ["1.1.1.1:443", "8.8.8.8:443"]
    ) {
        self.appearanceMode = appearanceMode
        self.dashboardCardOrder = DashboardCardID.sanitizedOrder(dashboardCardOrder)
        self.dashboardCardWidthModes = DashboardCardID.sanitizedWidthModes(dashboardCardWidthModes)
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.slowRefreshIntervalSeconds = slowRefreshIntervalSeconds
        self.historyRetentionHours = historyRetentionHours
        self.publicIPGeolocationEnabled = publicIPGeolocationEnabled
        self.automaticUpdateChecksEnabled = automaticUpdateChecksEnabled
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.useCurrentLocationForWeather = useCurrentLocationForWeather
        self.fuelPricesEnabled = fuelPricesEnabled
        self.visitedPlacesEnabled = visitedPlacesEnabled
        self.travelAdvisoryEnabled = travelAdvisoryEnabled
        self.travelWeatherAlertsEnabled = travelWeatherAlertsEnabled
        self.regionalSecurityEnabled = regionalSecurityEnabled
        self.tankerkonigAPIKey = tankerkonigAPIKey
        self.surfSpotName = surfSpotName
        self.surfSpotLatitude = surfSpotLatitude
        self.surfSpotLongitude = surfSpotLongitude
        self.latencyHosts = latencyHosts
    }

    enum CodingKeys: String, CodingKey {
        case appearanceMode
        case dashboardCardOrder
        case dashboardCardWidthModes
        case refreshIntervalSeconds
        case slowRefreshIntervalSeconds
        case historyRetentionHours
        case publicIPGeolocationEnabled
        case automaticUpdateChecksEnabled
        case launchAtLoginEnabled
        case useCurrentLocationForWeather
        case fuelPricesEnabled
        case visitedPlacesEnabled
        case travelAdvisoryEnabled
        case travelWeatherAlertsEnabled
        case regionalSecurityEnabled
        case tankerkonigAPIKey
        case surfSpotName
        case surfSpotLatitude
        case surfSpotLongitude
        case latencyHosts
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        appearanceMode = try container.decodeIfPresent(AppAppearanceMode.self, forKey: .appearanceMode) ?? .system
        let persistedCardOrder = (try? container.decodeIfPresent([String].self, forKey: .dashboardCardOrder))?
            .compactMap(DashboardCardID.init(rawValue:))
        dashboardCardOrder = DashboardCardID.sanitizedOrder(persistedCardOrder ?? DashboardCardID.defaultOrder)
        let persistedCardWidthModes = (try? container.decodeIfPresent([String: String].self, forKey: .dashboardCardWidthModes))?
            .reduce(into: [DashboardCardID: DashboardCardWidthMode]()) { result, entry in
                guard let cardID = DashboardCardID(rawValue: entry.key),
                      let widthMode = DashboardCardWidthMode(rawValue: entry.value)
                else {
                    return
                }

                result[cardID] = widthMode
            }
        dashboardCardWidthModes = DashboardCardID.sanitizedWidthModes(
            persistedCardWidthModes ?? DashboardCardID.defaultWidthModes
        )
        refreshIntervalSeconds = try container.decode(TimeInterval.self, forKey: .refreshIntervalSeconds)
        slowRefreshIntervalSeconds = try container.decode(TimeInterval.self, forKey: .slowRefreshIntervalSeconds)
        historyRetentionHours = try container.decode(Int.self, forKey: .historyRetentionHours)
        publicIPGeolocationEnabled = try container.decode(Bool.self, forKey: .publicIPGeolocationEnabled)
        automaticUpdateChecksEnabled = try container.decode(Bool.self, forKey: .automaticUpdateChecksEnabled)
        launchAtLoginEnabled = try container.decode(Bool.self, forKey: .launchAtLoginEnabled)
        useCurrentLocationForWeather = try container.decode(Bool.self, forKey: .useCurrentLocationForWeather)
        fuelPricesEnabled = try container.decodeIfPresent(Bool.self, forKey: .fuelPricesEnabled) ?? false
        visitedPlacesEnabled = try container.decodeIfPresent(Bool.self, forKey: .visitedPlacesEnabled) ?? false
        travelAdvisoryEnabled = try container.decodeIfPresent(Bool.self, forKey: .travelAdvisoryEnabled) ?? true
        travelWeatherAlertsEnabled = try container.decodeIfPresent(Bool.self, forKey: .travelWeatherAlertsEnabled) ?? false
        regionalSecurityEnabled = try container.decodeIfPresent(Bool.self, forKey: .regionalSecurityEnabled) ?? false
        tankerkonigAPIKey = try container.decodeIfPresent(String.self, forKey: .tankerkonigAPIKey) ?? ""
        surfSpotName = try container.decodeIfPresent(String.self, forKey: .surfSpotName) ?? ""
        surfSpotLatitude = try container.decodeIfPresent(Double.self, forKey: .surfSpotLatitude)
        surfSpotLongitude = try container.decodeIfPresent(Double.self, forKey: .surfSpotLongitude)
        latencyHosts = try container.decode([String].self, forKey: .latencyHosts)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(appearanceMode, forKey: .appearanceMode)
        try container.encode(dashboardCardOrder.map(\.rawValue), forKey: .dashboardCardOrder)
        try container.encode(
            dashboardCardWidthModes.reduce(into: [String: String]()) { result, entry in
                result[entry.key.rawValue] = entry.value.rawValue
            },
            forKey: .dashboardCardWidthModes
        )
        try container.encode(refreshIntervalSeconds, forKey: .refreshIntervalSeconds)
        try container.encode(slowRefreshIntervalSeconds, forKey: .slowRefreshIntervalSeconds)
        try container.encode(historyRetentionHours, forKey: .historyRetentionHours)
        try container.encode(publicIPGeolocationEnabled, forKey: .publicIPGeolocationEnabled)
        try container.encode(automaticUpdateChecksEnabled, forKey: .automaticUpdateChecksEnabled)
        try container.encode(launchAtLoginEnabled, forKey: .launchAtLoginEnabled)
        try container.encode(useCurrentLocationForWeather, forKey: .useCurrentLocationForWeather)
        try container.encode(fuelPricesEnabled, forKey: .fuelPricesEnabled)
        try container.encode(visitedPlacesEnabled, forKey: .visitedPlacesEnabled)
        try container.encode(travelAdvisoryEnabled, forKey: .travelAdvisoryEnabled)
        try container.encode(travelWeatherAlertsEnabled, forKey: .travelWeatherAlertsEnabled)
        try container.encode(regionalSecurityEnabled, forKey: .regionalSecurityEnabled)
        try container.encode(tankerkonigAPIKey, forKey: .tankerkonigAPIKey)
        try container.encode(surfSpotName, forKey: .surfSpotName)
        try container.encodeIfPresent(surfSpotLatitude, forKey: .surfSpotLatitude)
        try container.encodeIfPresent(surfSpotLongitude, forKey: .surfSpotLongitude)
        try container.encode(latencyHosts, forKey: .latencyHosts)
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
        let coordinate: CLLocationCoordinate2D? = if isValid, let surfSpotLatitude, let surfSpotLongitude {
            CLLocationCoordinate2D(latitude: surfSpotLatitude, longitude: surfSpotLongitude)
        } else {
            nil
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
