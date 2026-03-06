import Foundation

public enum TravelAlertKind: String, Codable, CaseIterable, Equatable, Sendable {
    case advisory
    case weather
    case security
}

public enum TravelAlertSeverity: String, Codable, CaseIterable, Equatable, Sendable, Comparable {
    case clear
    case info
    case caution
    case warning
    case critical

    public static func < (lhs: TravelAlertSeverity, rhs: TravelAlertSeverity) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .clear:
            0
        case .info:
            1
        case .caution:
            2
        case .warning:
            3
        case .critical:
            4
        }
    }
}

public struct TravelAlertSignalSnapshot: Codable, Equatable, Sendable, Identifiable {
    public let kind: TravelAlertKind
    public let severity: TravelAlertSeverity
    public let title: String
    public let summary: String
    public let sourceName: String
    public let sourceURL: URL?
    public let updatedAt: Date
    public let affectedCountryCodes: [String]
    public let itemCount: Int?

    public var id: TravelAlertKind { kind }

    public init(
        kind: TravelAlertKind,
        severity: TravelAlertSeverity,
        title: String,
        summary: String,
        sourceName: String,
        sourceURL: URL?,
        updatedAt: Date,
        affectedCountryCodes: [String],
        itemCount: Int? = nil
    ) {
        self.kind = kind
        self.severity = severity
        self.title = title
        self.summary = summary
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.updatedAt = updatedAt
        self.affectedCountryCodes = affectedCountryCodes
        self.itemCount = itemCount
    }
}

public struct TravelAlertsSnapshot: Codable, Equatable, Sendable {
    public let enabledKinds: [TravelAlertKind]
    public let primaryCountryCode: String?
    public let primaryCountryName: String?
    public let coverageCountryCodes: [String]
    public let signals: [TravelAlertSignalSnapshot]
    public let fetchedAt: Date?

    public init(
        enabledKinds: [TravelAlertKind],
        primaryCountryCode: String?,
        primaryCountryName: String?,
        coverageCountryCodes: [String],
        signals: [TravelAlertSignalSnapshot],
        fetchedAt: Date?
    ) {
        self.enabledKinds = enabledKinds
        self.primaryCountryCode = primaryCountryCode
        self.primaryCountryName = primaryCountryName
        self.coverageCountryCodes = coverageCountryCodes
        self.signals = signals.sorted { $0.kind.sortOrder < $1.kind.sortOrder }
        self.fetchedAt = fetchedAt
    }

    public func signal(for kind: TravelAlertKind) -> TravelAlertSignalSnapshot? {
        signals.first { $0.kind == kind }
    }

    public var highestSeverity: TravelAlertSeverity {
        signals.map(\.severity).max() ?? .clear
    }
}

public struct TravelAlertPreferences: Equatable, Sendable {
    public let advisoryEnabled: Bool
    public let weatherEnabled: Bool
    public let securityEnabled: Bool

    public init(advisoryEnabled: Bool, weatherEnabled: Bool, securityEnabled: Bool) {
        self.advisoryEnabled = advisoryEnabled
        self.weatherEnabled = weatherEnabled
        self.securityEnabled = securityEnabled
    }

    public var enabledKinds: [TravelAlertKind] {
        TravelAlertKind.allCases.filter { kind in
            switch kind {
            case .advisory:
                advisoryEnabled
            case .weather:
                weatherEnabled
            case .security:
                securityEnabled
            }
        }
    }
}

public extension AppSettings {
    var travelAlertPreferences: TravelAlertPreferences {
        TravelAlertPreferences(
            advisoryEnabled: travelAdvisoryEnabled,
            weatherEnabled: travelWeatherAlertsEnabled,
            securityEnabled: regionalSecurityEnabled
        )
    }

    var usesDeviceLocation: Bool {
        useCurrentLocationForWeather || travelWeatherAlertsEnabled
    }
}

private extension TravelAlertKind {
    var sortOrder: Int {
        switch self {
        case .advisory:
            0
        case .weather:
            1
        case .security:
            2
        }
    }
}
