import Foundation
@testable import NomadCore
import Testing

@Suite("Nomads.com city provider", .serialized)
struct NomadsCityProviderTests {
    @Test func searchDecodesNullableMetricsAndUsesExpectedQueryParameters() async throws {
        let session = makeNomadsSession { request in
            let url = try #require(request.url)
            #expect(url.scheme == "https")
            #expect(url.host == "nomads.com")
            #expect(url.path == "/api/search")
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            #expect(items?.first(where: { $0.name == "limit" })?.value == "20")
            #expect(items?.first(where: { $0.name == "country" })?.value == "Finland")
            #expect(items?.first(where: { $0.name == "max_cost_usd" })?.value == "2500")
            #expect(items?.first(where: { $0.name == "min_internet_mbps" })?.value == "100")
            return (200, Self.searchPayload, [:])
        }
        let now = Date(timeIntervalSince1970: 1_000)
        let provider = NomadsCityProvider(session: session, now: { now })

        let result = try await provider.search(.init(country: " Finland ", maxCostUSD: 2_500, minInternetMbps: 100))

        #expect(result.cities.count == 1)
        #expect(result.fetchedAt == now)
        #expect(result.cities[0].slug == "helsinki-finland")
        #expect(result.cities[0].overallScore == nil)
        #expect(result.cities[0].costForNomadUSDPerMonth == 2_000)
        #expect(result.cities[0].nextMeetup?.peopleGoing == nil)
        #expect(result.cities[0].cityURL?.absoluteString == "https://nomads.com/helsinki")
        #expect(result.cities[0].nextMeetup?.meetupURL?.host == "nomads.com")
    }

    @Test func cacheAndInFlightTaskAvoidDuplicateRequests() async throws {
        let session = makeNomadsSession { _ in
            Thread.sleep(forTimeInterval: 0.08)
            return (200, Self.searchPayload, [:])
        }
        let provider = NomadsCityProvider(session: session)
        let query = NomadsCitySearch(country: "Finland")
        async let first = provider.search(query)
        async let second = provider.search(query)
        _ = try await (first, second)
        _ = try await provider.search(query)
        #expect(MockNomadsURLProtocol.requestCount == 1)
    }

    @Test func detailUsesEncodedCityRouteAndRejectsUntrustedAPIURL() async throws {
        let session = makeNomadsSession { request in
            let url = try #require(request.url)
            #expect(url.path == "/api/city/helsinki-finland")
            return (200, """
            {"city":{"slug":"helsinki-finland","name":"Helsinki","country":"Finland","url":"https://evil.example/city/helsinki-finland"}}
            """, [:])
        }
        let city = try await NomadsCityProvider(session: session).city(slug: " Helsinki-Finland ")
        #expect(city.url == nil)
        #expect(city.cityURL == nil)
    }

