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
    func weatherSignalPreservesAttributionAndHighestSeverity() {
        let signal = WeatherKitAlertProvider.signal(
            from: [
                WeatherAlertPayload(
                    detailsURL: URL(string: "https://weather.example/minor")!,
                    source: "National Weather Service",
                    summary: "Wind advisory.",
                    severity: .minor
                ),
                WeatherAlertPayload(
                    detailsURL: URL(string: "https://weather.example/severe")!,
                    source: "National Weather Service",
                    summary: "Flood warning.",
                    severity: .severe
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
}
