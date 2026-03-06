import Foundation

public enum ProviderError: Error {
    case invalidResponse
    case missingCoordinate
}

public actor CachedPublicIPProvider: PublicIPProvider {
    private let session: URLSession
    private let ttl: TimeInterval
    private var cachedValue: PublicIPSnapshot?

    public init(session: URLSession = .shared, ttl: TimeInterval = 900) {
        self.session = session
        self.ttl = ttl
    }

    public func currentIP(forceRefresh: Bool) async throws -> PublicIPSnapshot {
        if !forceRefresh, let cachedValue, abs(cachedValue.fetchedAt.timeIntervalSinceNow) < ttl {
            return cachedValue
        }

        let url = URL(string: "https://api64.ipify.org?format=json")!
        let (data, _) = try await session.data(from: url)
        let response = try JSONDecoder().decode(IPifyResponse.self, from: data)
        let snapshot = PublicIPSnapshot(address: response.ip, provider: "ipify", fetchedAt: Date())
        cachedValue = snapshot
        return snapshot
    }
}

public actor CachedIPLocationProvider: PublicIPLocationProvider {
    private let session: URLSession
    private let ttl: TimeInterval
    private var cache: [String: IPLocationSnapshot] = [:]

    public init(session: URLSession = .shared, ttl: TimeInterval = 1800) {
        self.session = session
        self.ttl = ttl
    }

    public func currentLocation(for ipAddress: String, forceRefresh: Bool) async throws -> IPLocationSnapshot {
        if !forceRefresh,
           let cached = cache[ipAddress],
           abs(cached.fetchedAt.timeIntervalSinceNow) < ttl {
            return cached
        }

        let url = URL(string: "https://ipapi.co/\(ipAddress)/json/")!
        let (data, _) = try await session.data(from: url)
        let response = try JSONDecoder().decode(IPAPICoResponse.self, from: data)
        let snapshot = IPLocationSnapshot(
            city: response.city,
            region: response.region,
            country: response.countryName,
            countryCode: response.countryCode,
            latitude: response.latitude,
            longitude: response.longitude,
            timeZone: response.timezone,
            provider: "ipapi.co",
            fetchedAt: Date()
        )
        cache[ipAddress] = snapshot
        return snapshot
    }
}

private struct IPifyResponse: Decodable {
    let ip: String
}

private struct IPAPICoResponse: Decodable {
    let city: String?
    let region: String?
    let countryName: String?
    let countryCode: String?
    let latitude: Double?
    let longitude: Double?
    let timezone: String?

    private enum CodingKeys: String, CodingKey {
        case city
        case region
        case countryName = "country_name"
        case countryCode = "country_code"
        case latitude
        case longitude
        case timezone
    }
}

