import CoreLocation
import Foundation

public enum VisitedPlaceSource: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case deviceLocation
    case publicIPGeolocation
}

public struct VisitedPlaceInput: Equatable, Sendable {
    public let city: String?
    public let region: String?
    public let country: String
    public let countryCode: String?
    public let latitude: Double?
    public let longitude: Double?
    public let source: VisitedPlaceSource
    public let visitedAt: Date

    public init(
        city: String?,
        region: String?,
        country: String,
        countryCode: String?,
        latitude: Double?,
        longitude: Double?,
        source: VisitedPlaceSource,
        visitedAt: Date
    ) {
        self.city = city
        self.region = region
        self.country = country
        self.countryCode = countryCode
        self.latitude = latitude
        self.longitude = longitude
        self.source = source
        self.visitedAt = visitedAt
    }
}

public struct VisitedPlace: Codable, Equatable, Sendable, Identifiable {
    public let city: String?
    public let region: String?
    public let country: String
    public let countryCode: String?
    public let latitude: Double?
    public let longitude: Double?
    public let firstVisitedAt: Date
    public let lastVisitedAt: Date
    public let sources: [VisitedPlaceSource]

    public init(
        city: String?,
        region: String?,
        country: String,
        countryCode: String?,
        latitude: Double?,
        longitude: Double?,
        firstVisitedAt: Date,
        lastVisitedAt: Date,
        sources: [VisitedPlaceSource]
    ) {
        self.city = Self.normalizedValue(city)
        self.region = Self.normalizedValue(region)
        self.country = country.trimmingCharacters(in: .whitespacesAndNewlines)
        self.countryCode = Self.normalizedCountryCode(countryCode)
        self.latitude = latitude
        self.longitude = longitude
        self.firstVisitedAt = firstVisitedAt
        self.lastVisitedAt = lastVisitedAt
        self.sources = sources.uniqued()
    }

    public var id: String {
        Self.storageKey(countryCode: countryCode, country: country, city: city)
    }

    public var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else {
            return nil
        }

        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    public var displayName: String {
        [city, country]
            .compactMap { value in
                guard let value, value.isEmpty == false else {
                    return nil
                }

                return value
            }
            .joined(separator: ", ")
    }

    public var supportsMapPin: Bool {
        city?.isEmpty == false && coordinate != nil
    }

    func merging(input: VisitedPlaceInput) -> VisitedPlace {
        let normalizedInput = Self.normalized(input)
        let sources = (self.sources + [normalizedInput.source]).uniqued()
        let preferredReplacement = normalizedInput.source == .deviceLocation || coordinate == nil

        return VisitedPlace(
            city: normalizedInput.city ?? city,
            region: normalizedInput.region ?? region,
            country: normalizedInput.country.isEmpty == false ? normalizedInput.country : country,
            countryCode: normalizedInput.countryCode ?? countryCode,
            latitude: preferredReplacement ? normalizedInput.latitude ?? latitude : latitude ?? normalizedInput.latitude,
            longitude: preferredReplacement ? normalizedInput.longitude ?? longitude : longitude ?? normalizedInput.longitude,
            firstVisitedAt: min(firstVisitedAt, normalizedInput.visitedAt),
            lastVisitedAt: max(lastVisitedAt, normalizedInput.visitedAt),
            sources: sources
        )
    }

    static func from(_ input: VisitedPlaceInput) -> VisitedPlace? {
        let normalizedInput = normalized(input)
        guard normalizedInput.country.isEmpty == false else {
            return nil
        }

        return VisitedPlace(
            city: normalizedInput.city,
            region: normalizedInput.region,
            country: normalizedInput.country,
            countryCode: normalizedInput.countryCode,
            latitude: normalizedInput.latitude,
            longitude: normalizedInput.longitude,
            firstVisitedAt: normalizedInput.visitedAt,
            lastVisitedAt: normalizedInput.visitedAt,
            sources: [normalizedInput.source]
        )
    }

    static func storageKey(countryCode: String?, country: String, city: String?) -> String {
        let normalizedCountryCode = normalizedCountryCode(countryCode)
        let normalizedCountry = normalizedKeyValue(country)
        let normalizedCity = normalizedKeyValue(city) ?? "__country__"

        if let normalizedCountryCode {
            return "\(normalizedCountryCode)|\(normalizedCity)"
        }

        return "\((normalizedCountry ?? "__unknown__"))|\(normalizedCity)"
    }

    private static func normalized(_ input: VisitedPlaceInput) -> VisitedPlaceInput {
        VisitedPlaceInput(
            city: normalizedValue(input.city),
            region: normalizedValue(input.region),
            country: input.country.trimmingCharacters(in: .whitespacesAndNewlines),
            countryCode: normalizedCountryCode(input.countryCode),
            latitude: input.latitude,
            longitude: input.longitude,
            source: input.source,
            visitedAt: input.visitedAt
        )
    }

    private static func normalizedValue(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), value.isEmpty == false else {
            return nil
        }

        return value
    }

    private static func normalizedCountryCode(_ value: String?) -> String? {
        normalizedValue(value)?.uppercased()
    }

    private static func normalizedKeyValue(_ value: String?) -> String? {
        normalizedValue(value)?
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}

public struct VisitedPlaceSummary: Equatable, Sendable {
    public let citiesVisited: Int
    public let countriesVisited: Int
    public let latestVisitAt: Date?

    public init(citiesVisited: Int, countriesVisited: Int, latestVisitAt: Date?) {
        self.citiesVisited = citiesVisited
        self.countriesVisited = countriesVisited
        self.latestVisitAt = latestVisitAt
    }
}

public extension Array where Element == VisitedPlace {
    var visitedPlaceSummary: VisitedPlaceSummary {
        let countryKeys = compactMap { place in
            if let countryCode = place.countryCode, countryCode.isEmpty == false {
                return countryCode
            }

            return place.country.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        }

        return VisitedPlaceSummary(
            citiesVisited: filter { $0.supportsMapPin }.count,
            countriesVisited: Set(countryKeys).count,
            latestVisitAt: map(\.lastVisitedAt).max()
        )
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
