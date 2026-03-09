import Foundation
@testable import NomadCore
import Testing

struct LiveWeatherProviderTests {
    @Test
    func nearTermPrecipitationChancePrefersMinuteForecast() {
        let chance = LiveWeatherProvider.nearTermPrecipitationChance(
            minuteForecastChance: 0.42,
            hourlyForecastChance: 0.18
        )

        #expect(chance == 0.42)
    }

    @Test
    func nearTermPrecipitationChanceFallsBackToHourlyForecast() {
        let chance = LiveWeatherProvider.nearTermPrecipitationChance(
            minuteForecastChance: nil,
            hourlyForecastChance: 0.18
        )

        #expect(chance == 0.18)
    }

    @Test
    func nearTermPrecipitationChanceReturnsNilWhenForecastsHaveNoChance() {
        let chance = LiveWeatherProvider.nearTermPrecipitationChance(
            minuteForecastChance: nil,
            hourlyForecastChance: nil
        )

        #expect(chance == nil)
    }
}
