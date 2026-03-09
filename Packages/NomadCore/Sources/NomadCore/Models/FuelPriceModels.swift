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

public enum FuelDiagnosticsStage: String, Codable, Equatable, Sendable {
    case locationMissing
    case reverseGeocoding
    case providerSelection
    case requestStarted
    case responseDecoded
    case bestPriceSelection

    public var displayName: String {
        switch self {
        case .locationMissing:
            "Location Missing"
        case .reverseGeocoding:
            "Reverse Geocoding"
        case .providerSelection:
            "Provider Selection"
        case .requestStarted:
            "Request Started"
        case .responseDecoded:
            "Response Decoded"
        case .bestPriceSelection:
            "Best Price Selection"
        }
    }
}

public enum FuelNetworkFailureKind: String, Codable, Equatable, Sendable {
    case dnsResolution
    case tlsHandshake
    case certificateValidation
    case timeout
    case connectivity
    case httpStatus
    case decodeFailure
    case invalidResponse
    case unknown

    public var displayName: String {
        switch self {
        case .dnsResolution:
            "DNS Resolution"
        case .tlsHandshake:
            "TLS Handshake"
        case .certificateValidation:
            "Certificate Validation"
        case .timeout:
            "Timeout"
        case .connectivity:
            "Connectivity"
        case .httpStatus:
            "HTTP Status"
        case .decodeFailure:
            "Decode Failure"
        case .invalidResponse:
            "Invalid Response"
        case .unknown:
            "Unknown"
        }
    }
}

public struct FuelDiagnosticsError: Equatable, Sendable {
    public let failureKind: FuelNetworkFailureKind?
    public let domain: String?
    public let code: Int?
    public let localizedDescription: String
    public let failingURL: URL?
    public let httpStatusCode: Int?
    public let responseMIMEType: String?
    public let payloadByteCount: Int?
    public let urlErrorSymbol: String?
    public let summary: String?

    public init(
        failureKind: FuelNetworkFailureKind?,
        domain: String?,
        code: Int?,
        localizedDescription: String,
        failingURL: URL?,
        httpStatusCode: Int? = nil,
        responseMIMEType: String? = nil,
        payloadByteCount: Int? = nil,
        urlErrorSymbol: String? = nil,
        summary: String? = nil
    ) {
        self.failureKind = failureKind
        self.domain = domain
        self.code = code
        self.localizedDescription = localizedDescription
        self.failingURL = failingURL
        self.httpStatusCode = httpStatusCode
        self.responseMIMEType = responseMIMEType
        self.payloadByteCount = payloadByteCount
        self.urlErrorSymbol = urlErrorSymbol
        self.summary = summary
    }

    public var preferredSummary: String {
        summary ?? localizedDescription
    }
}

public struct FuelDiagnosticsSnapshot: Equatable, Sendable {
    public let status: FuelPriceStatus
    public let stage: FuelDiagnosticsStage
    public let countryCode: String?
    public let countryName: String?
    public let latitude: Double?
    public let longitude: Double?
    public let searchRadiusKilometers: Double
    public let providerName: String?
    public let sourceURL: URL?
    public let startedAt: Date?
    public let finishedAt: Date?
    public let elapsedMilliseconds: Int?
    public let summary: String
    public let error: FuelDiagnosticsError?

    public init(
        status: FuelPriceStatus,
        stage: FuelDiagnosticsStage,
        countryCode: String?,
        countryName: String?,
        latitude: Double?,
        longitude: Double?,
        searchRadiusKilometers: Double,
        providerName: String?,
        sourceURL: URL?,
        startedAt: Date?,
        finishedAt: Date?,
        elapsedMilliseconds: Int?,
        summary: String,
        error: FuelDiagnosticsError?
    ) {
        self.status = status
        self.stage = stage
        self.countryCode = countryCode
        self.countryName = countryName
        self.latitude = latitude
        self.longitude = longitude
        self.searchRadiusKilometers = searchRadiusKilometers
        self.providerName = providerName
        self.sourceURL = sourceURL
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.elapsedMilliseconds = elapsedMilliseconds
        self.summary = summary
        self.error = error
    }

