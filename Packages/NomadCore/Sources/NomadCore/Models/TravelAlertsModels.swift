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

public enum TravelAlertSignalStatus: String, Codable, CaseIterable, Equatable, Sendable {
    case checking
    case ready
    case stale
    case unavailable
}

public enum TravelAlertUnavailableReason: String, Codable, CaseIterable, Equatable, Sendable {
    case countryRequired
    case locationRequired
    case sourceUnavailable
    case sourceConfigurationRequired
}

public struct TravelAlertSourceDescriptor: Codable, Equatable, Sendable {
    public let name: String
    public let url: URL?

    public init(name: String, url: URL?) {
        self.name = name
        self.url = url
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

    public var id: TravelAlertKind {
        kind
    }

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

public struct TravelAlertSignalState: Codable, Equatable, Sendable, Identifiable {
    public let kind: TravelAlertKind
    public let status: TravelAlertSignalStatus
    public let signal: TravelAlertSignalSnapshot?
    public let reason: TravelAlertUnavailableReason?
    public let diagnosticSummary: String?
    public let sourceName: String
    public let sourceURL: URL?
    public let lastAttemptedAt: Date?
    public let lastSuccessAt: Date?

    public var id: TravelAlertKind {
        kind
    }

    public init(
        kind: TravelAlertKind,
        status: TravelAlertSignalStatus,
        signal: TravelAlertSignalSnapshot?,
        reason: TravelAlertUnavailableReason?,
        diagnosticSummary: String? = nil,
        sourceName: String,
        sourceURL: URL?,
        lastAttemptedAt: Date?,
        lastSuccessAt: Date?
    ) {
        self.kind = kind
        self.status = status
        self.signal = signal
        self.reason = reason
        self.diagnosticSummary = diagnosticSummary
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.lastAttemptedAt = lastAttemptedAt
        self.lastSuccessAt = lastSuccessAt
    }

    public var resolvedSignal: TravelAlertSignalSnapshot? {
        switch status {
        case .ready, .stale:
            signal
        case .checking, .unavailable:
            nil
        }
    }

    public var highestSeverity: TravelAlertSeverity? {
        resolvedSignal?.severity
    }
}

public struct TravelAlertsSnapshot: Codable, Equatable, Sendable {
    public let enabledKinds: [TravelAlertKind]
    public let primaryCountryCode: String?
    public let primaryCountryName: String?
    public let coverageCountryCodes: [String]
    public let states: [TravelAlertSignalState]
    public let fetchedAt: Date?

    public init(
        enabledKinds: [TravelAlertKind],
        primaryCountryCode: String?,
        primaryCountryName: String?,
        coverageCountryCodes: [String],
        states: [TravelAlertSignalState],
        fetchedAt: Date?
    ) {
        self.enabledKinds = enabledKinds
        self.primaryCountryCode = primaryCountryCode
        self.primaryCountryName = primaryCountryName
        self.coverageCountryCodes = coverageCountryCodes
        self.states = states.sorted { $0.kind.sortOrder < $1.kind.sortOrder }
        self.fetchedAt = fetchedAt
    }

    public func state(for kind: TravelAlertKind) -> TravelAlertSignalState? {
        states.first { $0.kind == kind }
    }

    public func signal(for kind: TravelAlertKind) -> TravelAlertSignalSnapshot? {
        state(for: kind)?.resolvedSignal
    }

    public var highestSeverity: TravelAlertSeverity {
        states.compactMap(\.highestSeverity).max() ?? .clear
    }

    public var hasStaleStates: Bool {
        states.contains { $0.status == .stale }
    }

    public var hasUnavailableStates: Bool {
        states.contains { $0.status == .unavailable }
    }

    public var allResolvedClear: Bool {
        enabledKinds.isEmpty == false
            && states.count == enabledKinds.count
            && states.allSatisfy { $0.status == .ready && $0.signal?.severity == .clear }
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
        useCurrentLocationForWeather || fuelPricesEnabled || emergencyCareEnabled || travelWeatherAlertsEnabled || visitedPlacesEnabled
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
