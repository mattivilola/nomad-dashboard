import Foundation
import NomadCore
@testable import NomadUI
import Testing

struct WeatherAirPresentationTests {
    private typealias Support = StaysTestSupport

    // MARK: UV

    private func weather(uv: Int?, slots: [(hours: Double, uv: Int?)] = []) -> WeatherSnapshot {
        WeatherSnapshot(
            currentTemperatureCelsius: 24,
            apparentTemperatureCelsius: 25,
            conditionDescription: "Sunny",
            symbolName: "sun.max.fill",
            precipitationChance: 0,
            windSpeedKph: 10,
            windDirectionDegrees: 90,
            uvIndex: uv,
            hourlyForecastSlots: slots.map { slot in
                WeatherHourlyForecastSlot(
                    date: Support.now.addingTimeInterval(slot.hours * 3_600),
                    symbolName: "sun.max",
                    conditionDescription: "Sunny",
                    temperatureCelsius: 25,
                    precipitationChance: 0,
                    windSpeedKph: 10,
                    windDirectionDegrees: 90,
                    uvIndex: slot.uv
                )
            },
            fetchedAt: Support.now
        )
    }

    private func uv(_ weather: WeatherSnapshot?) -> WeatherUVPresentation? {
        WeatherUVPresentation(
            weather: weather,
            travelContext: DashboardSnapshot.preview.travelContext,
            now: Support.now,
            calendar: Support.calendar,
            locale: Support.locale
        )
    }

    @Test
    func uvNamesTheWhoBand() {
        #expect(uv(weather(uv: 7))?.value == "7 (high)")
        #expect(uv(weather(uv: 7))?.text == "UV 7 (high)")
        #expect(uv(weather(uv: 2))?.value == "2 (low)")
        #expect(uv(weather(uv: 4))?.value == "4 (moderate)")
        #expect(uv(weather(uv: 9))?.value == "9 (very high)")
        #expect(uv(weather(uv: 11))?.value == "11 (extreme)")
    }

    @Test
    func uvTintsFollowTheWhoBands() {
        #expect(uv(weather(uv: 5))?.tone == .neutral)
        #expect(uv(weather(uv: 6))?.tone == .caution)
        #expect(uv(weather(uv: 7))?.tone == .caution)
        #expect(uv(weather(uv: 8))?.tone == .caution)
        #expect(uv(weather(uv: 10))?.tone == .caution)
        #expect(uv(weather(uv: 11))?.tone == .attention)
    }

    @Test
    func uvNeedsAReading() {
        #expect(uv(weather(uv: nil)) == nil)
        #expect(uv(nil) == nil)
    }

    @Test
    func uvShowsTheRestOfTheDaysPeakWhenItIsHigher() {
        // 12:00 UTC now; slots at 13:00, 14:00 and tomorrow.
        let result = uv(weather(uv: 7, slots: [(1, 9), (2, 8), (26, 11)]))

        #expect(result?.peak?.hasPrefix("peak 9 at ") == true)
        #expect(result?.tone == .caution)
    }

    @Test
    func uvHasNoPeakWhenNothingHigherFollowsToday() {
        #expect(uv(weather(uv: 9, slots: [(1, 8), (26, 11)]))?.peak == nil)
        #expect(uv(weather(uv: 9))?.peak == nil)
    }

    // MARK: Air quality

    private func airQuality(aqi: Int, pollutant: AirQualityPollutant? = .pm10, outlook: [Int?] = []) -> AirQualitySnapshot {
        AirQualitySnapshot(
            latitude: 34,
            longitude: -6.8,
            sourceName: "Open-Meteo",
            europeanAQI: aqi,
            mainPollutant: pollutant,
            pm2_5: 12,
            pm10: 30.4,
            ozone: 80,
            nitrogenDioxide: 14,
            forecastSlots: outlook.enumerated().map { index, value in
                AirQualityForecastSlot(date: Support.now.addingTimeInterval(Double(index + 1) * 3_600), europeanAQI: value)
            },
            fetchedAt: Support.now
        )
    }

