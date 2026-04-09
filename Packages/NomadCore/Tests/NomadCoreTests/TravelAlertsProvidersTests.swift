import Foundation
@testable import NomadCore
import Testing
import WeatherKit

@Suite(.serialized)
struct TravelAlertsProvidersTests {
    @Test
    func bundledNeighborCountryResolverReturnsBundledBorders() {
        let resolver = BundledNeighborCountryResolver()

        #expect(resolver.neighboringCountryCodes(for: "ES") == ["AD", "FR", "GI", "MA", "PT"])
        #expect(resolver.neighboringCountryCodes(for: "IS").isEmpty)
    }

    @Test
    func advisorySignalUsesHighestNearbySeverity() throws {
        let signal = try SmartravellerAdvisoryProvider.signal(
            from: [
                AdvisoryMatch(
                    countryCode: "ES",
                    countryName: "Spain",
                    destination: SmartravellerDestination(
                        name: "Spain",
                        level: 1,
                        url: URL(string: "https://example.com/spain"),
                        updatedAt: .now
                    )
                ),
                AdvisoryMatch(
                    countryCode: "FR",
                    countryName: "France",
                    destination: SmartravellerDestination(
                        name: "France",
                        level: 2,
                        url: URL(string: "https://example.com/france"),
                        updatedAt: .now
                    )
                )
            ],
            primaryCountryCode: "ES",
            now: .now
        )

        #expect(signal.kind == .advisory)
        #expect(signal.severity == .caution)
        #expect(signal.summary == "France nearby: exercise a high degree of caution.")
        #expect(signal.sourceURL?.absoluteString == "https://example.com/france")
        #expect(signal.affectedCountryCodes == ["FR"])
    }

    @Test
    func advisorySignalUsesParsedPrimaryCountryDetailAsMainSummary() throws {
        let signal = try SmartravellerAdvisoryProvider.signal(
            from: [
                AdvisoryMatch(
                    countryCode: "FR",
                    countryName: "France",
                    destination: SmartravellerDestination(
                        name: "France",
                        level: 2,
                        url: URL(string: "https://example.com/france"),
                        updatedAt: .now
                    )
                )
            ],
            primaryCountryCode: "FR",
            detailSummary: "Exercise a high degree of caution in France due to the threat of terrorism.",
            now: .now
        )

        #expect(signal.summary == "Exercise a high degree of caution in France due to the threat of terrorism.")
        #expect(signal.detailSummary == "Exercise a high degree of caution in France due to the threat of terrorism.")
        #expect(signal.sourceURL?.absoluteString == "https://example.com/france")
    }

    @Test
    func advisoryProviderParsesLiveDestinationsHTML() throws {
        let destinations = try SmartravellerAdvisoryProvider.parseDestinations(
            from: Data(
                """
                <table>
                  <tr>
                    <th>Destination</th>
                    <th>Updates</th>
                    <th>Advice level</th>
                    <th>Last updated</th>
                  </tr>
                  <tr>
                    <td><a href="/destinations/france">France</a></td>
                    <td>Advisory</td>
                    <td>Exercise a high degree of caution</td>
                    <td>07 Apr 2026</td>
                  </tr>
                </table>
                """.utf8
            ),
            stage: "live destinations",
            baseURL: URL(string: "https://www.smartraveller.gov.au/destinations")!
        )

        #expect(destinations.count == 1)
        #expect(destinations.first?.name == "France")
        #expect(destinations.first?.level == 2)
        #expect(destinations.first?.url?.absoluteString == "https://www.smartraveller.gov.au/destinations/france")
    }

