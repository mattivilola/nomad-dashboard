import CoreLocation
import Foundation
@testable import NomadCore
import Testing

struct LocalPriceLevelProviderTests {
    @Test
    func eurostatRowsCarryTheSignedDifferenceBehindTheirDetailText() async throws {
        let session = makeSession { categoryValues in
            switch categoryValues {
            case "A0111": 95.6 // 4.4 below -> -4
            case "A0101": 104.4 // 4.4 above -> +4
            case "A01": 100.4 // within one point -> "Around"
            default: nil
            }
        }
        let provider = LiveLocalPriceLevelProvider(session: session)

        let snapshot = try await provider.prices(
            for: LocalPriceSearchRequest(coordinate: nil, countryCode: "ES", countryName: "Spain", locality: nil),
            forceRefresh: true
        )

        let meal = try #require(snapshot.rows.first { $0.kind == .mealOut })
        let groceries = try #require(snapshot.rows.first { $0.kind == .groceries })
        let overall = try #require(snapshot.rows.first { $0.kind == .overall })

        #expect(meal.differenceFromEUPercent == -4)
        #expect(meal.detail.hasPrefix("4% below EU average"))
        #expect(groceries.differenceFromEUPercent == 4)
        #expect(groceries.detail.hasPrefix("4% above EU average"))
        #expect(overall.differenceFromEUPercent == 0)
        #expect(overall.detail.hasPrefix("Around EU average"))
    }

    @Test
    func differenceHelpersAgreeOnRoundingAndSign() {
        #expect(LiveLocalPriceLevelProvider.wholePercentDifference(for: 96, against: 100) == -4)
        #expect(LiveLocalPriceLevelProvider.wholePercentDifference(for: 112.4, against: 100) == 12)
        #expect(LiveLocalPriceLevelProvider.relativeDifferenceText(forWholePercent: -4, suffix: "EU average") == "4% below EU average")
        #expect(LiveLocalPriceLevelProvider.relativeDifferenceText(forWholePercent: 12, suffix: "EU average") == "12% above EU average")
        #expect(LiveLocalPriceLevelProvider.relativeDifferenceText(forWholePercent: 1, suffix: "EU average") == "Around EU average")
    }

    @Test
    func rowsDefaultToNoEUDifference() {
        let row = LocalPriceIndicatorRow(
            kind: .rentOneBedroom,
            value: "$1,200/mo",
            detail: "County benchmark · 2025",
            precision: .countyBenchmark,
            source: LocalPriceSourceAttribution(name: "HUD USER", url: nil)
        )

        #expect(row.differenceFromEUPercent == nil)
    }

    @Test
    func legacyCachedRowsWithoutTheFieldStillDecode() throws {
        let legacy = """
        {
          "kind": "mealOut",
          "value": "Moderate",
          "detail": "4% below EU average · Country fallback · 2024",
          "precision": "countryFallback",
          "source": { "name": "Eurostat" }
        }
        """
        let row = try JSONDecoder().decode(LocalPriceIndicatorRow.self, from: Data(legacy.utf8))

        #expect(row.differenceFromEUPercent == nil)
        #expect(row.detail.hasPrefix("4% below"))
    }

    @Test
    func differenceRoundTripsThroughCoding() throws {
        let row = LocalPriceIndicatorRow(
            kind: .groceries,
            value: "Moderate",
            detail: "4% below EU average · Country fallback · 2024",
            precision: .countryFallback,
            source: LocalPriceSourceAttribution(name: "Eurostat", url: nil),
            differenceFromEUPercent: -4
        )
        let decoded = try JSONDecoder().decode(LocalPriceIndicatorRow.self, from: JSONEncoder().encode(row))

        #expect(decoded == row)
        #expect(decoded.differenceFromEUPercent == -4)
    }

    @Test
    func previewFixtureRowsMatchTheirDetailText() throws {
        let rows = try #require(DashboardSnapshot.preview.localInfo?.localPriceLevel?.rows)

        for row in rows {
            let difference = try #require(row.differenceFromEUPercent)
            let expected = LiveLocalPriceLevelProvider.relativeDifferenceText(
                forWholePercent: Int(difference),
                suffix: "EU average"
            )
            #expect(row.detail.hasPrefix(expected))
        }
    }