    private func aqi(
        _ snapshot: AirQualitySnapshot?,
        settings: AppSettings = AppSettings()
    ) -> WeatherAirQualityPresentation? {
        WeatherAirQualityPresentation(
            airQuality: snapshot,
            settings: settings,
            travelContext: DashboardSnapshot.preview.travelContext,
            now: Support.now,
            calendar: Support.calendar,
            locale: Support.locale
        )
    }

    @Test
    func theHeadlineHasTheIndexBandAndMainPollutant() {
        #expect(aqi(airQuality(aqi: 38, pollutant: .pm10))?.headline == "AQI 38 · Fair · mostly PM10")
        #expect(aqi(airQuality(aqi: 64, pollutant: .ozone))?.headline == "AQI 64 · Poor · mostly ozone")
        #expect(aqi(airQuality(aqi: 12, pollutant: nil))?.headline == "AQI 12 · Good")
    }

    @Test
    func bandTintsStayNeutralUntilPoor() {
        #expect(aqi(airQuality(aqi: 10))?.tone == .neutral)
        #expect(aqi(airQuality(aqi: 39))?.tone == .neutral)
        #expect(aqi(airQuality(aqi: 59))?.tone == .neutral)
        #expect(aqi(airQuality(aqi: 60))?.tone == .caution)
        #expect(aqi(airQuality(aqi: 79))?.tone == .caution)
        #expect(aqi(airQuality(aqi: 80))?.tone == .attention)
        #expect(aqi(airQuality(aqi: 140))?.tone == .attention)
    }

    @Test
    func theOutlookIsABarPerHourWithItsPeak() throws {
        let result = try #require(aqi(airQuality(aqi: 38, outlook: [40, 55, 64, 50])))

        #expect(result.bars.count == 4)
        #expect(result.bars.map(\.tone) == [.neutral, .neutral, .caution, .neutral])
        #expect(abs(result.bars[2].height - 0.64) < 0.0001)
        #expect(result.bars[2].help.hasSuffix("AQI 64 · Poor"))
        #expect(result.outlookCaption?.hasPrefix("Next 4 h · peak 64 at ") == true)
    }

    @Test
    func missingOutlookHoursAreSkipped() throws {
        let result = try #require(aqi(airQuality(aqi: 38, outlook: [nil, 50])))

        #expect(result.bars.count == 1)
        #expect(aqi(airQuality(aqi: 38))?.outlookCaption == nil)
        #expect(aqi(airQuality(aqi: 38))?.bars.isEmpty == true)
    }

    @Test
    func airQualityNeedsTheSettingAndWeatherLocation() {
        let snapshot = airQuality(aqi: 38)

        #expect(aqi(snapshot, settings: AppSettings(airQualityEnabled: false)) == nil)
        #expect(aqi(snapshot, settings: AppSettings(useCurrentLocationForWeather: false)) == nil)
        #expect(aqi(nil) == nil)
        #expect(aqi(snapshot) != nil)
    }

    @Test
    func theHelpListsTheConcentrations() {
        let help = aqi(airQuality(aqi: 38))?.help

        #expect(help?.contains("PM2.5 12 µg/m³") == true)
        #expect(help?.contains("PM10 30 µg/m³") == true)
    }

    @Test
    func offlineEssentialsSummarisesTheSavedReading() {
        #expect(OfflineEssentialsPresentation.airQualitySummary(airQuality(aqi: 64)) == "AQI 64 (poor) · saved")
        #expect(OfflineEssentialsPresentation.airQualitySummary(airQuality(aqi: 12)) == "AQI 12 (good) · saved")
    }

    @Test
    func theAirQualitySectionHasATitle() {
        #expect(DashboardDataSection.airQuality.title == "Air quality")
    }
}
