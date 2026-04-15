import CoreLocation
import Foundation
import NomadCore
import Testing

@Suite(.serialized)
struct LocalInfoProviderLiveTests {
    @Test
    func infoBuildsReadySnapshotWhenPublicHolidaySchoolBreakAndPriceRowsExist() async throws {
        let session = makeMockLocalInfoSession { request in
            let url = try #require(request.url)
            switch (url.path, url.query ?? "") {
            case ("/api/v3/publicholidays/2026/DE", _):
                return (200, """
                [{"date":"2026-05-01","localName":"Tag der Arbeit","name":"Labour Day","counties":null}]
                """)
            case ("/Subdivisions", let query) where query.contains("countryIsoCode=DE"):
                return (200, """
                [{"code":"DE-BE","isoCode":"DE-BE","shortName":"BE","name":[{"language":"EN","text":"Berlin"}]}]
                """)
            case ("/SchoolHolidays", let query) where query.contains("countryIsoCode=DE"):
                return (200, """
                [{"startDate":"2026-03-30","endDate":"2026-04-10","name":[{"language":"EN","text":"Easter Holidays"}],"nationwide":false,"subdivisions":[{"code":"DE-BE"}]}]
                """)
            default:
                Issue.record("Unexpected request: \(url.absoluteString)")
                return (404, "[]")
            }
        }

        let provider = LiveLocalInfoProvider(
            session: session,
            localPriceLevelProvider: FixedPriceRowsProvider(),
            nowProvider: { Self.makeDate(year: 2026, month: 4, day: 1, timeZoneID: "Europe/Berlin") }
        )

        let snapshot = try await provider.info(
            for: LocalInfoRequest(
                coordinate: CLLocationCoordinate2D(latitude: 52.52, longitude: 13.405),
                countryCode: "DE",
                countryName: "Germany",
                locality: "Berlin",
                administrativeRegion: "Berlin",
                timeZoneIdentifier: "Europe/Berlin"
            ),
            forceRefresh: true
        )

        #expect(snapshot.status == .ready)
        #expect(snapshot.publicHolidayStatus.state == .upcoming)
        #expect(snapshot.publicHolidayStatus.nextPeriod?.name == "Tag der Arbeit")
        #expect(snapshot.schoolHolidayStatus?.state == .current)
        #expect(snapshot.schoolHolidayStatus?.currentPeriod?.name == "Easter Holidays")
        #expect(snapshot.localPriceLevel?.rows.map(\.kind) == [.mealOut, .groceries, .overall])
        #expect(snapshot.sources.map(\.name).contains("Nager.Date"))
        #expect(snapshot.sources.map(\.name).contains("OpenHolidays"))
    }

    @Test
    func infoOmitsSchoolHolidayWhenRegionalMatchIsUnavailable() async throws {
        let session = makeMockLocalInfoSession { request in
            let url = try #require(request.url)
            switch (url.path, url.query ?? "") {
            case ("/api/v3/publicholidays/2026/FI", _):
                return (200, """
                [{"date":"2026-05-01","localName":"Vappu","name":"May Day","counties":null}]
                """)
            case ("/Subdivisions", let query) where query.contains("countryIsoCode=FI"):
                return (200, "[]")
            default:
                Issue.record("Unexpected request: \(url.absoluteString)")
                return (404, "[]")
            }
        }

        let provider = LiveLocalInfoProvider(
            session: session,
            localPriceLevelProvider: FixedPriceRowsProvider(),
            nowProvider: { Self.makeDate(year: 2026, month: 4, day: 1, timeZoneID: "Europe/Helsinki") }
        )

        let snapshot = try await provider.info(
            for: LocalInfoRequest(
                coordinate: CLLocationCoordinate2D(latitude: 60.1699, longitude: 24.9384),
                countryCode: "FI",
                countryName: "Finland",
                locality: "Helsinki",
                administrativeRegion: nil,
                timeZoneIdentifier: "Europe/Helsinki"
            ),
            forceRefresh: true
        )

        #expect(snapshot.status == .partial)
        #expect(snapshot.publicHolidayStatus.nextPeriod?.name == "Vappu")
        #expect(snapshot.schoolHolidayStatus == nil)
        #expect(snapshot.note?.contains("confident regional match") == true)
    }

    @Test
    func infoLoadsNextYearHolidayAndReusesCachedResponses() async throws {
        let requestCounter = LockedCounter()
        let session = makeMockLocalInfoSession { request in
            let url = try #require(request.url)
            await requestCounter.increment(for: url.absoluteString)

            switch (url.path, url.query ?? "") {
            case ("/api/v3/publicholidays/2026/FI", _):
                return (200, "[]")
            case ("/api/v3/publicholidays/2027/FI", _):
                return (200, """
                [{"date":"2027-01-01","localName":"Uudenvuodenpäivä","name":"New Year's Day","counties":null}]
                """)
            case ("/Subdivisions", let query) where query.contains("countryIsoCode=FI"):
                return (200, "[]")
            default:
                Issue.record("Unexpected request: \(url.absoluteString)")
                return (404, "[]")
            }
        }

        let provider = LiveLocalInfoProvider(
            session: session,
            localPriceLevelProvider: FixedPriceRowsProvider(),
            nowProvider: { Self.makeDate(year: 2026, month: 12, day: 31, timeZoneID: "Europe/Helsinki") }
        )

        let request = LocalInfoRequest(
            coordinate: CLLocationCoordinate2D(latitude: 60.1699, longitude: 24.9384),
            countryCode: "FI",
            countryName: "Finland",
            locality: "Helsinki",
            administrativeRegion: nil,
            timeZoneIdentifier: "Europe/Helsinki"
        )

        let first = try await provider.info(for: request, forceRefresh: false)
        let second = try await provider.info(for: request, forceRefresh: false)

        #expect(first.publicHolidayStatus.nextPeriod?.name == "Uudenvuodenpäivä")
        #expect(second.publicHolidayStatus.nextPeriod?.name == "Uudenvuodenpäivä")
        #expect(await requestCounter.count(for: "https://date.nager.at/api/v3/publicholidays/2026/FI") == 1)
        #expect(await requestCounter.count(for: "https://date.nager.at/api/v3/publicholidays/2027/FI") == 1)
    }