    @Test
    func advisoryProviderFallsBackFromLiveDestinationsToExport() async throws {
        let session = makeMockSession()
        let provider = SmartravellerAdvisoryProvider(
            session: session,
            ttl: 0,
            liveDestinationsURL: URL(string: "https://example.com/destinations")!,
            exportURL: URL(string: "https://example.com/destinations-export")!,
            requestTimeout: 1
        )

        MockTravelAlertsURLProtocol.handler = { request in
            guard let url = request.url else {
                throw ProviderError.invalidResponse
            }

            switch url.path {
            case "/destinations":
                throw URLError(.timedOut)
            case "/destinations-export":
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let body = Data("""
                [{"title":"France","advice_level":2,"url":"https://example.com/france","updated_at":"2026-04-07T10:00:00Z"}]
                """.utf8)
                return (body, response)
            default:
                throw ProviderError.invalidResponse
            }
        }

        let signal = try await provider.advisory(for: ["ES", "FR"], primaryCountryCode: "ES", forceRefresh: true)

        #expect(signal.severity == .caution)
        #expect(signal.summary == "France nearby: exercise a high degree of caution.")
        #expect(signal.sourceURL?.absoluteString == "https://example.com/france")
    }

    @Test
    func advisoryProviderFallsBackToBrowserHTMLAfterDirectFailures() async throws {
        let session = makeMockSession()
        let provider = SmartravellerAdvisoryProvider(
            session: session,
            ttl: 0,
            liveDestinationsURL: URL(string: "https://example.com/destinations")!,
            exportURL: URL(string: "https://example.com/destinations-export")!,
            browserFetcher: StubBrowserFetcher(
                result: .success(
                    """
                    <table>
                      <tr>
                        <td><a href="/destinations/france">France</a></td>
                        <td>Advisory</td>
                        <td>Exercise a high degree of caution</td>
                        <td>07 Apr 2026</td>
                      </tr>
                    </table>
                    """
                )
            ),
            requestTimeout: 1
        )

        MockTravelAlertsURLProtocol.handler = { request in
            guard let url = request.url else {
                throw ProviderError.invalidResponse
            }

            let response = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (Data("upstream unavailable".utf8), response)
        }

        let signal = try await provider.advisory(for: ["ES", "FR"], primaryCountryCode: "ES", forceRefresh: true)

        #expect(signal.severity == .caution)
        #expect(signal.summary == "France nearby: exercise a high degree of caution.")
        #expect(signal.sourceURL?.absoluteString == "https://www.smartraveller.gov.au/destinations/france")
    }

    @Test
    func advisoryProviderFetchesOptionalDestinationDetailWithoutAffectingSeveritySource() async throws {
        let session = makeMockSession()
        let provider = SmartravellerAdvisoryProvider(
            session: session,
            ttl: 0,
            liveDestinationsURL: URL(string: "https://example.com/destinations")!,
            exportURL: URL(string: "https://example.com/destinations-export")!,
            requestTimeout: 1
        )

        MockTravelAlertsURLProtocol.handler = { request in
            guard let url = request.url else {
                throw ProviderError.invalidResponse
            }

            switch url.path {
            case "/destinations":
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let body = Data("""
                [{"title":"France","advice_level":2,"url":"https://example.com/destinations/europe/france","updated_at":"2026-04-07T10:00:00Z"}]
                """.utf8)
                return (body, response)
            case "/destinations/europe/france":
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let body = Data("""
                <html><body><p>Exercise a high degree of caution in France due to the threat of terrorism. Higher levels apply in some areas.</p></body></html>
                """.utf8)
                return (body, response)
            default:
                throw ProviderError.invalidResponse
            }
        }

        let signal = try await provider.advisory(for: ["FR", "ES"], primaryCountryCode: "FR", forceRefresh: true)

        #expect(signal.severity == .caution)
        #expect(signal.summary == "Exercise a high degree of caution in France due to the threat of terrorism.")
        #expect(signal.detailSummary == "Exercise a high degree of caution in France due to the threat of terrorism.")
        #expect(signal.sourceURL?.absoluteString == "https://example.com/destinations/europe/france")
    }