    @Test
    func snapshotsCachedBeforeTheHomeComparisonExistedStillDecode() throws {
        let legacy = """
        {
          "status": "ready",
          "summaryBand": "medium",
          "countryCode": "ES",
          "countryName": "Spain",
          "rows": [],
          "sources": [],
          "detail": "Country fallback snapshot."
        }
        """
        let snapshot = try JSONDecoder().decode(LocalPriceLevelSnapshot.self, from: Data(legacy.utf8))

        #expect(snapshot.homeComparison == nil)
        #expect(snapshot.homeCountryCode == nil)
        #expect(snapshot.countryCode == "ES")
    }

    @Test
    func homeComparisonRoundTripsThroughCoding() throws {
        let snapshot = LocalPriceLevelSnapshot(
            status: .ready,
            summaryBand: .low,
            countryCode: "ES",
            countryName: "Spain",
            rows: [],
            sources: [],
            fetchedAt: nil,
            detail: nil,
            note: nil,
            homeComparison: [PriceLevelDifference(kind: .groceries, percentDifference: -30)],
            homeCountryCode: "FI"
        )
        let decoded = try JSONDecoder().decode(LocalPriceLevelSnapshot.self, from: JSONEncoder().encode(snapshot))

        #expect(decoded == snapshot)
    }

    @Test
    func pricesCompareWithTheHomeCountryAndFetchEachCountryOnce() async throws {
        let stub = EurostatStub(indices: [
            "ES": ["A0111": 90, "A0101": 80, "A01": 85],
            "FI": ["A0111": 120, "A0101": 110, "A01": 118]
        ])
        let provider = LiveLocalPriceLevelProvider(session: stub.session)
        let request = LocalPriceSearchRequest(
            coordinate: nil,
            countryCode: "ES",
            countryName: "Spain",
            locality: nil,
            homeCountryCode: "fi"
        )

        let snapshot = try await provider.prices(for: request, forceRefresh: false)
        let comparison = try #require(snapshot.homeComparison)

        #expect(snapshot.homeCountryCode == "FI")
        #expect(comparison.first { $0.kind == .mealOut }?.percentDifference == -25)
        #expect(comparison.first { $0.kind == .groceries }?.percentDifference == -27)
        #expect(comparison.first { $0.kind == .overall }?.percentDifference == -28)
        #expect(stub.requests.count == 6)
        #expect(Set(stub.requests.map(\.geo)) == ["ES", "FI"])

        // A forced refresh refetches the current country only; the annual home indices stay cached.
        _ = try await provider.prices(for: request, forceRefresh: true)
        #expect(stub.requests.count == 9)
        #expect(stub.requests.suffix(3).allSatisfy { $0.geo == "ES" })
    }

    @Test
    func homeRequestSendsOnlyTheCountryCode() async throws {
        let stub = EurostatStub(indices: ["ES": ["A01": 85], "FI": ["A01": 118]])
        let provider = LiveLocalPriceLevelProvider(session: stub.session)

        _ = try await provider.prices(
            for: LocalPriceSearchRequest(
                coordinate: CLLocationCoordinate2D(latitude: 41.39, longitude: 2.17),
                countryCode: "ES",
                countryName: "Spain",
                locality: "Barcelona",
                homeCountryCode: "FI"
            ),
            forceRefresh: false
        )

        let homeRequests = stub.requests.filter { $0.geo == "FI" }
        #expect(homeRequests.isEmpty == false)
        for request in homeRequests {
            let names = Set(URLComponents(string: request.url)?.queryItems?.map(\.name) ?? [])
            #expect(names == ["geo", "indic_ppp", "ppp_cat18", "lang"])
            #expect(request.url.contains("Barcelona") == false)
            #expect(request.url.contains("41.39") == false)
        }
    }

