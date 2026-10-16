import Foundation
@testable import NomadCore
import Testing

struct UVAndAirQualityInsightTests {
    // MARK: - UV index

    @Test
    func uvBelowSixProducesNothing() {
        for uv in [0, 3, 5] {
            #expect(insights(weather: weather(uv: uv, slots: [slot(hours: 1, uv: uv)])).isEmpty)
        }
        #expect(insights(weather: weather(uv: nil, slots: [slot(hours: 1, uv: nil)])).isEmpty)
    }

    @Test
    func uvCategoryThresholdsFollowWHOBands() throws {
        let expectations: [(uv: Int, severity: DashboardInsightSeverity)] = [
            (6, .info), (7, .info), (8, .caution), (10, .caution), (11, .attention), (14, .attention)
        ]
        for (uv, severity) in expectations {
            let insight = try #require(insights(weather: weather(uv: 0, slots: [slot(hours: 1, uv: uv)])).first)
            #expect(insight.kind == .uvIndex)
            #expect(insight.severity == severity, "UV \(uv)")
            #expect(insight.menuBarText == "UV \(uv)")
            #expect(insight.relatedCard == .weather)
        }
    }

    @Test
    func extremeUVIsAttentionWithTheContiguousTimeRange() throws {
        let weather = weather(uv: 5, slots: [slot(hours: 1, uv: 11), slot(hours: 2, uv: 12), slot(hours: 3, uv: 7)])
        let insight = try #require(insights(weather: weather).first)

        #expect(insight.severity == .attention)
        #expect(insight.symbolName == "sun.max.trianglebadge.exclamationmark")
        #expect(insight.title == "UV extreme (12) \(clock(hours: 1))\u{2013}\(clock(hours: 2))")
        #expect(insight.detail == "Avoid midday sun; cover up and use SPF 30+")
        #expect(insight.menuBarText == "UV 12")
    }

    @Test
    func veryHighUVIsCautionAndNamesOnlyTheStart() throws {
        let weather = weather(uv: 4, slots: [slot(hours: 1, uv: 9), slot(hours: 2, uv: 9), slot(hours: 3, uv: 6)])
        let insight = try #require(insights(weather: weather).first)

        #expect(insight.severity == .caution)
        #expect(insight.symbolName == "sun.max.trianglebadge.exclamationmark")
        #expect(insight.title == "UV very high (9) from \(clock(hours: 1))")
        #expect(insight.detail == "Seek shade at midday; SPF 30+")
        #expect(insight.menuBarText == "UV 9")
    }

    @Test
    func highUVIsInfoWithTheSunSymbol() throws {
        let weather = weather(uv: 3, slots: [slot(hours: 1, uv: 6), slot(hours: 2, uv: 7), slot(hours: 3, uv: 6)])
        let insight = try #require(insights(weather: weather).first)

        #expect(insight.severity == .info)
        #expect(insight.symbolName == "sun.max")
        #expect(insight.title == "UV high (7) \(clock(hours: 1))\u{2013}\(clock(hours: 3))")
        #expect(insight.detail == "Hat and sunscreen around midday")
    }

    @Test
    func uvRangeStopsAtAGapBelowTheCategoryFloor() throws {
        // 8, then 3, then 9: the peak (9) is only the last reading, so the range does not bridge the dip.
        let weather = weather(uv: 0, slots: [slot(hours: 1, uv: 8), slot(hours: 2, uv: 3), slot(hours: 3, uv: 9)])
        let insight = try #require(insights(weather: weather).first)
        #expect(insight.title == "UV very high (9) from \(clock(hours: 3))")
    }

    @Test
    func uvPeakTiesKeepTheEarliestRun() throws {
        let weather = weather(uv: 0, slots: [slot(hours: 1, uv: 7), slot(hours: 2, uv: 3), slot(hours: 3, uv: 7)])
        let insight = try #require(insights(weather: weather).first)
        #expect(insight.title == "UV high (7) around \(clock(hours: 1))")
    }