    @Test
    func advisoryProviderIgnoresDestinationDetailFetchFailure() async throws {
        let session = makeMockSession()
        let provider = SmartravellerAdvisoryProvider(
            session: session,
            ttl: 0,
            liveDestinationsURL: URL(string: "https://example.com/destinations")!,
            exportURL: URL(string: "https://example.com/destinations-export")!,
            requestTimeout: 1
        )

        MockTravelAlertsURLProtocol.handler = { request in
            guard let url = request.url else {
                throw ProviderError.invalidResponse
            }

            switch url.path {
            case "/destinations":
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let body = Data("""
                [{"title":"France","advice_level":2,"url":"https://example.com/destinations/europe/france","updated_at":"2026-04-07T10:00:00Z"}]
                """.utf8)
                return (body, response)
            case "/destinations/europe/france":
                throw URLError(.timedOut)
            default:
                throw ProviderError.invalidResponse
            }
        }

        let signal = try await provider.advisory(for: ["ES", "FR"], primaryCountryCode: "ES", forceRefresh: true)

        #expect(signal.severity == .caution)
        #expect(signal.summary == "France nearby: exercise a high degree of caution.")
        #expect(signal.detailSummary == nil)
        #expect(signal.sourceURL?.absoluteString == "https://example.com/destinations/europe/france")
    }

    @Test
    func advisoryProviderParsesDestinationDetailSummarySentence() {
        let summary = SmartravellerAdvisoryProvider.parseDestinationDetailSummary(
            from: Data(
                """
                <html>
                  <body>
                    <p>Do not travel to parts of Exampleland.</p>
                    <p>Exercise a high degree of caution in France due to the threat of terrorism. Monitor local media.</p>
                  </body>
                </html>
                """.utf8
            )
        )

        #expect(summary == "Do not travel to parts of Exampleland.")
    }

    @Test
    func advisoryProviderMergesStageFailuresWhenAllFallbacksFail() async throws {
        let session = makeMockSession()
        let provider = SmartravellerAdvisoryProvider(
            session: session,
            ttl: 0,
            liveDestinationsURL: URL(string: "https://example.com/destinations")!,
            exportURL: URL(string: "https://example.com/destinations-export")!,
            browserFetcher: StubBrowserFetcher(result: .failure(StubBrowserFetcherError(message: "Navigation failed"))),
            requestTimeout: 1
        )

        MockTravelAlertsURLProtocol.handler = { request in
            throw URLError(.timedOut)
        }

        do {
            _ = try await provider.advisory(for: ["ES", "FR"], primaryCountryCode: "ES", forceRefresh: true)
            Issue.record("Expected Smartraveller provider to fail after all fallbacks.")
        } catch let error as SmartravellerProviderError {
            #expect(error.diagnosticSummary == "Smartraveller request timed out.")
            #expect(error.description.contains("live destinations"))
            #expect(error.description.contains("destinations-export"))
            #expect(error.description.contains("browser fallback"))
        }
    }

    @Test
    func smartravellerTimedOutRequestUsesExplicitDiagnosticSummary() {
        let error = SmartravellerProviderError.requestFailed(
            stage: "live destinations",
            message: "The request timed out.",
            code: .timedOut
        )

        #expect(error.diagnosticSummary == "Smartraveller request timed out.")
    }

    @Test
    func weatherSignalPreservesAttributionAndHighestSeverity() throws {
        let signal = try WeatherKitAlertProvider.signal(
            from: [
                WeatherAlertPayload(
                    detailsURL: #require(URL(string: "https://weather.example/minor")),
                    source: "National Weather Service",
                    summary: "Wind advisory.",
                    severity: .info
                ),
                WeatherAlertPayload(
                    detailsURL: #require(URL(string: "https://weather.example/severe")),
                    source: "National Weather Service",
                    summary: "Flood warning.",
                    severity: .warning
                )
            ],
            fetchedAt: .now
        )

        #expect(signal.kind == .weather)
        #expect(signal.severity == .warning)
        #expect(signal.sourceName == "National Weather Service")
        #expect(signal.sourceURL?.absoluteString == "https://weather.example/severe")
        #expect(signal.itemCount == 2)
    }

