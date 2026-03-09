import CoreLocation
import Foundation
@testable import NomadCore
import Testing

struct FuelPriceProvidersTests {
    @Test
    func providerDecodesSpainFeedAndChoosesCheapestStationsWithinRadius() async throws {
        let provider = LiveEuropeanFuelPriceProvider(session: makeMockFuelSession(), ttl: 0)

        let snapshot = try await provider.prices(
            for: FuelSearchRequest(
                coordinate: CLLocationCoordinate2D(latitude: 39.4699, longitude: -0.3763),
                countryCode: "ES",
                countryName: "Spain"
            ),
            forceRefresh: true
        )

        #expect(snapshot.status == .ready)
        #expect(snapshot.diesel?.stationName == "Cheap Diesel")
        #expect(snapshot.gasoline?.stationName == "Cheap Gasoline")
    }

    @Test
    func providerDecodesFranceRecordsResponse() async throws {
        let provider = LiveEuropeanFuelPriceProvider(session: makeMockFuelSession(), ttl: 0)

        let snapshot = try await provider.prices(
            for: FuelSearchRequest(
                coordinate: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522),
                countryCode: "FR",
                countryName: "France"
            ),
            forceRefresh: true
        )

        #expect(snapshot.status == .ready)
        #expect(snapshot.diesel?.stationName == "Carrefour")
        #expect(snapshot.gasoline?.pricePerLiter == 1.799)
    }

    @Test
    func providerJoinsItalyStationAndPriceFeeds() async throws {
        let provider = LiveEuropeanFuelPriceProvider(session: makeMockFuelSession(), ttl: 0)

        let snapshot = try await provider.prices(
            for: FuelSearchRequest(
                coordinate: CLLocationCoordinate2D(latitude: 41.9028, longitude: 12.4964),
                countryCode: "IT",
                countryName: "Italy"
            ),
            forceRefresh: true
        )

        #expect(snapshot.status == .ready)
        #expect(snapshot.note == "Italian prices come from the daily 8:00 update.")
        #expect(snapshot.diesel?.isSelfService == true)
        #expect(snapshot.gasoline?.stationName == "Q8")
    }

    @Test
    func providerReturnsConfigurationRequirementForGermanyWithoutAPIKey() async throws {
        let provider = LiveEuropeanFuelPriceProvider(session: makeMockFuelSession(), ttl: 0, tankerkonigAPIKey: nil)

        let snapshot = try await provider.prices(
            for: FuelSearchRequest(
                coordinate: CLLocationCoordinate2D(latitude: 52.52, longitude: 13.405),
                countryCode: "DE",
                countryName: "Germany"
            ),
            forceRefresh: true
        )

        #expect(snapshot.status == .configurationRequired)
        #expect(snapshot.detail == "Germany needs a Tankerkönig API key in app config.")
    }

    @Test
    func providerReturnsUnsupportedForUnknownCountry() async throws {
        let provider = LiveEuropeanFuelPriceProvider(session: makeMockFuelSession(), ttl: 0)

        let snapshot = try await provider.prices(
            for: FuelSearchRequest(
                coordinate: CLLocationCoordinate2D(latitude: 60.1699, longitude: 24.9384),
                countryCode: "FI",
                countryName: "Finland"
            ),
            forceRefresh: true
        )

        #expect(snapshot.status == .unsupported)
        #expect(snapshot.detail == "Fuel prices are not supported in Finland yet.")
    }
}

private func makeMockFuelSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockFuelURLProtocol.self]
    MockFuelURLProtocol.handler = fuelResponse(for:)
    return URLSession(configuration: configuration)
}

private func fuelResponse(for request: URLRequest) throws -> (Data, URLResponse) {
    guard
        let url = request.url,
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
    else {
        throw ProviderError.invalidResponse
    }

    switch url.host {
    case "sedeaplicaciones.minetur.gob.es":
        return (Data(
            """
            {
              "ListaEESSPrecio": [
                {
                  "IDEESS": "1",
                  "Rótulo": "Cheap Diesel",
                  "Dirección": "Harbor 1",
                  "Municipio": "Valencia",
                  "Latitud": "39,4700",
                  "Longitud (WGS84)": "-0,3760",
                  "Precio Gasoleo A": "1,429",
                  "Precio Gasolina 95 E5": "1,559"
                },
                {
                  "IDEESS": "2",
                  "Rótulo": "Cheap Gasoline",
                  "Dirección": "Port 3",
                  "Municipio": "Valencia",
                  "Latitud": "39,4800",
                  "Longitud (WGS84)": "-0,3700",
                  "Precio Gasoleo A": "1,469",
                  "Precio Gasolina 95 E5": "1,509"
                },
                {
                  "IDEESS": "3",
                  "Rótulo": "Too Far",
                  "Dirección": "Distant 8",
                  "Municipio": "Alicante",
                  "Latitud": "38,3450",
                  "Longitud (WGS84)": "-0,4810",
                  "Precio Gasoleo A": "1,199",
                  "Precio Gasolina 95 E5": "1,199"
                }
              ]
            }
            """.utf8
        ), response)
    case "data.economie.gouv.fr":
        return (Data(
            """
            {
              "results": [
                {
                  "id": "station-1",
                  "enseigne": "Carrefour",
                  "adresse": "1 Rue de Paris",
                  "ville": "Paris",
                  "geom": { "lat": 48.8566, "lon": 2.3522 },
                  "gazole_prix": 1.689,
                  "sp95_e10_prix": 1.799,
                  "gazole_maj": "2026-03-09T08:00:00Z",
                  "sp95_e10_maj": "2026-03-09T08:00:00Z"
                }
              ]
            }
            """.utf8
        ), response)
    case "www.mimit.gov.it":
        if url.absoluteString.hasSuffix("/anagrafica_impianti_attivi.csv") {
            return (Data(
                """
                idImpianto;Gestore;Bandiera;TipoImpianto;NOME;Indirizzo;Comune;Provincia;Latitudine;Longitudine
                100;Gestore;Q8;Stradale;Q8 Roma;Via Roma 1;Roma;RM;41.9028;12.4964
                """.utf8
            ), response)
        }

        if url.absoluteString.hasSuffix("/prezzo_alle_8.csv") {
            return (Data(
                """
                idImpianto;descCarburante;prezzo;isSelf;dtComu
                100;Gasolio;1.659;1;09/03/2026 08:00:00
                100;Benzina;1.749;1;09/03/2026 08:00:00
                """.utf8
            ), response)
        }

        throw ProviderError.invalidResponse
    default:
        throw ProviderError.invalidResponse
    }
}

private final class MockFuelURLProtocol: URLProtocol, @unchecked Sendable {
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
