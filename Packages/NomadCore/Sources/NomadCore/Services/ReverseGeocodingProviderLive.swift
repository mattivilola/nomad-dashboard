import CoreLocation
import Foundation

public struct ReverseGeocodedLocation: Equatable, Sendable {
    public let city: String?
    public let region: String?
    public let country: String?
    public let countryCode: String?
    public let timeZoneIdentifier: String?

    public init(city: String?, region: String?, country: String?, countryCode: String?, timeZoneIdentifier: String?) {
        self.city = city
        self.region = region
        self.country = country
        self.countryCode = countryCode
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

public actor CachedReverseGeocodingProvider: ReverseGeocodingProvider {
    private let geocoder = CLGeocoder()
    private let ttl: TimeInterval
    private var cache: [String: CachedReverseGeocodedLocation] = [:]

    public init(ttl: TimeInterval = 1_800) {
        self.ttl = ttl
    }

    public func details(for location: CLLocation) async throws -> ReverseGeocodedLocation {
        let cacheKey = Self.cacheKey(for: location.coordinate)
        if let cached = cache[cacheKey], abs(cached.fetchedAt.timeIntervalSinceNow) < ttl {
            return cached.location
        }

        let placemarks = try await geocoder.reverseGeocodeLocation(location)
        guard let placemark = placemarks.first else {
            throw ProviderError.invalidResponse
        }

        let location = ReverseGeocodedLocation(
            city: placemark.locality ?? placemark.subLocality ?? placemark.name,
            region: placemark.administrativeArea ?? placemark.subAdministrativeArea,
            country: placemark.country,
            countryCode: placemark.isoCountryCode,
            timeZoneIdentifier: placemark.timeZone?.identifier
        )
        cache[cacheKey] = CachedReverseGeocodedLocation(location: location, fetchedAt: Date())
        return location
    }

    private static func cacheKey(for coordinate: CLLocationCoordinate2D) -> String {
        let latitude = String(format: "%.3f", coordinate.latitude)
        let longitude = String(format: "%.3f", coordinate.longitude)
        return "\(latitude),\(longitude)"
    }
}

private struct CachedReverseGeocodedLocation {
    let location: ReverseGeocodedLocation
    let fetchedAt: Date
}
