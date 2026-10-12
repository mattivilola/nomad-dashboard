import CoreLocation
import Foundation

public enum LocalPriceLevelStatus: String, Codable, Equatable, Sendable {
    case ready
    case partial
    case locationRequired
    case configurationRequired
    case unsupported
    case unavailable
}

public enum LocalPriceSummaryBand: String, Codable, Equatable, Sendable {
    case low
    case medium
    case high
    case limited

    public var displayName: String {
        switch self {
        case .low:
            "Low"
        case .medium:
            "Medium"
        case .high:
            "High"
        case .limited:
            "Limited"
        }
    }
}

public enum LocalPriceIndicatorKind: String, Codable, CaseIterable, Equatable, Sendable {
    case mealOut
    case groceries
    case rentOneBedroom
    case overall

    public var displayName: String {
        switch self {
        case .mealOut:
            "Meal Out"
        case .groceries:
            "Groceries"
        case .rentOneBedroom:
            "1BR Rent"
        case .overall:
            "Overall"
        }
    }
}

public enum LocalPricePrecision: String, Codable, Equatable, Sendable {
    case countryFallback
    case countyBenchmark
    case metroBenchmark

    public var displayName: String {
        switch self {
        case .countryFallback:
            "Country fallback"
        case .countyBenchmark:
            "County benchmark"
        case .metroBenchmark:
            "Metro benchmark"
        }
    }
}

public struct LocalPriceSourceAttribution: Codable, Equatable, Sendable, Hashable {
    public let name: String
    public let url: URL?

    public init(name: String, url: URL?) {
        self.name = name
        self.url = url
    }
}

public struct LocalPriceIndicatorRow: Codable, Equatable, Sendable, Identifiable {
    public let kind: LocalPriceIndicatorKind
    public let value: String
    public let detail: String
    public let precision: LocalPricePrecision
    public let source: LocalPriceSourceAttribution
    /// Signed whole-percent difference from the EU average (-4 means 4% below), the same number the
    /// detail text is built from. Nil when the row has no EU comparison, e.g. the US HUD rent row.
    /// Optional so snapshots cached before this field existed still decode.
    public let differenceFromEUPercent: Double?

    public init(
        kind: LocalPriceIndicatorKind,
        value: String,
        detail: String,
        precision: LocalPricePrecision,
        source: LocalPriceSourceAttribution,
        differenceFromEUPercent: Double? = nil
    ) {
        self.kind = kind
        self.value = value
        self.detail = detail
        self.precision = precision
        self.source = source
        self.differenceFromEUPercent = differenceFromEUPercent
    }

    public var id: LocalPriceIndicatorKind {
        kind
    }
}

public struct LocalPriceSearchRequest: Equatable, Sendable {
    public let coordinate: CLLocationCoordinate2D?
    public let countryCode: String
    public let countryName: String?
    public let locality: String?
    /// The user's home country (ISO 3166-1 alpha-2). When set, the provider also compares the current
    /// country's price levels with it; only this code is ever sent for the extra lookup.
    public let homeCountryCode: String?

    public init(
        coordinate: CLLocationCoordinate2D?,
        countryCode: String,
        countryName: String?,
        locality: String?,
        homeCountryCode: String? = nil
    ) {
        self.coordinate = coordinate
        self.countryCode = countryCode
        self.countryName = countryName
        self.locality = locality
        self.homeCountryCode = homeCountryCode
    }

    public static func == (lhs: LocalPriceSearchRequest, rhs: LocalPriceSearchRequest) -> Bool {
        lhs.coordinate?.latitude == rhs.coordinate?.latitude
            && lhs.coordinate?.longitude == rhs.coordinate?.longitude
            && lhs.countryCode == rhs.countryCode
            && lhs.countryName == rhs.countryName
            && lhs.locality == rhs.locality
            && lhs.homeCountryCode == rhs.homeCountryCode
    }
}

public struct LocalPriceLevelSnapshot: Codable, Equatable, Sendable {
    public let status: LocalPriceLevelStatus
    public let summaryBand: LocalPriceSummaryBand?
    public let countryCode: String?
    public let countryName: String?
    public let rows: [LocalPriceIndicatorRow]
    public let sources: [LocalPriceSourceAttribution]
    public let fetchedAt: Date?
    public let detail: String?
    public let note: String?
    /// How this country's price levels compare with the user's home country, per category. Nil when no
    /// home country is set, it equals this country, or either side has no Eurostat data. Optional so
    /// snapshots cached before this field existed still decode.
    public let homeComparison: [PriceLevelDifference]?
    /// The home country `homeComparison` was computed against.
    public let homeCountryCode: String?

    public init(
        status: LocalPriceLevelStatus,
        summaryBand: LocalPriceSummaryBand?,
        countryCode: String?,
        countryName: String?,
        rows: [LocalPriceIndicatorRow],
        sources: [LocalPriceSourceAttribution],
        fetchedAt: Date?,
        detail: String?,
        note: String?,
        homeComparison: [PriceLevelDifference]? = nil,
        homeCountryCode: String? = nil
    ) {
        self.status = status
        self.summaryBand = summaryBand
        self.countryCode = countryCode
        self.countryName = countryName
        self.rows = rows
        self.sources = sources
        self.fetchedAt = fetchedAt
        self.detail = detail
        self.note = note
        self.homeComparison = homeComparison
        self.homeCountryCode = homeCountryCode
    }

    /// This snapshot with the given home comparison attached.
    public func withHomeComparison(_ comparison: [PriceLevelDifference], homeCountryCode: String) -> LocalPriceLevelSnapshot {
        LocalPriceLevelSnapshot(
            status: status,
            summaryBand: summaryBand,
            countryCode: countryCode,
            countryName: countryName,
            rows: rows,
            sources: sources,
            fetchedAt: fetchedAt,
            detail: detail,
            note: note,
            homeComparison: comparison,
            homeCountryCode: homeCountryCode
        )
    }
}