    @Test
    func securitySignalMapsRecencyAndCountsToCautionLevels() {
        let now = Date()
        let signal = ReliefWebSecurityProvider.signal(
            from: [
                SecurityReportPayload(
                    title: "Border protest update",
                    date: now.addingTimeInterval(-6 * 3_600),
                    primaryCountryName: "France",
                    sourceName: "ReliefWeb",
                    urlAlias: "/report/france/border-protest"
                ),
                SecurityReportPayload(
                    title: "Transit disruption advisory",
                    date: now.addingTimeInterval(-18 * 3_600),
                    primaryCountryName: "Portugal",
                    sourceName: "ReliefWeb",
                    urlAlias: "/report/portugal/transit"
                )
            ],
            primaryCountryName: "Spain",
            matchedCountryNames: ["Spain", "France", "Portugal"],
            now: now
        )

        #expect(signal.kind == .security)
        #expect(signal.severity == .caution)
        #expect(signal.itemCount == 2)
        #expect(signal.summary == "2 nearby security bulletins were published recently.")
        #expect(signal.sourceURL?.absoluteString == "https://reliefweb.int/report/france/border-protest")
    }

    @Test
    func securityProviderBuildsDocumentedRequestAndSurfacesConfiguredHTTPErrors() async throws {
        let session = makeMockSession()
        let provider = ReliefWebSecurityProvider(session: session, ttl: 0, appName: "NomadDashboardTests")

        MockTravelAlertsURLProtocol.handler = { request in
            #expect(request.url?.absoluteString.contains("/v2/reports?appname=NomadDashboardTests") == true)
            #expect(String(data: request.httpBody ?? Data(), encoding: .utf8)?.contains("\"appname\"") == false)

            guard
                let url = request.url,
                let response = HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: nil)
            else {
                throw ProviderError.invalidResponse
            }

            return (Data("{\"message\":\"rate limited\"}".utf8), response)
        }

        await #expect(throws: ReliefWebProviderError.unexpectedStatus(429, bodySnippet: "{\"message\":\"rate limited\"}")) {
            try await provider.security(for: ["ES", "FR"], primaryCountryCode: "ES", forceRefresh: true)
        }

        MockTravelAlertsURLProtocol.handler = { request in
            guard
                let url = request.url,
                let response = HTTPURLResponse(url: url, statusCode: 403, httpVersion: nil, headerFields: nil)
            else {
                throw ProviderError.invalidResponse
            }

            return (
                Data("""
                {"status":403,"error":{"message":"You are not using an approved appname. Kindly request an appname from ReliefWeb here: https://apidoc.reliefweb.int/parameters#appname"}}
                """.utf8),
                response
            )
        }

        await #expect(throws: ReliefWebProviderError.appNameApprovalRequired("You are not using an approved appname. Kindly request an appname from ReliefWeb here: https://apidoc.reliefweb.int/parameters#appname")) {
            try await provider.security(for: ["ES", "FR"], primaryCountryCode: "ES", forceRefresh: true)
        }
    }

    @Test
    func securityProviderSurfacesInvalidPayloadAsDiagnosticError() throws {
        #expect(throws: ReliefWebProviderError.invalidPayload("Missing top-level data array.")) {
            _ = try ReliefWebSecurityProvider.parseReports(from: Data("{\"unexpected\":[]}".utf8))
        }
    }
}

private func makeMockSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockTravelAlertsURLProtocol.self]
    return URLSession(configuration: configuration)
}

private struct StubBrowserFetcher: SmartravellerBrowserFetcher {
    let result: Result<String, Error>

    func destinationsHTML() async throws -> String {
        try result.get()
    }
}

private struct StubBrowserFetcherError: Error {
    let message: String

    var localizedDescription: String {
        message
    }
}

private final class MockTravelAlertsURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Data, URLResponse))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: ProviderError.invalidResponse)
            return
        }

        do {
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
