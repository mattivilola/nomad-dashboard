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

public struct LocalPriceSourceAttribution: Equatable, Sendable, Hashable {
    public let name: String
    public let url: URL?

    public init(name: String, url: URL?) {
        self.name = name
        self.url = url
    }
}

public struct LocalPriceIndicatorRow: Equatable, Sendable, Identifiable {
    public let kind: LocalPriceIndicatorKind
    public let value: String
    public let detail: String
    public let precision: LocalPricePrecision
    public let source: LocalPriceSourceAttribution

    public init(
        kind: LocalPriceIndicatorKind,
        value: String,
        detail: String,
        precision: LocalPricePrecision,
        source: LocalPriceSourceAttribution
    ) {
        self.kind = kind
        self.value = value
        self.detail = detail
        self.precision = precision
        self.source = source
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

    public init(
        coordinate: CLLocationCoordinate2D?,
        countryCode: String,
        countryName: String?,
        locality: String?
    ) {
        self.coordinate = coordinate
        self.countryCode = countryCode
        self.countryName = countryName
        self.locality = locality
    }

    public static func == (lhs: LocalPriceSearchRequest, rhs: LocalPriceSearchRequest) -> Bool {
        lhs.coordinate?.latitude == rhs.coordinate?.latitude
            && lhs.coordinate?.longitude == rhs.coordinate?.longitude
            && lhs.countryCode == rhs.countryCode
            && lhs.countryName == rhs.countryName
            && lhs.locality == rhs.locality
    }
}

public struct LocalPriceLevelSnapshot: Equatable, Sendable {
    public let status: LocalPriceLevelStatus
    public let summaryBand: LocalPriceSummaryBand?
    public let countryCode: String?
    public let countryName: String?
    public let rows: [LocalPriceIndicatorRow]
    public let sources: [LocalPriceSourceAttribution]
    public let fetchedAt: Date?
    public let detail: String?
    public let note: String?

    public init(
        status: LocalPriceLevelStatus,
        summaryBand: LocalPriceSummaryBand?,
        countryCode: String?,
        countryName: String?,
        rows: [LocalPriceIndicatorRow],
        sources: [LocalPriceSourceAttribution],
        fetchedAt: Date?,
        detail: String?,
        note: String?
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
    }
}
