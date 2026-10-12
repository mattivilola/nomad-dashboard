import Foundation
import NomadCore
import Testing

struct AirQualityModelsTests {
    // MARK: - European AQI bands

    @Test
    func bandsStartAtTheirLowerBoundAndVeryPoorEndsAtOneHundred() {
        let expectations: [(Int, EuropeanAQIBand)] = [
            (0, .good), (19, .good), (20, .fair), (39, .fair), (40, .moderate), (59, .moderate),
            (60, .poor), (79, .poor), (80, .veryPoor), (100, .veryPoor), (101, .extremelyPoor), (250, .extremelyPoor)
        ]
        for (index, band) in expectations {
            #expect(EuropeanAQIBand(index: index) == band, "AQI \(index)")
        }
        #expect(EuropeanAQIBand.good < .extremelyPoor)
        #expect(EuropeanAQIBand.allCases.map(\.title) == ["Good", "Fair", "Moderate", "Poor", "Very poor", "Extremely poor"])
    }

    @Test
    func dominantPollutantIsTheHighestSubIndexWithEarlierPollutantWinningTies() {
        #expect(AirQualityPollutant.dominant(in: [.pm2_5: 40, .pm10: 55, .ozone: 20]) == .pm10)
        #expect(AirQualityPollutant.dominant(in: [.ozone: 70, .nitrogenDioxide: 30]) == .ozone)
        #expect(AirQualityPollutant.dominant(in: [.pm10: 50, .pm2_5: 50]) == .pm2_5)
        #expect(AirQualityPollutant.dominant(in: [.sulphurDioxide: 12]) == .sulphurDioxide)
        #expect(AirQualityPollutant.dominant(in: [.pm2_5: 0, .pm10: 0]) == nil)
        #expect(AirQualityPollutant.dominant(in: [:]) == nil)
    }

    // MARK: - Codable compatibility

    @Test
    func weatherSnapshotsCachedBeforeUVStillDecode() throws {
        let weather = WeatherSnapshot(
            currentTemperatureCelsius: 20,
            apparentTemperatureCelsius: 19,
            conditionDescription: "Clear",
            symbolName: "sun.max.fill",
            precipitationChance: 0,
            windSpeedKph: 5,
            windDirectionDegrees: 90,
            uvIndex: 8,
            hourlyForecastSlots: [
                WeatherHourlyForecastSlot(
                    date: Date(timeIntervalSince1970: 1_700_000_000),
                    symbolName: "sun.max.fill",
                    conditionDescription: "Clear",
                    temperatureCelsius: 21,
                    precipitationChance: 0,
                    windSpeedKph: 6,
                    windDirectionDegrees: 80,
                    uvIndex: 9
                )
            ],
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let roundTripped = try JSONDecoder().decode(WeatherSnapshot.self, from: JSONEncoder().encode(weather))
        #expect(roundTripped == weather)
        #expect(roundTripped.uvIndex == 8)
        #expect(roundTripped.hourlyForecastSlots.first?.uvIndex == 9)

        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(weather)) as? [String: Any])
        object.removeValue(forKey: "uvIndex")
        var slots = try #require(object["hourlyForecastSlots"] as? [[String: Any]])
        slots = slots.map { slot in
            var slot = slot
            slot.removeValue(forKey: "uvIndex")
            return slot
        }
        object["hourlyForecastSlots"] = slots

        let legacy = try JSONDecoder().decode(WeatherSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(legacy.uvIndex == nil)
        #expect(legacy.hourlyForecastSlots.first?.uvIndex == nil)
        #expect(legacy.currentTemperatureCelsius == 20)
    }

    @Test
    func offlineContentSavedBeforeAirQualityStillDecodesAndKeepsNewValues() throws {
        let savedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let content = OfflineDashboardContent(snapshot: .preview, savedAt: savedAt, locationKey: "ES:Valencia")
        #expect(content.airQuality != nil)
        #expect(content.weather?.uvIndex != nil)

        let data = try JSONEncoder().encode(content)
        #expect(try JSONDecoder().decode(OfflineDashboardContent.self, from: data) == content)

        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "airQuality")
        let legacy = try JSONDecoder().decode(OfflineDashboardContent.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(legacy.airQuality == nil)
        #expect(legacy.weather == content.weather)
        #expect(legacy.applying(to: .placeholder).airQuality == nil)
    }

    @Test
    func offlineCacheRoundTripKeepsAirQualityAndUV() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("offline.json")
        let cache = OfflineDashboardCache(fileURL: fileURL)
        let content = OfflineDashboardContent(snapshot: .preview, savedAt: .now, locationKey: nil)

        try await cache.save(content)
        let loaded = try #require(await cache.load())
        let applied = loaded.applying(to: .placeholder)

        #expect(applied.airQuality == DashboardSnapshot.preview.airQuality)
        #expect(applied.weather?.uvIndex == DashboardSnapshot.preview.weather?.uvIndex)
        #expect(applied.weather?.hourlyForecastSlots.map(\.uvIndex) == DashboardSnapshot.preview.weather?.hourlyForecastSlots.map(\.uvIndex))
    }

    // MARK: - Settings

    @Test
    func airQualityIsOnByDefaultAndLegacySettingsDecodeToOn() throws {
        #expect(AppSettings().airQualityEnabled)

        var settings = AppSettings()
        settings.airQualityEnabled = false
        let off = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(off.airQualityEnabled == false)

        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings())) as? [String: Any])
        object.removeValue(forKey: "airQualityEnabled")
        let legacy = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(legacy.airQualityEnabled)
    }

    @Test
    func airQualityNeedsTheWeatherLocationConsent() {
        var settings = AppSettings()
        #expect(settings.isAirQualityActive)
        settings.useCurrentLocationForWeather = false
        #expect(settings.isAirQualityActive == false)
        settings.useCurrentLocationForWeather = true
        settings.airQualityEnabled = false
        #expect(settings.isAirQualityActive == false)
    }

    @Test
    func newSectionHasATitleAndIsNotALargeDownload() {
        #expect(DashboardDataSection.airQuality.title == "Air quality")
        #expect(DashboardDataSection.airQuality.isLargeDownload == false)
    }
}
