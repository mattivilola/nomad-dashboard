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
