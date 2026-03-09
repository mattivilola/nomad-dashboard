import CoreLocation
import NomadCore
import Testing

struct LocationAuthorizationTests {
    @Test
    func whenInUseAuthorizationIsAcceptedForWeather() {
        #expect(CLAuthorizationStatus(rawValue: 4)?.isNomadWeatherAuthorized == true)
        #expect(CLAuthorizationStatus.authorizedAlways.isNomadWeatherAuthorized)
        #expect(CLAuthorizationStatus.denied.isNomadWeatherAuthorized == false)
    }
}