    @Test
    func currentUVCountsAsNowWhenFreshAndIsIgnoredWhenStale() throws {
        let fresh = try #require(insights(weather: weather(uv: 9, slots: [])).first)
        #expect(fresh.title == "UV very high (9) from now")

        let withSlot = try #require(insights(weather: weather(uv: 7, slots: [slot(hours: 1, uv: 7)])).first)
        #expect(withSlot.title == "UV high (7) now\u{2013}\(clock(hours: 1))")

        let single = try #require(insights(weather: weather(uv: 7, slots: [])).first)
        #expect(single.title == "UV high (7) now")

        let stale = weather(uv: 9, slots: [], fetchedAt: now.addingTimeInterval(-3 * 3_600))
        #expect(insights(weather: stale).isEmpty)
    }

    @Test
    func uvIgnoresPastSlotsAndEverythingAfterSunset() throws {
        let sunset = try #require(parisSun.sunset)
        #expect(insights(weather: weather(uv: 0, slots: [slot(hours: -1, uv: 11)])).isEmpty)

        // Slots after sunset are dropped even when they carry UV; the last daylight slot still counts.
        let beyondSunset = sunset.timeIntervalSince(now) / 3_600 + 0.5
        #expect(insights(weather: weather(uv: 0, slots: [slot(hours: beyondSunset, uv: 9)])).isEmpty)
        let beforeSunset = insights(weather: weather(uv: 0, slots: [slot(hours: beyondSunset - 1, uv: 9)]))
        #expect(beforeSunset.first?.kind == .uvIndex)

        // After sunset the current reading no longer counts either.
        let evening = sunset.addingTimeInterval(3_600)
        let night = weather(uv: 9, slots: [], fetchedAt: evening)
        #expect(insights(weather: night, at: evening).isEmpty)
    }

    @Test
    func uvWithoutALocationFallsBackToTheRestOfTheCalendarDay() throws {
        let sameDay = weather(uv: 0, slots: [slot(hours: 2, uv: 8)])
        #expect(try #require(insights(weather: sameDay, hasLocation: false).first).kind == .uvIndex)

        let nextDay = weather(uv: 0, slots: [slot(hours: 12, uv: 8)])
        #expect(insights(weather: nextDay, hasLocation: false).isEmpty)
    }

    // MARK: - Air quality

    @Test
    func airQualityThresholdsFollowEuropeanAQIBands() throws {
        for aqi in [0, 20, 39, 40, 59] {
            #expect(insights(airQuality: airQuality(aqi: aqi)).isEmpty, "AQI \(aqi)")
        }

        let expectations: [(aqi: Int, severity: DashboardInsightSeverity)] = [
            (60, .caution), (79, .caution), (80, .attention), (100, .attention), (140, .attention)
        ]
        for (aqi, severity) in expectations {
            let insight = try #require(insights(airQuality: airQuality(aqi: aqi)).first)
            #expect(insight.kind == .airQuality)
            #expect(insight.severity == severity, "AQI \(aqi)")
            #expect(insight.menuBarText == "AQI \(aqi)")
            #expect(insight.relatedCard == .weather)
        }
    }

    @Test
    func veryPoorAirQualityIsAttention() throws {
        let insight = try #require(insights(airQuality: airQuality(aqi: 86, main: .pm2_5)).first)

        #expect(insight.severity == .attention)
        #expect(insight.symbolName == "aqi.high")
        #expect(insight.title == "Air quality very poor (AQI 86)")
        #expect(insight.detail == "Mostly PM2.5 \u{B7} limit time outdoors")
        #expect(insight.menuBarText == "AQI 86")
    }

    @Test
    func poorAirQualityIsCaution() throws {
        let insight = try #require(insights(airQuality: airQuality(aqi: 64, main: .pm10)).first)

        #expect(insight.severity == .caution)
        #expect(insight.symbolName == "aqi.medium")
        #expect(insight.title == "Air quality poor (AQI 64)")
        #expect(insight.detail == "Mostly PM10 \u{B7} consider shorter outdoor activity")
    }

    @Test
    func extremelyPoorAirQualityKeepsAttentionAndNamesTheBand() throws {
        let insight = try #require(insights(airQuality: airQuality(aqi: 120, main: .ozone)).first)
        #expect(insight.severity == .attention)
        #expect(insight.title == "Air quality extremely poor (AQI 120)")
        #expect(insight.detail == "Mostly ozone \u{B7} limit time outdoors")
    }

    @Test
    func airQualityWithoutAMainPollutantOmitsTheSource() throws {
        let insight = try #require(insights(airQuality: airQuality(aqi: 70, main: nil)).first)
        #expect(insight.detail == "Consider shorter outdoor activity")
    }

