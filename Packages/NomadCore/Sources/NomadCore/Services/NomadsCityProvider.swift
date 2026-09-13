import Foundation

public enum NomadsProviderError: Error, LocalizedError, Sendable {
    case invalidSearch(String)
    case unavailable
    case rateLimited(until: Date?)
    case unknownCity

    public var errorDescription: String? {
        switch self {
        case let .invalidSearch(reason): return "That city search is invalid: \(reason)"
        case .unavailable: return "Nomads.com is unavailable right now."
        case let .rateLimited(until):
            guard let until else { return "Nomads.com is temporarily rate limited. Please try again later." }
            let time = DateFormatter.localizedString(from: until, dateStyle: .none, timeStyle: .short)
            return "Nomads.com is temporarily rate limited. Please try again after \(time)."
        case .unknownCity: return "That city could not be found on Nomads.com."
        }
    }
}

public actor NomadsCityProvider {
    private static let baseURL = URL(string: "https://nomads.com/api/")!
    private static let cacheTTL: TimeInterval = 6 * 60 * 60
    private static let maxSearchCacheEntries = 32
    private static let maxCityCacheEntries = 128
    private static let requestLimit = 60
    private static let requestWindow: TimeInterval = 60 * 60

    private let session: URLSession
    private let now: @Sendable () -> Date
    private var searchCache: [NomadsCitySearch: Cached<NomadsSearchResult>] = [:]
    private var cityCache: [String: Cached<NomadsCity>] = [:]
    private var inFlightSearches: [NomadsCitySearch: Task<NomadsSearchResult, Error>] = [:]
    private var inFlightCities: [String: Task<NomadsCity, Error>] = [:]
    private var directoryCache: Cached<[NomadsDirectoryCity]>?
    private var inFlightDirectory: Task<[NomadsDirectoryCity], Error>?
    private var requestTimes: [Date] = []
    private var cooldownUntil: Date?

    public init(session: URLSession? = nil, now: @escaping @Sendable () -> Date = Date.init) {
        self.session = session ?? Self.makeSession()
        self.now = now
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }

    public func search(_ query: NomadsCitySearch) async throws -> NomadsSearchResult {
        try Task.checkCancellation()
        try validate(query)
        if let cached = searchCache[query], isFresh(cached) {
            return cached.value
        }
        if let task = inFlightSearches[query] {
            do { return try await task.value }
            catch { throw record(error) }
        }

        try reserveRequest()
        let session = session
        let fetchedAt = now
        let task = Task { try await Self.fetchSearch(query, session: session, fetchedAt: fetchedAt) }
        inFlightSearches[query] = task
        do {
            let value = try await task.value
            inFlightSearches[query] = nil
            searchCache[query] = Cached(value: value, fetchedAt: now())
            trim(&searchCache, maximum: Self.maxSearchCacheEntries)
            return value
        } catch {
            inFlightSearches[query] = nil
            throw record(error)
        }
    }

    public func city(slug: String) async throws -> NomadsCity {
        try Task.checkCancellation()
        let slug = try validatedSlug(slug)
        if let cached = cityCache[slug], isFresh(cached) {
            return cached.value
        }
        if let task = inFlightCities[slug] {
            do { return try await task.value }
            catch { throw record(error) }
        }

        try reserveRequest()
        let session = session
        let current = now
        let task = Task { try await Self.fetchCity(slug: slug, session: session, current: current) }
        inFlightCities[slug] = task
        do {
            let value = try await task.value
            inFlightCities[slug] = nil
            cityCache[slug] = Cached(value: value, fetchedAt: now())
            trim(&cityCache, maximum: Self.maxCityCacheEntries)
            return value
        } catch {
            inFlightCities[slug] = nil
            throw record(error)
        }
    }

    /// Returns the documented public city directory. The response is coalesced and cached for this provider's lifetime.
    public func directory() async throws -> [NomadsDirectoryCity] {
        try Task.checkCancellation()
        if let directoryCache {
            return directoryCache.value
        }
        if let task = inFlightDirectory {
            do { return try await task.value }
            catch { throw record(error) }
        }

        try reserveRequest()
        let session = session
        let current = now
        let task = Task { try await Self.fetchDirectory(session: session, current: current) }
        inFlightDirectory = task
        do {
            let value = try await task.value
            inFlightDirectory = nil
            directoryCache = Cached(value: value, fetchedAt: now())
            return value
        } catch {
            inFlightDirectory = nil
            throw record(error)
        }
    }

    private func validate(_ query: NomadsCitySearch) throws {
        if query.country.count > 100 {
            throw NomadsProviderError.invalidSearch("country is too long")
        }
        if let maxCostUSD = query.maxCostUSD, maxCostUSD <= 0 {
            throw NomadsProviderError.invalidSearch("maximum monthly cost must be positive")
        }
        if let minInternetMbps = query.minInternetMbps, minInternetMbps < 0 {
            throw NomadsProviderError.invalidSearch("minimum internet speed cannot be negative")
        }
    }

    private func validatedSlug(_ rawSlug: String) throws -> String {
        let slug = rawSlug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        guard !slug.isEmpty, slug.count <= 100, slug.unicodeScalars.allSatisfy(allowed.contains),
              !slug.hasPrefix("-"), !slug.hasSuffix("-"), !slug.contains("--")
        else { throw NomadsProviderError.invalidSearch("city slug is invalid") }
        return slug
    }

    private func reserveRequest() throws {
        let current = now()
        if let cooldownUntil, cooldownUntil > current {
            throw NomadsProviderError.rateLimited(until: cooldownUntil)
        }
        requestTimes.removeAll { current.timeIntervalSince($0) >= Self.requestWindow }
        guard requestTimes.count < Self.requestLimit else { throw NomadsProviderError.rateLimited(until: requestTimes.first?.addingTimeInterval(Self.requestWindow)) }
        requestTimes.append(current)
    }

    private func record(_ error: Error) -> Error {
        guard case let NetworkError.rateLimited(retryAfter) = error else { return error }
        let until = retryAfter ?? now().addingTimeInterval(Self.requestWindow)
        cooldownUntil = max(cooldownUntil ?? .distantPast, until)
        return NomadsProviderError.rateLimited(until: cooldownUntil)
    }

    private func isFresh(_ cached: Cached<some Any>) -> Bool {
        now().timeIntervalSince(cached.fetchedAt) < Self.cacheTTL
    }

    private func trim(_ cache: inout [some Hashable: Cached<some Any>], maximum: Int) {
        while cache.count > maximum, let oldest = cache.min(by: { $0.value.fetchedAt < $1.value.fetchedAt })?.key {
            cache.removeValue(forKey: oldest)
        }
    }

    private static func fetchSearch(_ query: NomadsCitySearch, session: URLSession, fetchedAt: @Sendable () -> Date) async throws -> NomadsSearchResult {
        var components = URLComponents(url: baseURL.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "limit", value: "20")]
        if !query.country.isEmpty {
            items.append(URLQueryItem(name: "country", value: query.country))
        }
        if let value = query.maxCostUSD {
            items.append(URLQueryItem(name: "max_cost_usd", value: String(value)))
        }
        if let value = query.minInternetMbps {
            items.append(URLQueryItem(name: "min_internet_mbps", value: String(value)))
        }
        components.queryItems = items
        let response: SearchResponse = try await request(components.url!, session: session, now: fetchedAt)
        return NomadsSearchResult(cities: response.cities, fetchedAt: fetchedAt())
    }

    private static func fetchCity(slug: String, session: URLSession, current: @Sendable () -> Date) async throws -> NomadsCity {
        let url = baseURL.appendingPathComponent("city").appendingPathComponent(slug)
        let response: CityResponse = try await request(url, session: session, now: current)
        return response.city
    }

    private static func fetchDirectory(session: URLSession, current: @Sendable () -> Date) async throws -> [NomadsDirectoryCity] {
        let response: DirectoryResponse = try await request(baseURL.appendingPathComponent("cities"), session: session, now: current)
        return response.cities
    }

    private static func request<Response: Decodable>(
        _ url: URL,
        session: URLSession,
        now: @Sendable () -> Date
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw NomadsProviderError.unavailable }
            if http.statusCode == 429 {
                throw NetworkError.rateLimited(retryAfter: retryAfter(from: http, responseTime: now()))
            }
            if http.statusCode == 404 {
                throw NomadsProviderError.unknownCity
            }
            guard (200...299).contains(http.statusCode) else { throw NomadsProviderError.unavailable }
            do { return try JSONDecoder().decode(Response.self, from: data) }
            catch { throw NomadsProviderError.unavailable }
        } catch let error as NomadsProviderError { throw error }
        catch let error as NetworkError { throw error }
        catch { throw NomadsProviderError.unavailable }
    }

    private static func retryAfter(from response: HTTPURLResponse, responseTime: Date) -> Date? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if let seconds = TimeInterval(raw), seconds.isFinite, seconds >= 0 {
            return responseTime.addingTimeInterval(seconds)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: raw)
    }
}

private struct Cached<Value> { let value: Value
    let fetchedAt: Date
}

private struct SearchResponse: Decodable { let cities: [NomadsCity] }
private struct CityResponse: Decodable { let city: NomadsCity }
private struct DirectoryResponse: Decodable { let cities: [NomadsDirectoryCity] }
private enum NetworkError: Error { case rateLimited(retryAfter: Date?) }