    public var coordinateDescription: String {
        guard let latitude, let longitude else {
            return "n/a"
        }

        return String(format: "%.4f, %.4f", latitude, longitude)
    }

    public func reportText(fuelPrices: FuelPriceSnapshot?) -> String {
        var lines = [
            "Fuel diagnostics",
            "Status: \(status.rawValue)",
            "Stage: \(stage.displayName)",
            "Summary: \(summary)",
            "Country: \(([countryName, countryCode].compactMap { $0 }.joined(separator: " · ")).isEmpty ? "n/a" : [countryName, countryCode].compactMap { $0 }.joined(separator: " · "))",
            "Coordinate: \(coordinateDescription)",
            "Radius km: \(Int(searchRadiusKilometers))",
            "Provider: \(providerName ?? "n/a")",
            "Source URL: \(sourceURL?.absoluteString ?? "n/a")",
            "Started: \(Self.timestampText(startedAt))",
            "Finished: \(Self.timestampText(finishedAt))",
            "Elapsed ms: \(elapsedMilliseconds.map(String.init) ?? "n/a")"
        ]

        if let error {
            lines.append("Failure kind: \(error.failureKind?.displayName ?? "n/a")")
            lines.append("Error domain: \(error.domain ?? "n/a")")
            lines.append("Error code: \(error.code.map(String.init) ?? "n/a")")
            lines.append("URL error symbol: \(error.urlErrorSymbol ?? "n/a")")
            lines.append("Failing URL: \(error.failingURL?.absoluteString ?? "n/a")")
            lines.append("HTTP status: \(error.httpStatusCode.map(String.init) ?? "n/a")")
            lines.append("Response MIME: \(error.responseMIMEType ?? "n/a")")
            lines.append("Payload bytes: \(error.payloadByteCount.map(String.init) ?? "n/a")")
            lines.append("Localized error: \(error.localizedDescription)")
        }

        if let diesel = fuelPrices?.diesel {
            lines.append("Best diesel: \(diesel.stationName) @ \(String(format: "%.3f", diesel.pricePerLiter)) \(diesel.currencyCode)/L (\(String(format: "%.1f", diesel.distanceKilometers)) km)")
        }

        if let gasoline = fuelPrices?.gasoline {
            lines.append("Best gasoline: \(gasoline.stationName) @ \(String(format: "%.3f", gasoline.pricePerLiter)) \(gasoline.currencyCode)/L (\(String(format: "%.1f", gasoline.distanceKilometers)) km)")
        }

        return lines.joined(separator: "\n")
    }

    private static func timestampText(_ date: Date?) -> String {
        guard let date else {
            return "n/a"
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
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

public struct FuelStationMapDestination: Identifiable, Equatable, Sendable {
    public let fuelType: FuelType
    public let stationName: String
    public let address: String?
    public let locality: String?
    public let pricePerLiter: Double
    public let currencyCode: String
    public let latitude: Double
    public let longitude: Double
    public let updatedAt: Date?

    public init(
        fuelType: FuelType,
        stationName: String,
        address: String?,
        locality: String?,
        pricePerLiter: Double,
        currencyCode: String = "EUR",
        latitude: Double,
        longitude: Double,
        updatedAt: Date?
    ) {
        self.fuelType = fuelType
        self.stationName = stationName
        self.address = address
        self.locality = locality
        self.pricePerLiter = pricePerLiter
        self.currencyCode = currencyCode
        self.latitude = latitude
        self.longitude = longitude
        self.updatedAt = updatedAt
    }

    public var id: String {
        "\(fuelType.rawValue)|\(stationName)|\(latitude)|\(longitude)"
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

        let fallbackQuery = [stationName, addressLine]
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
