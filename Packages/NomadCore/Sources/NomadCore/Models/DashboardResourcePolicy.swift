import Foundation

public enum DataUsageMode: String, Codable, CaseIterable, Sendable {
    case automatic
    case standard
    case lowData

    public var title: String {
        switch self {
        case .automatic: "Automatic"
        case .standard: "Normal"
        case .lowData: "Low Data"
        }
    }
}

public struct ResourceConditions: Equatable, Sendable {
    public var pathAvailable: Bool?
    public var isExpensive: Bool
    public var isConstrained: Bool
    public var isLowPowerModeEnabled: Bool
    public var isThermallyLimited: Bool

    public init(
        pathAvailable: Bool? = nil,
        isExpensive: Bool = false,
        isConstrained: Bool = false,
        isLowPowerModeEnabled: Bool = false,
        isThermallyLimited: Bool = false
    ) {
        self.pathAvailable = pathAvailable
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
        self.isThermallyLimited = isThermallyLimited
    }
}

public protocol ResourceConditionsReading: Sendable {
    func currentConditions() -> ResourceConditions
}

public struct DefaultResourceConditionsReader: ResourceConditionsReading {
    public init() {}
    public func currentConditions() -> ResourceConditions {
        ResourceConditions()
    }
}

public struct DashboardResourcePolicy: Equatable, Sendable {
    public let isOffline: Bool
    public let isLowData: Bool
    public let reducesBackgroundWork: Bool
    public let reason: String?

    public init(mode: DataUsageMode, conditions: ResourceConditions) {
        isOffline = conditions.pathAvailable == false
        isLowData = mode == .lowData || (mode == .automatic && (conditions.isExpensive || conditions.isConstrained))
        reducesBackgroundWork = isLowData || conditions.isLowPowerModeEnabled || conditions.isThermallyLimited
        if isOffline {
            reason = "Offline — saved information is available"
        } else if isLowData {
            reason = "Low Data — large background downloads are paused"
        } else if conditions.isThermallyLimited {
            reason = "Keeping things light while your Mac is busy"
        } else if conditions.isLowPowerModeEnabled {
            reason = "Saving energy in Low Power Mode"
        } else {
            reason = nil
        }
    }

    public static let normal = DashboardResourcePolicy(mode: .automatic, conditions: ResourceConditions())
}

public enum DashboardDataSection: String, Codable, CaseIterable, Sendable, Identifiable {
    case location, publicIP, weather, localInfo, fuel, emergencyCare, marine, travelAlerts
    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .location: "Your location"
        case .publicIP: "Public IP"
        case .weather: "Weather"
        case .localInfo: "Local info"
        case .fuel: "Fuel prices"
        case .emergencyCare: "Emergency care"
        case .marine: "Surf forecast"
        case .travelAlerts: "Travel alerts"
        }
    }

    public var isLargeDownload: Bool {
        self == .fuel || self == .localInfo || self == .travelAlerts
    }
}

public struct DashboardSectionActivity: Equatable, Sendable {
    public var isRefreshing = false
    public var lastSuccessAt: Date?
    public var message: String?
    public var isSaved = false
    public init(isRefreshing: Bool = false, lastSuccessAt: Date? = nil, message: String? = nil, isSaved: Bool = false) {
        self.isRefreshing = isRefreshing
        self.lastSuccessAt = lastSuccessAt
        self.message = message
        self.isSaved = isSaved
    }
}