    @Test
    func indicesAreCachedPerCountry() async throws {
        let stub = EurostatStub(indices: [
            "SE": ["A0111": 110, "A0101": 105, "A01": 108],
            "PT": ["A0111": 70, "A0101": 85, "A01": 80]
        ])
        let provider = LiveLocalPriceLevelProvider(session: stub.session)

        let sweden = try await provider.indices(forCountryCode: "se")
        _ = try await provider.indices(forCountryCode: "SE")
        #expect(stub.requests.count == 3)
        #expect(sweden == [.mealOut: 110, .groceries: 105, .overall: 108])

        let portugal = try await provider.indices(forCountryCode: "PT")
        #expect(stub.requests.count == 6)
        #expect(portugal[.overall] == 80)

        _ = try await provider.indices(forCountryCode: "SE")
        _ = try await provider.indices(forCountryCode: "PT")
        #expect(stub.requests.count == 6)
    }

    @Test
    func indicesExpireAfterTheIndexTTL() async throws {
        let stub = EurostatStub(indices: ["SE": ["A01": 108]])
        let provider = LiveLocalPriceLevelProvider(session: stub.session, indexTTL: 0)

        _ = try await provider.indices(forCountryCode: "SE")
        _ = try await provider.indices(forCountryCode: "SE")

        #expect(stub.requests.count == 6)
    }

    @Test
    func countriesWithoutEurostatDataReturnNoIndicesAndMakeNoRequests() async throws {
        let stub = EurostatStub(indices: [:])
        let provider = LiveLocalPriceLevelProvider(session: stub.session)

        #expect(try await provider.indices(forCountryCode: "JP").isEmpty)
        #expect(try await provider.indices(forCountryCode: "US").isEmpty)
        #expect(try await provider.indices(forCountryCode: "").isEmpty)
        #expect(stub.requests.isEmpty)
    }

    @Test
    func greeceAndTheUnitedKingdomUseEurostatsOwnCodes() async throws {
        let stub = EurostatStub(indices: ["EL": ["A01": 80], "UK": ["A01": 128]])
        let provider = LiveLocalPriceLevelProvider(session: stub.session)

        #expect(try await provider.indices(forCountryCode: "GR") == [.overall: 80])
        #expect(try await provider.indices(forCountryCode: "GB") == [.overall: 128])
        #expect(Set(stub.requests.map(\.geo)) == ["EL", "UK"])
    }

    @Test
    func noComparisonWhenHomeIsTheCurrentCountry() async throws {
        let stub = EurostatStub(indices: ["GR": [:], "EL": ["A0111": 80, "A0101": 80, "A01": 80]])
        let provider = LiveLocalPriceLevelProvider(session: stub.session)

        for home in ["EL", "GR", "gr"] {
            let snapshot = try await provider.prices(
                for: LocalPriceSearchRequest(
                    coordinate: nil,
                    countryCode: "GR",
                    countryName: "Greece",
                    locality: nil,
                    homeCountryCode: home
                ),
                forceRefresh: false
            )

            #expect(snapshot.homeComparison == nil)
            #expect(snapshot.homeCountryCode == nil)
        }
        #expect(stub.requests.count == 3)
    }

    @Test
    func noComparisonWithoutAHomeCountryOrWhenHomeIsNotCovered() async throws {
        let stub = EurostatStub(indices: ["ES": ["A0111": 90, "A0101": 80, "A01": 85]])
        let provider = LiveLocalPriceLevelProvider(session: stub.session)

        let withoutHome = try await provider.prices(
            for: LocalPriceSearchRequest(coordinate: nil, countryCode: "ES", countryName: "Spain", locality: nil),
            forceRefresh: false
        )
        let uncoveredHome = try await provider.prices(
            for: LocalPriceSearchRequest(
                coordinate: nil,
                countryCode: "ES",
                countryName: "Spain",
                locality: nil,
                homeCountryCode: "JP"
            ),
            forceRefresh: false
        )

        #expect(withoutHome.homeComparison == nil)
        #expect(uncoveredHome.homeComparison == nil)
        #expect(uncoveredHome.rows.count == 3)
        #expect(stub.requests.count == 3)
    }

