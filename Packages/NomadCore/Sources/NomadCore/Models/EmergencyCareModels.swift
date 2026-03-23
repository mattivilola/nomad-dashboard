import CoreLocation
import Foundation

public enum HospitalOwnership: String, Codable, Equatable, Sendable {
    case `public`
    case `private`
    case unknown

    public var displayName: String {
        switch self {
        case .public:
            "Public"
        case .private:
            "Private"
        case .unknown:
            "Unknown"
        }
    }
}

public enum EmergencyCareStatus: String, Codable, Equatable, Sendable {
    case ready
    case locationRequired
    case unavailable
    case noHospitalsFound
}

public struct EmergencyCareSearchRequest: Equatable, Sendable {
    public let coordinate: CLLocationCoordinate2D
    public let searchRadiusKilometers: Double
    public let maximumResults: Int

    public init(
        coordinate: CLLocationCoordinate2D,
        searchRadiusKilometers: Double = 25,
        maximumResults: Int = 3
    ) {
        self.coordinate = coordinate
        self.searchRadiusKilometers = searchRadiusKilometers
        self.maximumResults = maximumResults
    }

    public static func == (lhs: EmergencyCareSearchRequest, rhs: EmergencyCareSearchRequest) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.searchRadiusKilometers == rhs.searchRadiusKilometers
            && lhs.maximumResults == rhs.maximumResults
    }
}

public struct EmergencyHospital: Equatable, Sendable, Identifiable {
    public let name: String
    public let address: String?
    public let locality: String?
    public let distanceKilometers: Double
    public let latitude: Double
    public let longitude: Double
    public let ownership: HospitalOwnership

    public init(
        name: String,
        address: String?,
        locality: String?,
        distanceKilometers: Double,
        latitude: Double,
        longitude: Double,
        ownership: HospitalOwnership
    ) {
        self.name = name
        self.address = address
        self.locality = locality
        self.distanceKilometers = distanceKilometers
        self.latitude = latitude
        self.longitude = longitude
        self.ownership = ownership
    }

    public var id: String {
        "\(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(latitude)|\(longitude)"
    }
}

public struct EmergencyHospitalMapDestination: Identifiable, Equatable, Sendable {
    public let hospitalName: String
    public let address: String?
    public let locality: String?
    public let ownership: HospitalOwnership
    public let latitude: Double
    public let longitude: Double

    public init(
        hospitalName: String,
        address: String?,
        locality: String?,
        ownership: HospitalOwnership,
        latitude: Double,
        longitude: Double
    ) {
        self.hospitalName = hospitalName
        self.address = address
        self.locality = locality
        self.ownership = ownership
        self.latitude = latitude
        self.longitude = longitude
    }

    public var id: String {
        "\(hospitalName)|\(latitude)|\(longitude)"
    }

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    public var isCoordinateValid: Bool {
        CLLocationCoordinate2DIsValid(coordinate)
    }

    public var addressLine: String? {
        let combined = [address, locality]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: ", ")
        return combined.isEmpty ? nil : combined
    }

    public var googleMapsURL: URL? {
        if isCoordinateValid {
            var components = URLComponents(string: "https://www.google.com/maps/dir/")!
            components.queryItems = [
                URLQueryItem(name: "api", value: "1"),
                URLQueryItem(name: "destination", value: "\(latitude),\(longitude)"),
                URLQueryItem(name: "travelmode", value: "driving")
            ]
            return components.url
        }

        let fallbackQuery = [hospitalName, addressLine]
            .compactMap(\.self)
            .joined(separator: ", ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard fallbackQuery.isEmpty == false else {
            return nil
        }

        var components = URLComponents(string: "https://www.google.com/maps/search/")!
        components.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: fallbackQuery)
        ]
        return components.url
    }
}

public struct EmergencyCareSnapshot: Equatable, Sendable {
    public let status: EmergencyCareStatus
    public let sourceName: String
    public let sourceURL: URL?
    public let searchRadiusKilometers: Double
    public let hospitals: [EmergencyHospital]
    public let fetchedAt: Date?
    public let detail: String?

    public init(
        status: EmergencyCareStatus,
        sourceName: String,
        sourceURL: URL?,
        searchRadiusKilometers: Double,
        hospitals: [EmergencyHospital],
        fetchedAt: Date?,
        detail: String?
    ) {
        self.status = status
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.searchRadiusKilometers = searchRadiusKilometers
        self.hospitals = hospitals
        self.fetchedAt = fetchedAt
        self.detail = detail
    }
}