    @Test
    func airQualityForecastToReachPoorWarnsWhenItIsNotPoorNow() throws {
        let snapshot = airQuality(aqi: 30, slots: [
            aqiSlot(hours: 1, aqi: 35), aqiSlot(hours: 4, aqi: 62), aqiSlot(hours: 5, aqi: 72)
        ])
        let insight = try #require(insights(airQuality: snapshot).first)

        #expect(insight.severity == .caution)
        #expect(insight.symbolName == "aqi.medium")
        #expect(insight.title == "Air quality worsening from \(clock(hours: 4))")
        #expect(insight.detail == "Forecast AQI up to 72 \u{B7} now 30")
        #expect(insight.menuBarText == "AQI \u{2191}72")
        #expect(insight.relatedCard == .weather)
    }

    @Test
    func airQualityForecastIgnoresPastLateAndNonPoorSlots() {
        let belowPoor = airQuality(aqi: 30, slots: [aqiSlot(hours: 2, aqi: 59), aqiSlot(hours: 6, aqi: 55)])
        #expect(insights(airQuality: belowPoor).isEmpty)

        let past = airQuality(aqi: 30, slots: [aqiSlot(hours: -2, aqi: 90)])
        #expect(insights(airQuality: past).isEmpty)

        let tooLate = airQuality(aqi: 30, slots: [aqiSlot(hours: 13, aqi: 90)])
        #expect(insights(airQuality: tooLate).isEmpty)

        let atBoundary = airQuality(aqi: 30, slots: [aqiSlot(hours: 12, aqi: 90)])
        #expect(insights(airQuality: atBoundary).first?.kind == .airQuality)

        let missingValues = airQuality(aqi: 30, slots: [aqiSlot(hours: 2, aqi: nil)])
        #expect(insights(airQuality: missingValues).isEmpty)
    }

    @Test
    func currentPoorAirQualityWinsOverTheForecastWarning() {
        let snapshot = airQuality(aqi: 65, main: .pm10, slots: [aqiSlot(hours: 3, aqi: 90)])
        let all = insights(airQuality: snapshot)
        #expect(all.count == 1)
        #expect(all.first?.title == "Air quality poor (AQI 65)")
    }

    @Test
    func staleAirQualityProducesNothing() {
        let stale = airQuality(aqi: 90, fetchedAt: now.addingTimeInterval(-3 * 3_600))
        #expect(insights(airQuality: stale).isEmpty)
    }

    // MARK: - Ranking

    @Test
    func nomadRanksUVAndAirQualityRightAfterRain() {
        let snapshot = makeSnapshot(
            weather: weather(uv: 0, windKph: 45, rain: 0.8, slots: [slot(hours: 1, uv: 7)]), // wind caution, rain + UV info
            airQuality: airQuality(aqi: 90, main: .pm2_5), // attention
            deviceLocation: parisLocation
        )
        let nomad = DashboardInsightEngine.insights(for: snapshot, now: now, calendar: parisCalendar, limit: 20).map(\.kind)
        #expect(nomad == [.airQuality, .strongWind, .rainSoon, .uvIndex])

        let info = makeSnapshot(
            weather: weather(uv: 0, rain: 0.8, slots: [slot(hours: 1, uv: 7)]),
            deviceLocation: parisLocation
        )
        #expect(DashboardInsightEngine.insights(for: info, now: now, calendar: parisCalendar, limit: 20).map(\.kind) == [.rainSoon, .uvIndex])
    }

    @Test
    func roadTripRanksUVAndAirQualityRightAfterDaylight() throws {
        let sunset = try #require(parisSun.sunset)
        let evening = sunset.addingTimeInterval(-30 * 60) // daylight caution
        let snapshot = makeSnapshot(
            weather: weather(uv: 9, windKph: 45, fetchedAt: evening), // wind caution, UV caution
            airQuality: airQuality(aqi: 65, main: .pm10, fetchedAt: evening), // AQI caution
            deviceLocation: parisLocation
        )

        let kinds = DashboardInsightEngine
            .insights(for: snapshot, now: evening, calendar: parisCalendar, limit: 20, profile: .roadTrip)
            .map(\.kind)
        #expect(kinds == [.strongWind, .daylight, .uvIndex, .airQuality])
    }

    // MARK: - Fixtures