    @Test func invalidInputAndHTTPFailuresHaveFriendlyErrors() async throws {
        let provider = NomadsCityProvider(session: makeNomadsSession { _ in (500, "{}", [:]) })
        await #expect(throws: NomadsProviderError.self) {
            try await provider.search(.init(maxCostUSD: 0))
        }
        await #expect(throws: NomadsProviderError.self) {
            try await provider.city(slug: "../private")
        }
        await #expect(throws: NomadsProviderError.self) {
            try await provider.search(.init(country: "FI"))
        }
    }

    @Test func rateLimitStartsAnHourCooldownWhenRetryAfterIsAbsent() async throws {
        let clock = Date(timeIntervalSince1970: 10_000)
        let session = makeNomadsSession { _ in (429, "{}", [:]) }
        let provider = NomadsCityProvider(session: session, now: { clock })
        await #expect(throws: NomadsProviderError.self) {
            try await provider.search(.init(country: "FI"))
        }
        await #expect(throws: NomadsProviderError.self) {
            try await provider.city(slug: "helsinki-finland")
        }
        #expect(MockNomadsURLProtocol.requestCount == 1)
    }

    @Test func searchCacheExpiresAfterSixHours() async throws {
        let clock = NomadsTestClock(Date(timeIntervalSince1970: 20_000))
        let provider = NomadsCityProvider(
            session: makeNomadsSession { _ in (200, Self.searchPayload, [:]) },
            now: { clock.now() }
        )
        let query = NomadsCitySearch(country: "Finland")

        _ = try await provider.search(query)
        _ = try await provider.search(query)
        #expect(MockNomadsURLProtocol.requestCount == 1)

        clock.advance(by: 6 * 60 * 60 + 1)
        _ = try await provider.search(query)
        #expect(MockNomadsURLProtocol.requestCount == 2)
    }

    @Test func detailCacheReusesAResponseForSixHours() async throws {
        let provider = NomadsCityProvider(
            session: makeNomadsSession { _ in
                (200, """
                {"city":{"slug":"helsinki-finland","name":"Helsinki","country":"Finland","url":"https://nomads.com/helsinki"}}
                """, [:])
            }
        )

        _ = try await provider.city(slug: "helsinki-finland")
        _ = try await provider.city(slug: "helsinki-finland")
        #expect(MockNomadsURLProtocol.requestCount == 1)
    }

    @Test func numericRetryAfterUsesResponseTimeAndBlocksUntilItExpires() async throws {
        let clock = NomadsTestClock(Date(timeIntervalSince1970: 30_000))
        let session = makeNomadsSession { _ in
            clock.advance(by: 10)
            return (429, "{}", ["Retry-After": "120"])
        }
        let provider = NomadsCityProvider(session: session, now: { clock.now() })

        await #expect(throws: NomadsProviderError.self) {
            try await provider.search(.init(country: "FI"))
        }
        clock.advance(by: 119)
        await #expect(throws: NomadsProviderError.self) {
            try await provider.city(slug: "helsinki-finland")
        }
        #expect(MockNomadsURLProtocol.requestCount == 1)

        clock.advance(by: 1)
        await #expect(throws: NomadsProviderError.self) {
            try await provider.city(slug: "helsinki-finland")
        }
        #expect(MockNomadsURLProtocol.requestCount == 2)
    }

    @Test func sharedRequestBudgetBlocksSixtyFirstUncachedRequest() async throws {
        let provider = NomadsCityProvider(
            session: makeNomadsSession { _ in (200, Self.searchPayload, [:]) }
        )

        for index in 0..<60 {
            _ = try await provider.search(.init(country: "Country \(index)"))
        }
        await #expect(throws: NomadsProviderError.self) {
            try await provider.search(.init(country: "Country 60"))
        }
        #expect(MockNomadsURLProtocol.requestCount == 60)
    }

    @Test func directoryDecodesOnlyTrustedDirectoryImagesAndCachesItsSingleResponse() async throws {
        let provider = NomadsCityProvider(session: makeNomadsSession { request in
            #expect(request.url?.path == "/api/cities")
            return (200, """
            {"cities":[
              {"name":"Lisbon","country":"Portugal","long_slug":"lisbon-portugal","short_slug":"lisbon","latitude":38.72,"longitude":-9.13,"image":"https://resizeapi.com/resize-cgi/image/format=auto/https://nomads.com/assets/img/places/lisbon-portugal.jpg","image_large":"https://nomads.com/assets/img/places/lisbon-portugal.jpg"},
              {"name":"Unsafe","country":"Portugal","long_slug":"unsafe-portugal","image":"https://example.com/unsafe.jpg"}
            ]}
            """, [:])
        })

        let first = try await provider.directory()
        let second = try await provider.directory()

        #expect(first == second)
        #expect(first.count == 2)
        #expect(first[0].id == "lisbon-portugal")
        #expect(first[0].imageURL?.host == "resizeapi.com")
        #expect(first[0].largeImageURL?.host == "nomads.com")
        #expect(first[1].imageURL == nil)
        #expect(MockNomadsURLProtocol.requestCount == 1)
    }

    @MainActor @Test func currentCityMatchingPrefersCountryExactThenNearbyWithinFiftyKilometers() throws {
        let cities = try JSONDecoder().decode(DirectoryFixture.self, from: Data("""
        {"cities":[
          {"name":"Helsinki","country":"Finland","long_slug":"helsinki-finland","latitude":60.1699,"longitude":24.9384},
          {"name":"Helsinki","country":"United States","long_slug":"helsinki-us","latitude":45.0,"longitude":-93.0},
          {"name":"Espoo","country":"Finland","long_slug":"espoo-finland","latitude":60.2055,"longitude":24.6559}
        ]}
        """.utf8)).cities
        let exact = location(city: "Hélsinki", country: nil, countryCode: "FI", latitude: 60.17, longitude: 24.94)
        let nearby = location(city: "Unknown", country: "Finland", countryCode: "FI", latitude: 60.21, longitude: 24.66)
        let distant = location(city: "Unknown", country: "Finland", countryCode: "FI", latitude: 61.0, longitude: 25.5)

        #expect(NomadsCurrentCityController.bestMatch(for: exact, in: cities)?.directoryCity.slug == "helsinki-finland")
        #expect(NomadsCurrentCityController.bestMatch(for: nearby, in: cities)?.directoryCity.slug == "espoo-finland")
        #expect(NomadsCurrentCityController.bestMatch(for: nearby, in: cities)?.isNearby == true)
        #expect(NomadsCurrentCityController.bestMatch(for: distant, in: cities) == nil)
        let remoteExact = location(city: "Helsinki", country: "United States", countryCode: "US", latitude: 60.17, longitude: 24.94)
        #expect(NomadsCurrentCityController.bestMatch(for: remoteExact, in: cities) == nil)
    }

    @MainActor @Test func currentCityNoMatchPersistsAndDoesNotRecheckAfterRestart() async {
        let storageURL = URL.temporaryDirectory.appendingPathComponent("nomads-city-match-\(UUID().uuidString).json")
        let preferencesKey = "NomadsCityProviderTests.\(UUID().uuidString)"
        defer {
            try? FileManager.default.removeItem(at: storageURL)
            UserDefaults.standard.removeObject(forKey: preferencesKey)
        }
        let session = makeNomadsSession { _ in (200, #"{"cities":[]}"#, [:]) }
        let location = location(city: "No matching city", country: "Finland", countryCode: "FI", latitude: 60.17, longitude: 24.94)
        let first = NomadsCurrentCityController(provider: NomadsCityProvider(session: session), storageURL: storageURL, preferencesKey: preferencesKey)

        first.ingest(location: location)
        #expect(await waitForCurrentCityLookup(first))
        #expect(first.state == .notFound)
        #expect(MockNomadsURLProtocol.requestCount == 1)

        let restarted = NomadsCurrentCityController(provider: NomadsCityProvider(session: session), storageURL: storageURL, preferencesKey: preferencesKey)
        restarted.ingest(location: location)
        #expect(restarted.state == .notFound)
        #expect(MockNomadsURLProtocol.requestCount == 1)
    }

    @MainActor @Test func currentCityMatchPersistsAndIgnoresCoordinateJitter() async {
        let storageURL = URL.temporaryDirectory.appendingPathComponent("nomads-city-match-\(UUID().uuidString).json")
        let preferencesKey = "NomadsCityProviderTests.\(UUID().uuidString)"
        defer {
            try? FileManager.default.removeItem(at: storageURL)
            UserDefaults.standard.removeObject(forKey: preferencesKey)
        }
        let clock = NomadsTestClock(Date(timeIntervalSince1970: 100_000))
        let session = makeNomadsSession { request in
            switch request.url?.path {
            case "/api/cities":
                (200, #"{"cities":[{"name":"Helsinki","country":"Finland","long_slug":"helsinki-finland","latitude":60.1699,"longitude":24.9384}]}"#, [:])
            case "/api/city/helsinki-finland":
                (200, #"{"city":{"slug":"helsinki-finland","name":"Helsinki","country":"Finland"}}"#, [:])
            default: (500, "{}", [:])
            }
        }
        let first = NomadsCurrentCityController(provider: NomadsCityProvider(session: session, now: { clock.now() }), storageURL: storageURL, preferencesKey: preferencesKey)
        first.ingest(location: location(city: "Hélsinki", country: "Suomi", countryCode: nil, latitude: 60.17, longitude: 24.94))
        #expect(await waitForCurrentCityLookup(first))
        #expect(first.matchedCity?.slug == "helsinki-finland")
        #expect(MockNomadsURLProtocol.requestCount == 2)

        first.ingest(location: location(city: "Helsinki", country: "Finland", countryCode: "FI", latitude: 60.175, longitude: 24.93))
        #expect(MockNomadsURLProtocol.requestCount == 2)

        clock.advance(by: 6 * 60 * 60 + 1)
        first.ingest(location: nil)
        first.ingest(location: location(city: nil, country: "Finland", countryCode: "FI", latitude: 60.175, longitude: 24.93))
        first.ingest(location: location(city: "Helsinki", country: "Finland", countryCode: "FI", latitude: 60.175, longitude: 24.93))
        #expect(first.matchedCity?.slug == "helsinki-finland")
        #expect(MockNomadsURLProtocol.requestCount == 2)

        let restarted = NomadsCurrentCityController(provider: NomadsCityProvider(session: session), storageURL: storageURL, preferencesKey: preferencesKey)
        restarted.ingest(location: location(city: "Helsinki", country: "Finland", countryCode: "FI", latitude: 60.17, longitude: 24.94))
        #expect(restarted.matchedCity?.slug == "helsinki-finland")
        #expect(MockNomadsURLProtocol.requestCount == 2)
    }

    @MainActor @Test func corruptMatchingStorageIsPreserved() async throws {
        let storageURL = URL.temporaryDirectory.appendingPathComponent("nomads-city-match-\(UUID().uuidString).json")
        let preferencesKey = "NomadsCityProviderTests.\(UUID().uuidString)"
        let corrupt = Data("not json".utf8)
        try corrupt.write(to: storageURL)
        defer {
            try? FileManager.default.removeItem(at: storageURL)
            UserDefaults.standard.removeObject(forKey: preferencesKey)
        }
        let controller = NomadsCurrentCityController(provider: NomadsCityProvider(session: makeNomadsSession { _ in (200, #"{"cities":[]}"#, [:]) }), storageURL: storageURL, preferencesKey: preferencesKey)
        controller.ingest(location: location(city: "Missing", country: "Finland", countryCode: "FI", latitude: 60, longitude: 24))
        #expect(await waitForCurrentCityLookup(controller))
        #expect(controller.errorMessage == "Saved city matching data could not be read.")
        #expect(try Data(contentsOf: storageURL) == corrupt)
    }

    @MainActor @Test func currentCityRaceNeverPublishesTheSupersededCity() async {
        let storageURL = URL.temporaryDirectory.appendingPathComponent("nomads-city-match-\(UUID().uuidString).json")
        let preferencesKey = "NomadsCityProviderTests.\(UUID().uuidString)"
        defer {
            try? FileManager.default.removeItem(at: storageURL)
            UserDefaults.standard.removeObject(forKey: preferencesKey)
        }
        let session = makeNomadsSession { request in
            switch request.url?.path {
            case "/api/cities":
                return (200, #"{"cities":[{"name":"Alpha","country":"Finland","long_slug":"alpha-finland","latitude":60.17,"longitude":24.94},{"name":"Beta","country":"Finland","long_slug":"beta-finland","latitude":60.20,"longitude":24.70}]}"#, [:])
            case "/api/city/alpha-finland":
                Thread.sleep(forTimeInterval: 0.2)
                return (200, #"{"city":{"slug":"alpha-finland","name":"Alpha","country":"Finland"}}"#, [:])
            case "/api/city/beta-finland":
                return (200, #"{"city":{"slug":"beta-finland","name":"Beta","country":"Finland"}}"#, [:])
            default: return (500, "{}", [:])
            }
        }
        let controller = NomadsCurrentCityController(provider: NomadsCityProvider(session: session), storageURL: storageURL, preferencesKey: preferencesKey)
        controller.ingest(location: location(city: "Alpha", country: "Finland", countryCode: "FI", latitude: 60.17, longitude: 24.94))
        #expect(await waitForNomadsRequest(path: "/api/city/alpha-finland"))
        controller.ingest(location: location(city: "Beta", country: "Finland", countryCode: "FI", latitude: 60.20, longitude: 24.70))
        #expect(await waitForCurrentCityLookup(controller))
        #expect(controller.state == .matched)
        #expect(controller.matchedCity?.slug == "beta-finland")

        let restarted = NomadsCurrentCityController(provider: NomadsCityProvider(session: session), storageURL: storageURL, preferencesKey: preferencesKey)
        restarted.ingest(location: location(city: "Beta", country: "Finland", countryCode: "FI", latitude: 60.20, longitude: 24.70))
        #expect(restarted.matchedCity?.slug == "beta-finland")
    }

    @MainActor @Test func disabledCurrentCityMakesNoNetworkRequestsAndRestoresSavedMatchWhenReenabled() async {
        let storageURL = URL.temporaryDirectory.appendingPathComponent("nomads-city-match-\(UUID().uuidString).json")
        let preferencesKey = "NomadsCityProviderTests.\(UUID().uuidString)"
        defer {
            try? FileManager.default.removeItem(at: storageURL)
            UserDefaults.standard.removeObject(forKey: preferencesKey)
        }
        let session = makeNomadsSession { request in
            switch request.url?.path {
            case "/api/cities": (200, #"{"cities":[{"name":"Helsinki","country":"Finland","long_slug":"helsinki-finland","latitude":60.17,"longitude":24.94}]}"#, [:])
            case "/api/city/helsinki-finland": (200, #"{"city":{"slug":"helsinki-finland","name":"Helsinki","country":"Finland"}}"#, [:])
            default: (500, "{}", [:])
            }
        }
        let controller = NomadsCurrentCityController(provider: NomadsCityProvider(session: session), storageURL: storageURL, preferencesKey: preferencesKey)
        let helsinki = location(city: "Helsinki", country: "Finland", countryCode: "FI", latitude: 60.17, longitude: 24.94)
        controller.ingest(location: helsinki)
        #expect(await waitForCurrentCityLookup(controller))
        #expect(MockNomadsURLProtocol.requestCount == 2)

        controller.enabled = false
        controller.ingest(location: helsinki)
        #expect(controller.state == .disabled)
        #expect(MockNomadsURLProtocol.requestCount == 2)
        controller.enabled = true
        #expect(controller.state == .matched)
        #expect(controller.matchedCity?.slug == "helsinki-finland")
        #expect(MockNomadsURLProtocol.requestCount == 2)
    }

    private static let searchPayload = """
    {
      "cities": [{
        "slug":"helsinki-finland", "name":"Helsinki", "country":"Finland",
        "url":"https://nomads.com/helsinki",
        "overall_score":null, "cost_for_nomad_usd_per_month":2000,
        "rent_1br_center_usd_per_month":null, "coworking_usd_per_month":null,
        "internet_mbps":100, "safety_score_0_to_5":4.1,
        "walkability_score_0_to_5":4.2, "english_speaking_score_0_to_5":4.9,
        "next_meetup":{"name":"Nomads Coffee", "date":"2026-10-01", "people_going":null, "url":"https://nomads.com/meetups/helsinki"}
      }], "total_matching":16, "returned":1, "attribution":"Nomads.com"
    }
    """
}

private struct DirectoryFixture: Decodable { let cities: [NomadsDirectoryCity] }

private func location(city: String?, country: String?, countryCode: String?, latitude: Double?, longitude: Double?) -> IPLocationSnapshot {
    IPLocationSnapshot(city: city, region: "Uusimaa", country: country, countryCode: countryCode, latitude: latitude, longitude: longitude, timeZone: "Europe/Helsinki", provider: "test", fetchedAt: .now)
}

@MainActor
private func waitForCurrentCityLookup(_ controller: NomadsCurrentCityController) async -> Bool {
    let deadline = Date().addingTimeInterval(2)
    while controller.isLoading, Date() < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
    return !controller.isLoading
}

private func waitForNomadsRequest(path: String) async -> Bool {
    let deadline = Date().addingTimeInterval(2)
    while Date() < deadline {
        if MockNomadsURLProtocol.requestedPaths.contains(path) {
            return true
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return false
}

private func makeNomadsSession(
    handler: @escaping @Sendable (URLRequest) throws -> (Int, String, [String: String])
) -> URLSession {
    MockNomadsURLProtocol.reset(handler: handler)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockNomadsURLProtocol.self]
    return URLSession(configuration: configuration)
}

private final class MockNomadsURLProtocol: URLProtocol, @unchecked Sendable {
    private static let state = MockNomadsURLProtocolState()

    static var requestCount: Int {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.count
    }

    static var requestedPaths: [String] {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.paths
    }

    static func reset(handler: @escaping @Sendable (URLRequest) throws -> (Int, String, [String: String])) {
        state.lock.lock()
        defer { state.lock.unlock() }
        state.handler = handler
        state.count = 0
        state.paths = []
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.state.lock.lock()
        Self.state.count += 1
        if let path = request.url?.path {
            Self.state.paths.append(path)
        }
        let handler = Self.state.handler
        Self.state.lock.unlock()
        do {
            let (status, body, headers) = try handler?(request) ?? (500, "{}", [:])
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class MockNomadsURLProtocolState: @unchecked Sendable {
    let lock = NSLock()
    var handler: (@Sendable (URLRequest) throws -> (Int, String, [String: String]))?
    var count = 0
    var paths: [String] = []
}

private final class NomadsTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) {
        self.value = value
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        value.addTimeInterval(interval)
        lock.unlock()
    }
}
