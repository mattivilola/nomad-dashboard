import Foundation
@testable import NomadCore
import Testing

struct PublicIPProvidersTests {
    @Test
    func decodesFreeIPAPIResponseIntoSnapshots() throws {
        let data = Data(
            """
            {
              "ipAddress": " 198.51.100.12 ",
              "cityName": "Helsinki",
              "regionName": "Uusimaa",
              "countryName": "Finland",
              "countryCode": "FI",
              "latitude": 60.1699,
              "longitude": 24.9384,
              "timeZones": ["Europe/Helsinki"]
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(FreeIPAPIResponse.self, from: data)
        let ipSnapshot = try response.publicIPSnapshot(provider: "freeipapi", fetchedAt: .now)
        let locationSnapshot = response.locationSnapshot(provider: "freeipapi", fetchedAt: .now)

        #expect(ipSnapshot.address == "198.51.100.12")
        #expect(locationSnapshot.city == "Helsinki")
        #expect(locationSnapshot.country == "Finland")
        #expect(locationSnapshot.countryCode == "FI")
        #expect(locationSnapshot.timeZone == "Europe/Helsinki")
    }

    @Test
    func decodesPartialFreeIPAPIResponseWithStringTimeZone() throws {
        let data = Data(
            """
            {
              "ipAddress": "203.0.113.42",
              "countryName": "Spain",
              "timeZones": "Europe/Madrid"
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(FreeIPAPIResponse.self, from: data)
        let locationSnapshot = response.locationSnapshot(provider: "freeipapi", fetchedAt: .now)

        #expect(locationSnapshot.city == nil)
        #expect(locationSnapshot.country == "Spain")
        #expect(locationSnapshot.timeZone == "Europe/Madrid")
    }
}