    private let now = Date(timeIntervalSince1970: 1_791_806_400) // 2026-10-12 12:00:00 UTC == 14:00 Paris

    private var parisCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }

    private var parisLocation: IPLocationSnapshot {
        IPLocationSnapshot(
            city: nil,
            region: nil,
            country: nil,
            countryCode: nil,
            latitude: 48.8566,
            longitude: 2.3522,
            timeZone: "Europe/Paris",
            provider: "test",
            fetchedAt: now
        )
    }

    private var parisSun: SolarDay {
        DaylightReference(latitude: 48.8566, longitude: 2.3522, timeZone: TimeZone(identifier: "Europe/Paris")!).solarDay(on: now)
    }

    private func clock(hours: Double) -> String {
        now.addingTimeInterval(hours * 3_600).formatted(
            Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: "en_GB"), timeZone: TimeZone(identifier: "Europe/Paris")!)
        )
    }

    private func insights(
        weather: WeatherSnapshot? = nil,
        airQuality: AirQualitySnapshot? = nil,
        hasLocation: Bool = true,
        at instant: Date? = nil
    ) -> [DashboardInsight] {
        // A location makes the sunset known; without one the engine falls back to the calendar day.
        DashboardInsightEngine.insights(
            for: makeSnapshot(weather: weather, airQuality: airQuality, deviceLocation: hasLocation ? parisLocation : nil),
            now: instant ?? now,
            calendar: parisCalendar,
            limit: 20
        )
    }

    private func weather(
        uv: Int?,
        windKph: Double? = nil,
        rain: Double? = nil,
        slots: [WeatherHourlyForecastSlot] = [],
        fetchedAt: Date? = nil
    ) -> WeatherSnapshot {
        WeatherSnapshot(
            currentTemperatureCelsius: 24,
            apparentTemperatureCelsius: 25,
            conditionDescription: "Clear",
            symbolName: "sun.max.fill",
            precipitationChance: rain,
            windSpeedKph: windKph,
            windDirectionDegrees: 270,
            uvIndex: uv,
            hourlyForecastSlots: slots,
            fetchedAt: fetchedAt ?? now
        )
    }

    private func slot(hours: Double, uv: Int?) -> WeatherHourlyForecastSlot {
        WeatherHourlyForecastSlot(
            date: now.addingTimeInterval(hours * 3_600),
            symbolName: "sun.max.fill",
            conditionDescription: "Clear",
            temperatureCelsius: 24,
            precipitationChance: nil,
            windSpeedKph: nil,
            windDirectionDegrees: nil,
            uvIndex: uv
        )
    }

    private func airQuality(
        aqi: Int,
        main: AirQualityPollutant? = .pm2_5,
        slots: [AirQualityForecastSlot] = [],
        fetchedAt: Date? = nil
    ) -> AirQualitySnapshot {
        AirQualitySnapshot(
            latitude: 48.9,
            longitude: 2.4,
            sourceName: "Open-Meteo",
            europeanAQI: aqi,
            mainPollutant: main,
            pm2_5: 20,
            pm10: 30,
            ozone: 50,
            nitrogenDioxide: 15,
            forecastSlots: slots,
            fetchedAt: fetchedAt ?? now
        )
    }

    private func aqiSlot(hours: Double, aqi: Int?) -> AirQualityForecastSlot {
        AirQualityForecastSlot(date: now.addingTimeInterval(hours * 3_600), europeanAQI: aqi)
    }

    private func makeSnapshot(
        weather: WeatherSnapshot? = nil,
        airQuality: AirQualitySnapshot? = nil,
        deviceLocation: IPLocationSnapshot? = nil
    ) -> DashboardSnapshot {
        DashboardSnapshot(
            network: NetworkSectionSnapshot(
                throughput: nil,
                connectivity: .checking,
                latency: nil,
                downloadHistory: [],
                uploadHistory: [],
                latencyHistory: []
            ),
            power: PowerSectionSnapshot(snapshot: nil, chargeHistory: [], dischargeHistory: []),
            travelContext: TravelContextSnapshot(
                wifi: nil,
                vpn: nil,
                timeZoneIdentifier: "Europe/Paris",
                deviceLocation: deviceLocation,
                publicIP: nil,
                location: nil
            ),
            weather: weather,
            airQuality: airQuality,
            appState: AppStatusSnapshot(lastRefresh: nil, updateState: .idle, issues: [])
        )
    }
}
