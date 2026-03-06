import Foundation

public enum ProviderError: Error {
    case invalidResponse
    case missingCoordinate
    case missingCountryCode
    case missingConfiguration
}

public actor CachedPublicIPProvider: PublicIPProvider {
    private let client: CachedFreeIPAPIClient
    private let ttl: TimeInterval
    private var cachedValue: PublicIPSnapshot?

    public init(session: URLSession = .shared, ttl: TimeInterval = 900) {
        self.client = CachedFreeIPAPIClient(session: session)
        self.ttl = ttl
    }

    init(client: CachedFreeIPAPIClient, ttl: TimeInterval = 900) {
        self.client = client
        self.ttl = ttl
    }

    public func currentIP(forceRefresh: Bool) async throws -> PublicIPSnapshot {
        if !forceRefresh, let cachedValue, abs(cachedValue.fetchedAt.timeIntervalSinceNow) < ttl {
            return cachedValue
        }

        let response = try await client.currentResponse(forceRefresh: forceRefresh)
        let snapshot = try response.publicIPSnapshot(provider: "freeipapi", fetchedAt: Date())
        cachedValue = snapshot
        return snapshot
    }
}

public actor CachedIPLocationProvider: PublicIPLocationProvider {
    private let client: CachedFreeIPAPIClient
    private let ttl: TimeInterval
    private var cache: [String: IPLocationSnapshot] = [:]

    public init(session: URLSession = .shared, ttl: TimeInterval = 1800) {
        self.client = CachedFreeIPAPIClient(session: session)
        self.ttl = ttl
    }

    init(client: CachedFreeIPAPIClient, ttl: TimeInterval = 1800) {
        self.client = client
        self.ttl = ttl
    }

    public func currentLocation(for ipAddress: String, forceRefresh: Bool) async throws -> IPLocationSnapshot {
        if !forceRefresh,
           let cached = cache[ipAddress],
           abs(cached.fetchedAt.timeIntervalSinceNow) < ttl {
            return cached
        }

        let response = try await client.response(for: ipAddress, forceRefresh: forceRefresh)
        let snapshot = response.locationSnapshot(provider: "freeipapi", fetchedAt: Date())
        cache[ipAddress] = snapshot
        return snapshot
    }
}

actor CachedFreeIPAPIClient {
    private let session: URLSession
    private let ttl: TimeInterval
    private var currentCache: CachedResponse?
    private var cacheByAddress: [String: CachedResponse] = [:]

    init(session: URLSession = .shared, ttl: TimeInterval = 900) {
        self.session = session
        self.ttl = ttl
    }

    func currentResponse(forceRefresh: Bool) async throws -> FreeIPAPIResponse {
        if !forceRefresh, let currentCache, isFresh(currentCache) {
            return currentCache.response
        }

        let response = try await fetchResponse(at: FreeIPAPIResponse.baseURL)
        let cached = CachedResponse(response: response, fetchedAt: Date())
        currentCache = cached
        cacheByAddress[response.ipAddress] = cached
        return response
    }

    func response(for ipAddress: String, forceRefresh: Bool) async throws -> FreeIPAPIResponse {
        if !forceRefresh,
           let currentCache,
           currentCache.response.ipAddress == ipAddress,
           isFresh(currentCache) {
            return currentCache.response
        }

        if !forceRefresh, let cached = cacheByAddress[ipAddress], isFresh(cached) {
            return cached.response
        }

        let response = try await fetchResponse(at: FreeIPAPIResponse.baseURL.appendingPathComponent(ipAddress))
        let cached = CachedResponse(response: response, fetchedAt: Date())
        if response.ipAddress == ipAddress {
            cacheByAddress[ipAddress] = cached
        }
        return response
    }

    private func fetchResponse(at url: URL) async throws -> FreeIPAPIResponse {
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw ProviderError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(FreeIPAPIResponse.self, from: data)
        guard decoded.ipAddress.isEmpty == false else {
            throw ProviderError.invalidResponse
        }

        return decoded
    }

    private func isFresh(_ response: CachedResponse) -> Bool {
        abs(response.fetchedAt.timeIntervalSinceNow) < ttl
    }
}

struct FreeIPAPIResponse: Decodable {
    static let baseURL = URL(string: "https://free.freeipapi.com/api/json/")!

    let ipAddress: String
    let cityName: String?
    let regionName: String?
    let countryName: String?
    let countryCode: String?
    let latitude: Double?
    let longitude: Double?
    let timeZones: [String]?

    private enum CodingKeys: String, CodingKey {
        case ipAddress
        case cityName
        case regionName
        case countryName
        case countryCode
        case latitude
        case longitude
        case timeZones
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ipAddress = try container.decode(String.self, forKey: .ipAddress)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        cityName = try container.decodeIfPresent(String.self, forKey: .cityName)
        regionName = try container.decodeIfPresent(String.self, forKey: .regionName)
        countryName = try container.decodeIfPresent(String.self, forKey: .countryName)
        countryCode = try container.decodeIfPresent(String.self, forKey: .countryCode)
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)

        if let values = try? container.decodeIfPresent([String].self, forKey: .timeZones) {
            timeZones = values
        } else if let value = try? container.decode(String.self, forKey: .timeZones) {
            timeZones = [value]
        } else {
            timeZones = nil
        }
    }

    func publicIPSnapshot(provider: String, fetchedAt: Date) throws -> PublicIPSnapshot {
        guard ipAddress.isEmpty == false else {
            throw ProviderError.invalidResponse
        }

        return PublicIPSnapshot(address: ipAddress, provider: provider, fetchedAt: fetchedAt)
    }

    func locationSnapshot(provider: String, fetchedAt: Date) -> IPLocationSnapshot {
        IPLocationSnapshot(
            city: cityName,
            region: regionName,
            country: countryName,
            countryCode: countryCode,
            latitude: latitude,
            longitude: longitude,
            timeZone: timeZones?.first,
            provider: provider,
            fetchedAt: fetchedAt
        )
    }
}

private struct CachedResponse {
    let response: FreeIPAPIResponse
    let fetchedAt: Date
}
