import CoreLocation
import Foundation
@testable import NomadCore
import Testing

struct LiveWeatherProviderTests {
    @Test
    func manualRefreshBypassesFreshWeatherCache() async throws {
        let loader = WeatherLoadCounter()
        let provider = LiveWeatherProvider(loadSnapshot: { _ in await loader.load() })
        let coordinate = CLLocationCoordinate2D(latitude: 43, longitude: -1)
        _ = try await provider.weather(for: coordinate)
        _ = try await provider.weather(for: coordinate)
        #expect(await loader.count == 1)
        _ = try await provider.weather(for: coordinate, forceRefresh: true)
        #expect(await loader.count == 2)
    }

    @Test
    func dailyOutlookDropsPastDaysAndIncludesToday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Paris"))
        let now = try #require(calendar.date(from: DateComponents(year: 2_026, month: 10, day: 19, hour: 15)))
        let days = (-2...8).map { offset in
            WeatherDaySummary(date: calendar.date(byAdding: .day, value: offset, to: now)!, symbolName: "cloud", summary: "Day \(offset)", temperatureMinCelsius: 10, temperatureMaxCelsius: 20, precipitationChance: 0)
        }
        let upcoming = LiveWeatherProvider.upcomingDailyForecasts(days.reversed(), now: now, calendar: calendar)
        #expect(upcoming.count == 7)
        #expect(upcoming.first?.summary == "Day 0")
        #expect(upcoming.last?.summary == "Day 6")
    }

    @Test
    func weatherSnapshotSelectsTomorrowWhenDailyForecastStartsToday() {
        let now = Date()
        let days = (0...1).map { offset in
            WeatherDaySummary(date: Calendar.current.date(byAdding: .day, value: offset, to: now)!, symbolName: "cloud", summary: "Day \(offset)", temperatureMinCelsius: 10, temperatureMaxCelsius: 20, precipitationChance: 0)
        }
        let snapshot = WeatherSnapshot(currentTemperatureCelsius: 20, apparentTemperatureCelsius: 19, conditionDescription: "Cloudy", symbolName: "cloud", precipitationChance: 0, windSpeedKph: 10, windDirectionDegrees: 0, dailyForecast: days, fetchedAt: now)
        #expect(snapshot.tomorrow == days[1])
    }

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

    @Test
    func forecastTargetDatesUseConfiguredHourOffsets() {
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

        let targetDates = LiveWeatherProvider.forecastTargetDates(from: referenceDate)

        #expect(targetDates.count == 4)
        #expect(abs(targetDates[0].timeIntervalSince(referenceDate) - (3 * 3_600)) < 1)
        #expect(abs(targetDates[1].timeIntervalSince(referenceDate) - (6 * 3_600)) < 1)
        #expect(abs(targetDates[2].timeIntervalSince(referenceDate) - (12 * 3_600)) < 1)
        #expect(abs(targetDates[3].timeIntervalSince(referenceDate) - (24 * 3_600)) < 1)
    }

    @Test
    func upcomingDailyForecastsLimitToSevenDaysStartingTomorrow() {
        let dailyForecast = (1...10).map { dayOffset in
            WeatherDaySummary(
                date: Calendar.current.date(byAdding: .day, value: dayOffset, to: .now) ?? .now,
                symbolName: "sun.max.fill",
                summary: "Day \(dayOffset)",
                temperatureMinCelsius: Double(dayOffset),
                temperatureMaxCelsius: Double(dayOffset + 10),
                precipitationChance: Double(dayOffset) / 100
            )
        }

        let upcoming = LiveWeatherProvider.upcomingDailyForecasts(dailyForecast)

        #expect(upcoming.count == 7)
        #expect(upcoming.first?.summary == "Day 1")
        #expect(upcoming.last?.summary == "Day 7")
    }

    @Test
    func weatherSnapshotUsesFirstDailyForecastAsTomorrow() {
        let dailyForecast = [
            WeatherDaySummary(
                date: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now,
                symbolName: "cloud.sun.fill",
                summary: "Tomorrow",
                temperatureMinCelsius: 11,
                temperatureMaxCelsius: 19,
                precipitationChance: 0.2
            ),
            WeatherDaySummary(
                date: Calendar.current.date(byAdding: .day, value: 2, to: .now) ?? .now,
                symbolName: "sun.max.fill",
                summary: "Later",
                temperatureMinCelsius: 12,
                temperatureMaxCelsius: 21,
                precipitationChance: 0.1
            )
        ]

        let snapshot = WeatherSnapshot(
            currentTemperatureCelsius: 18,
            apparentTemperatureCelsius: 18,
            conditionDescription: "Clear",
            symbolName: "sun.max.fill",
            precipitationChance: 0.1,
            windSpeedKph: 9,
            windDirectionDegrees: 45,
            dailyForecast: dailyForecast,
            fetchedAt: .now
        )

        #expect(snapshot.tomorrow == dailyForecast.first)
        #expect(snapshot.dailyForecast.count == 2)
    }
}

private actor WeatherLoadCounter {
    var count = 0

    func load() -> WeatherSnapshot {
        count += 1
        return WeatherSnapshot(currentTemperatureCelsius: 20, apparentTemperatureCelsius: 19, conditionDescription: "Cloudy", symbolName: "cloud", precipitationChance: 0, windSpeedKph: 10, windDirectionDegrees: 0, fetchedAt: .now)
    }
}
