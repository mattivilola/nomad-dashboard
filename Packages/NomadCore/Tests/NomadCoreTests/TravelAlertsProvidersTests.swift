import Foundation
@testable import NomadCore
import Testing
import WeatherKit

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
        #expect(signal.summary == "France is at Level 2 nearby.")
        #expect(signal.sourceURL?.absoluteString == "https://example.com/france")
        #expect(signal.affectedCountryCodes == ["FR"])
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