    @Test
    func aFailingHomeLookupLeavesTheSnapshotWithoutComparison() async throws {
        let stub = EurostatStub(indices: ["ES": ["A0111": 90, "A0101": 80, "A01": 85]], failingGeos: ["FI"])
        let provider = LiveLocalPriceLevelProvider(session: stub.session)

        let snapshot = try await provider.prices(
            for: LocalPriceSearchRequest(
                coordinate: nil,
                countryCode: "ES",
                countryName: "Spain",
                locality: nil,
                homeCountryCode: "FI"
            ),
            forceRefresh: false
        )

        #expect(snapshot.status == .ready)
        #expect(snapshot.homeComparison == nil)
    }

    @Test
    func noComparisonForTheUSPath() async throws {
        let stub = EurostatStub(indices: ["FI": ["A01": 118]])
        let provider = LiveLocalPriceLevelProvider(session: stub.session)

        let snapshot = try await provider.prices(
            for: LocalPriceSearchRequest(
                coordinate: nil,
                countryCode: "US",
                countryName: "United States",
                locality: nil,
                homeCountryCode: "FI"
            ),
            forceRefresh: false
        )

        #expect(snapshot.homeComparison == nil)
        #expect(stub.requests.isEmpty)
    }

    @Test
    func previewHospitalsAreListedNearestFirst() {
        let distances = DashboardSnapshot.preview.emergencyCare?.hospitals.map(\.distanceKilometers) ?? []

        #expect(distances.isEmpty == false)
        #expect(distances == distances.sorted())
    }
}

private func makeSession(valueForCategory: @escaping @Sendable (String) -> Double?) -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockLocalPriceURLProtocol.self]
    MockLocalPriceURLProtocol.valueForCategory = valueForCategory
    return URLSession(configuration: configuration)
}

private final class MockLocalPriceURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var valueForCategory: (@Sendable (String) -> Double?)?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let category = components.queryItems?.first(where: { $0.name == "ppp_cat18" })?.value,
              let value = Self.valueForCategory?(category)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let body = #"{"value":{"0":\#(value)},"dimension":{"time":{"category":{"index":{"2024":0}}}}}"#
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Serves Eurostat-shaped responses for `geo` x `ppp_cat18` and records every request it receives.
/// Each stub gets its own `URLSession` (and host-keyed registry slot) so tests can run in parallel.
private final class EurostatStub: @unchecked Sendable {
    struct Request: Sendable {
        let geo: String
        let url: String
    }

    let session: URLSession
    private let id = UUID().uuidString
    private let lock = NSLock()
    private var recorded: [Request] = []

    var requests: [Request] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    init(indices: [String: [String: Double]], failingGeos: Set<String> = []) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EurostatStubURLProtocol.self]
        configuration.httpAdditionalHeaders = [EurostatStubURLProtocol.idHeader: id]
        session = URLSession(configuration: configuration)
        EurostatStubURLProtocol.register(id: id) { [weak self] request in
            guard let url = request.url,
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let geo = components.queryItems?.first(where: { $0.name == "geo" })?.value,
                  let category = components.queryItems?.first(where: { $0.name == "ppp_cat18" })?.value
            else {
                return nil
            }

            self?.record(Request(geo: geo, url: url.absoluteString))
            if failingGeos.contains(geo) {
                return nil
            }

            guard let value = indices[geo]?[category] else {
                return Data(#"{"dimension":{"time":{"category":{"index":{"2024":0}}}}}"#.utf8)
            }
            return Data(#"{"value":{"0":\#(value)},"dimension":{"time":{"category":{"index":{"2024":0}}}}}"#.utf8)
        }
    }

    private func record(_ request: Request) {
        lock.lock()
        recorded.append(request)
        lock.unlock()
    }
}

private final class EurostatStubURLProtocol: URLProtocol, @unchecked Sendable {
    static let idHeader = "X-Eurostat-Stub"
    private static let lock = NSLock()
    private nonisolated(unsafe) static var handlers: [String: @Sendable (URLRequest) -> Data?] = [:]

    static func register(id: String, handler: @escaping @Sendable (URLRequest) -> Data?) {
        lock.lock()
        handlers[id] = handler
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        let handler = request.value(forHTTPHeaderField: Self.idHeader).flatMap { Self.handlers[$0] }
        Self.lock.unlock()

        guard let url = request.url, let body = handler?(request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
