import CoreLocation
import Foundation

public enum FuelType: String, Codable, CaseIterable, Sendable {
    case diesel
    case gasoline

    public var displayName: String {
        switch self {
        case .diesel:
            "Diesel"
        case .gasoline:
            "Gasoline"
        }
    }
}

public enum FuelPriceStatus: String, Codable, Equatable, Sendable {
    case ready
    case unsupported
    case locationRequired
    case configurationRequired
    case unavailable
    case noStationsFound
}

public struct FuelSearchRequest: Equatable, Sendable {
    public let coordinate: CLLocationCoordinate2D
    public let countryCode: String
    public let countryName: String?
    public let searchRadiusKilometers: Double

    public init(
        coordinate: CLLocationCoordinate2D,
        countryCode: String,
        countryName: String?,
        searchRadiusKilometers: Double = 50
    ) {
        self.coordinate = coordinate
        self.countryCode = countryCode
        self.countryName = countryName
        self.searchRadiusKilometers = searchRadiusKilometers
    }

    public static func == (lhs: FuelSearchRequest, rhs: FuelSearchRequest) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.countryCode == rhs.countryCode
            && lhs.countryName == rhs.countryName
            && lhs.searchRadiusKilometers == rhs.searchRadiusKilometers
    }
}

public struct FuelStationPrice: Equatable, Sendable {
    public let fuelType: FuelType
    public let stationName: String
    public let address: String?
    public let locality: String?
    public let pricePerLiter: Double
    public let currencyCode: String
    public let distanceKilometers: Double
    public let latitude: Double
    public let longitude: Double
    public let updatedAt: Date?
    public let isSelfService: Bool?

    public init(
        fuelType: FuelType,
        stationName: String,
        address: String?,
        locality: String?,
        pricePerLiter: Double,
        currencyCode: String = "EUR",
        distanceKilometers: Double,
        latitude: Double,
        longitude: Double,
        updatedAt: Date?,
        isSelfService: Bool? = nil
    ) {
        self.fuelType = fuelType
        self.stationName = stationName
        self.address = address
        self.locality = locality
        self.pricePerLiter = pricePerLiter
        self.currencyCode = currencyCode
        self.distanceKilometers = distanceKilometers
        self.latitude = latitude
        self.longitude = longitude
        self.updatedAt = updatedAt
        self.isSelfService = isSelfService
    }
}

public struct FuelPriceSnapshot: Equatable, Sendable {
    public let status: FuelPriceStatus
    public let sourceName: String
    public let sourceURL: URL?
    public let countryCode: String?
    public let countryName: String?
    public let searchRadiusKilometers: Double
    public let diesel: FuelStationPrice?
    public let gasoline: FuelStationPrice?
    public let fetchedAt: Date?
    public let detail: String?
    public let note: String?

    public init(
        status: FuelPriceStatus,
        sourceName: String,
        sourceURL: URL?,
        countryCode: String?,
        countryName: String?,
        searchRadiusKilometers: Double,
        diesel: FuelStationPrice?,
        gasoline: FuelStationPrice?,
        fetchedAt: Date?,
        detail: String?,
        note: String? = nil
    ) {
        self.status = status
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.countryCode = countryCode
        self.countryName = countryName
        self.searchRadiusKilometers = searchRadiusKilometers
        self.diesel = diesel
        self.gasoline = gasoline
        self.fetchedAt = fetchedAt
        self.detail = detail
        self.note = note
    }

    public var availableFuelTypes: [FuelType] {
        FuelType.allCases.filter { fuelType in
            switch fuelType {
            case .diesel:
                diesel != nil
            case .gasoline:
                gasoline != nil
            }
        }
    }
}