    @Test
    func infoPreservesLocalPriceNoteWhenPriceRowsExist() async throws {
        let session = makeMockLocalInfoSession { request in
            let url = try #require(request.url)
            switch (url.path, url.query ?? "") {
            case ("/api/v3/publicholidays/2026/US", _):
                return (200, """
                [{"date":"2026-07-04","localName":"Independence Day","name":"Independence Day","counties":null}]
                """)
            case ("/Subdivisions", let query) where query.contains("countryIsoCode=US"):
                return (200, "[]")
            default:
                Issue.record("Unexpected request: \(url.absoluteString)")
                return (404, "[]")
            }
        }

        let provider = LiveLocalInfoProvider(
            session: session,
            localPriceLevelProvider: FixedPriceRowsProviderWithNote(),
            nowProvider: { Self.makeDate(year: 2026, month: 4, day: 1, timeZoneID: "America/New_York") }
        )

        let snapshot = try await provider.info(
            for: LocalInfoRequest(
                coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
                countryCode: "US",
                countryName: "United States",
                locality: "New York",
                administrativeRegion: "New York",
                timeZoneIdentifier: "America/New_York"
            ),
            forceRefresh: true
        )

        #expect(snapshot.localPriceLevel?.rows.isEmpty == false)
        #expect(snapshot.note?.contains("Kings County") == true)
    }

    private static func makeDate(year: Int, month: Int, day: Int, timeZoneID: String) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 10)) ?? .now
    }
}

private struct FixedPriceRowsProvider: LocalPriceLevelProvider {
    func prices(for request: LocalPriceSearchRequest, forceRefresh: Bool) async throws -> LocalPriceLevelSnapshot {
        LocalPriceLevelSnapshot(
            status: .ready,
            summaryBand: .medium,
            countryCode: request.countryCode,
            countryName: request.countryName,
            rows: [
                LocalPriceIndicatorRow(
                    kind: .mealOut,
                    value: "Moderate",
                    detail: "4% below EU average · Country fallback · 2024",
                    precision: .countryFallback,
                    source: LocalPriceSourceAttribution(name: "Eurostat", url: URL(string: "https://ec.europa.eu"))
                ),
                LocalPriceIndicatorRow(
                    kind: .groceries,
                    value: "Moderate",
                    detail: "4% below EU average · Country fallback · 2024",
                    precision: .countryFallback,
                    source: LocalPriceSourceAttribution(name: "Eurostat", url: URL(string: "https://ec.europa.eu"))
                ),
                LocalPriceIndicatorRow(
                    kind: .overall,
                    value: "Moderate",
                    detail: "1% below EU average · Country fallback · 2024",
                    precision: .countryFallback,
                    source: LocalPriceSourceAttribution(name: "Eurostat", url: URL(string: "https://ec.europa.eu"))
                )
            ],
            sources: [LocalPriceSourceAttribution(name: "Eurostat", url: URL(string: "https://ec.europa.eu"))],
            fetchedAt: .now,
            detail: "Country fallback snapshot.",
            note: nil
        )
    }
}

private struct FixedPriceRowsProviderWithNote: LocalPriceLevelProvider {
    func prices(for request: LocalPriceSearchRequest, forceRefresh: Bool) async throws -> LocalPriceLevelSnapshot {
        LocalPriceLevelSnapshot(
            status: .partial,
            summaryBand: .limited,
            countryCode: request.countryCode,
            countryName: request.countryName,
            rows: [
                LocalPriceIndicatorRow(
                    kind: .rentOneBedroom,
                    value: "$2,100/mo",
                    detail: "County exact · HUD USER · 2026",
                    precision: .countyBenchmark,
                    source: LocalPriceSourceAttribution(name: "HUD USER", url: URL(string: "https://www.huduser.gov"))
                )
            ],
            sources: [LocalPriceSourceAttribution(name: "HUD USER", url: URL(string: "https://www.huduser.gov"))],
            fetchedAt: .now,
            detail: "US v1 currently shows the HUD 1-bedroom rent benchmark only.",
            note: "Kings County"
        )
    }
}

private actor LockedCounter {
    private var values: [String: Int] = [:]

    func increment(for key: String) {
        values[key, default: 0] += 1
    }

    func count(for key: String) -> Int {
        values[key, default: 0]
    }
}

private func makeMockLocalInfoSession(
    handler: @escaping @Sendable (URLRequest) async throws -> (Int, String)
) -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockLocalInfoURLProtocol.self]
    MockLocalInfoURLProtocol.handler = handler
    return URLSession(configuration: configuration)
}

private final class MockLocalInfoURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) async throws -> (Int, String))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        Task {
            do {
                let (statusCode, body) = try await handler(request)
                let response = HTTPURLResponse(
                    url: try #require(request.url),
                    statusCode: statusCode,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(body.utf8))
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {}
}
