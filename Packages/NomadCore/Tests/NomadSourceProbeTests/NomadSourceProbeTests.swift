import Foundation
import NomadCore
@testable import NomadSourceProbe
import Testing

struct NomadSourceProbeTests {
    @Test
    func optionsParseFuelOverrides() throws {
        let options = try Options.parse(arguments: [
            "--country-code", "ES",
            "--latitude", "39.4699",
            "--longitude", "-0.3763",
            "--fuel-country-code", "DE",
            "--fuel-latitude", "52.52",
            "--fuel-longitude", "13.405",
            "--tankerkonig-api-key", "test-key"
        ])

        #expect(options.countryCode == "ES")
        #expect(options.fuelCountryCode == "DE")
        #expect(options.coordinate?.latitude == 39.4699)
        #expect(options.fuelCoordinate?.latitude == 52.52)
        #expect(options.tankerkonigAPIKey == "test-key")
    }

    @Test
    func fuelPriceProviderErrorsRenderStructuredProbeLines() {
        let lines = errorLines(for: FuelPriceProviderError(
            sourceName: "Spanish Ministry Fuel Prices",
            sourceURL: URL(string: "https://example.com/fuel"),
            stage: .requestStarted,
            details: FuelDiagnosticsError(
                failureKind: .dnsResolution,
                domain: NSURLErrorDomain,
                code: URLError.cannotFindHost.rawValue,
                localizedDescription: "A server with the specified hostname could not be found.",
                failingURL: URL(string: "https://example.com/fuel"),
                urlErrorSymbol: "cannotFindHost",
                summary: "Fuel source host could not be resolved."
            )
        ))

        #expect(lines.contains("fuel source: Spanish Ministry Fuel Prices"))
        #expect(lines.contains("fuel source URL: https://example.com/fuel"))
        #expect(lines.contains("fuel failure kind: dnsResolution"))
        #expect(lines.contains("fuel URL error symbol: cannotFindHost"))
        #expect(lines.contains("underlying: A server with the specified hostname could not be found."))
    }

    @Test
    func fuelHostResolutionFailuresProduceAppleStackHint() {
        let hint = errorHint(for: FuelPriceProviderError(
            sourceName: "Spanish Ministry Fuel Prices",
            sourceURL: nil,
            stage: .requestStarted,
            details: FuelDiagnosticsError(
                failureKind: .dnsResolution,
                domain: NSURLErrorDomain,
                code: URLError.cannotFindHost.rawValue,
                localizedDescription: "A server with the specified hostname could not be found.",
                failingURL: nil,
                urlErrorSymbol: "cannotFindHost",
                summary: "Fuel source host could not be resolved."
            )
        ))

        #expect(hint == "Apple URLSession could not resolve the host. Compare this with curl or nscurl --ats-diagnostics; curl reachability does not guarantee app reachability.")
    }

    @Test
    func fuelSnapshotLinesIncludeBothFuels() {
        let lines = fuelPriceLines(
            FuelPriceSnapshot(
                status: .ready,
                sourceName: "Spanish Ministry Fuel Prices",
                sourceURL: URL(string: "https://example.com/fuel"),
                countryCode: "ES",
                countryName: "Spain",
                searchRadiusKilometers: 50,
                diesel: FuelStationPrice(
                    fuelType: .diesel,
                    stationName: "Diesel Stop",
                    address: nil,
                    locality: nil,
                    pricePerLiter: 1.429,
                    distanceKilometers: 4.8,
                    latitude: 39.47,
                    longitude: -0.37,
                    updatedAt: nil
                ),
                gasoline: FuelStationPrice(
                    fuelType: .gasoline,
                    stationName: "Gasoline Stop",
                    address: nil,
                    locality: nil,
                    pricePerLiter: 1.509,
                    distanceKilometers: 6.2,
                    latitude: 39.48,
                    longitude: -0.36,
                    updatedAt: nil
                ),
                fetchedAt: .now,
                detail: "Cheapest prices within 50 km."
            )
        )

        #expect(lines.contains("status: ready"))
        #expect(lines.contains("diesel: Diesel Stop"))
        #expect(lines.contains("gasoline: Gasoline Stop"))
    }
}
