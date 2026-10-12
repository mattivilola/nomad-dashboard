import Foundation
import Testing
@testable import NomadCore

struct DashboardInsightEngineTests {
    // MARK: - General

    @Test
    func emptySnapshotProducesNoInsights() {
        #expect(DashboardInsightEngine.insights(for: .placeholder, now: now, calendar: parisCalendar).isEmpty)
    }

    @Test
    func insightsCoverOnlyNonHealthCards() {
        let snapshot = makeSnapshot(
            metered: makeMetered(usedBytes: 2_000, capBytes: 1_000),
            alerts: makeAlerts([(.advisory, .warning)]),
            weather: makeWeather(windKph: 70, slots: [slot(hours: 1, rain: 0.9)]),
            localInfo: makeLocalInfo(currentPeriod: holiday(dayOffset: 0)),
            fuel: makeFuel(diesel: station(.diesel))
        )

        let all = DashboardInsightEngine.insights(for: snapshot, now: now, calendar: parisCalendar, limit: 20)

        let cards = Set(all.map(\.relatedCard))
        #expect(cards.isSubset(of: [.meteredData, .travelAlerts, .weather, .localInfo, .fuelPrices]))
        #expect(all.count == Set(all.map(\.kind)).count)
    }

    @Test
    func sortsBySeverityThenKindOrderAndHonorsLimit() {
        let snapshot = makeSnapshot(
            metered: makeMetered(usedBytes: 850, capBytes: 1_000), // dataCap caution
            alerts: makeAlerts([(.advisory, .caution), (.security, .critical)]), // advisory caution, security attention
            weather: makeWeather(windKph: 45, slots: [slot(hours: 2, rain: 0.8)]), // wind caution, rain info
            localInfo: makeLocalInfo(currentPeriod: holiday(dayOffset: 0)), // holiday caution
            fuel: makeFuel(diesel: station(.diesel)) // fuel info
        )

        let all = DashboardInsightEngine.insights(for: snapshot, now: now, calendar: parisCalendar, limit: 20)

        #expect(all.map(\.kind) == [
            .regionalSecurity,
            .dataCap,
            .travelAdvisory,
            .strongWind,
            .publicHoliday,
            .rainSoon,
            .fuelNearby
        ])

        let limited = DashboardInsightEngine.insights(for: snapshot, now: now, calendar: parisCalendar)
        #expect(limited.map(\.kind) == [.regionalSecurity, .dataCap, .travelAdvisory])

        #expect(DashboardInsightEngine.insights(for: snapshot, now: now, calendar: parisCalendar, limit: 1).count == 1)
        #expect(DashboardInsightEngine.insights(for: snapshot, now: now, calendar: parisCalendar, limit: 0).isEmpty)
    }

    @Test
    func roadTripProfileRanksTheSameInsightsDifferently() {
        let snapshot = makeSnapshot(
            metered: makeMetered(usedBytes: 850, capBytes: 1_000), // dataCap caution
            alerts: makeAlerts([(.advisory, .caution), (.weather, .caution), (.security, .critical)]), // advisory + weather caution, security attention
            weather: makeWeather(windKph: 45, slots: [slot(hours: 2, rain: 0.8)]), // wind caution, rain info
            localInfo: makeLocalInfo(currentPeriod: holiday(dayOffset: 0)), // holiday caution
            fuel: makeFuel(diesel: station(.diesel)) // fuel info
        )

        func kinds(_ profile: TravelProfile) -> [DashboardInsightKind] {
            DashboardInsightEngine.insights(for: snapshot, now: now, calendar: parisCalendar, limit: 20, profile: profile).map(\.kind)
        }

        #expect(kinds(.nomad) == [
            .regionalSecurity,
            .dataCap,
            .travelAdvisory,
            .weatherAlert,
            .strongWind,
            .publicHoliday,
            .rainSoon,
            .fuelNearby
        ])
        #expect(kinds(.roadTrip) == [
            .regionalSecurity,
            .strongWind,
            .weatherAlert,
            .dataCap,
            .travelAdvisory,
            .publicHoliday,
            .fuelNearby,
            .rainSoon
        ])
        #expect(DashboardInsightEngine.insights(for: snapshot, now: now, calendar: parisCalendar, profile: .roadTrip).count == 3)
    }

    @Test
    func severityStaysPrimaryForRoadTripProfile() {
        let snapshot = makeSnapshot(
            metered: makeMetered(usedBytes: 2_000, capBytes: 1_000), // dataCap attention
            weather: makeWeather(windKph: 45), // wind caution
            fuel: makeFuel(diesel: station(.diesel)) // fuel info
        )

        let kinds = DashboardInsightEngine.insights(for: snapshot, now: now, calendar: parisCalendar, limit: 20, profile: .roadTrip).map(\.kind)
        #expect(kinds == [.dataCap, .strongWind, .fuelNearby])
    }

    @Test
    func tieBreakOrderCoversEveryKindForEveryProfile() {
        for profile in TravelProfile.allCases {
            let order = DashboardInsightKind.tieBreakOrder(for: profile)
            #expect(Set(order) == Set(DashboardInsightKind.allCases))
            #expect(order.count == DashboardInsightKind.allCases.count)
        }
        #expect(DashboardInsightKind.tieBreakOrder(for: .nomad) == DashboardInsightKind.allCases)
        #expect(DashboardInsightKind.allCases.last == .daylight)

        let roadTrip = DashboardInsightKind.tieBreakOrder(for: .roadTrip)
        let wind = roadTrip.firstIndex(of: .strongWind)
        #expect(roadTrip.firstIndex(of: .daylight) == wind.map { $0 + 1 })

        // UV and air quality follow the rain heads-up for nomads and the daylight heads-up for road trips.
        let nomadOrder = DashboardInsightKind.tieBreakOrder(for: .nomad)
        let rain = nomadOrder.firstIndex(of: .rainSoon)
        #expect(Array(nomadOrder[(rain ?? 0) + 1...(rain ?? 0) + 2]) == [.uvIndex, .airQuality])
        let daylight = roadTrip.firstIndex(of: .daylight)
        #expect(Array(roadTrip[(daylight ?? 0) + 1...(daylight ?? 0) + 2]) == [.uvIndex, .airQuality])

        // The stay insights follow the data cap in both profiles.
        for order in [DashboardInsightKind.tieBreakOrder(for: .nomad), roadTrip] {
            let dataCap = order.firstIndex(of: .dataCap)
            #expect(Array(order[(dataCap ?? 0) + 1...(dataCap ?? 0) + 3]) == [.stayAllowance, .schengenLimit, .taxResidenceDays])
        }

        // The local-rhythm heads-up follows the public holiday in both profiles.
        for order in [DashboardInsightKind.tieBreakOrder(for: .nomad), roadTrip] {
            #expect(order.firstIndex(of: .localRhythm) == order.firstIndex(of: .publicHoliday).map { $0 + 1 })
        }
    }

    @Test
    func everyInsightCarriesCompactMenuBarText() throws {
        let snapshot = makeSnapshot(
            metered: makeMetered(usedBytes: 850, capBytes: 1_000),
            alerts: makeAlerts([(.advisory, .caution), (.weather, .caution), (.security, .caution)]),
            weather: makeWeather(windKph: 45, slots: [slot(hours: 2, rain: 0.8)], uvIndex: 9),
            localInfo: makeLocalInfo(currentPeriod: holiday(dayOffset: 0)),
            fuel: makeFuel(diesel: station(.diesel)),
            deviceLocation: parisLocation,
            airQuality: makeAirQuality(aqi: 86)
        )

        // Daylight only fires for the road trip profile, and only near sunset or in the dark.
        // Morocco: 12 of 90 days left, Schengen: 10 of 90 left (80 days in France), Spain: 160 days this year.
        let stayDays = (0..<80).map { offset -> VisitedCountryDay in
            let date = parisCalendar.date(byAdding: .day, value: -offset, to: now)!
            let stamp = VisitedCountryDayStamp(date: date, calendar: parisCalendar)
            return VisitedCountryDay(day: stamp, country: "France", countryCode: "FR", source: .deviceLocation, isInferred: false)
        }
        let stayInput = StayInsightInput(
            countryDays: stayDays,
            settings: AppSettings(citizenshipCountryCodes: ["US"], stayAllowances: ["FR": 92], taxResidenceThresholdDays: 90),
            currentCountryCode: "FR"
        )
        let nomad = DashboardInsightEngine.insights(for: snapshot, now: now, calendar: parisCalendar, limit: 20, stays: stayInput)
        #expect(Set(nomad.map(\.kind)) == Set(DashboardInsightKind.allCases).subtracting([.daylight, .localRhythm]))
        // Same severity ranks by tie-break order: the data cap, then the stay insights, then the advisory.
        let cautionKinds = nomad.filter { $0.severity == .caution }.map(\.kind)
        #expect(cautionKinds.prefix(3) == [.dataCap, .stayAllowance, .schengenLimit])

        let sunset = try #require(parisSun.sunset)
        let evening = DashboardInsightEngine.insights(
            for: snapshot, now: sunset.addingTimeInterval(-30 * 60), calendar: parisCalendar, limit: 20, profile: .roadTrip,
            stays: stayInput
        )
        let dark = DashboardInsightEngine.insights(
            for: snapshot, now: sunset.addingTimeInterval(3 * 3_600), calendar: parisCalendar, limit: 20, profile: .roadTrip,
            stays: stayInput
        )
        #expect(evening.contains { $0.kind == .daylight })
        #expect(dark.contains { $0.kind == .daylight })
        // The local-rhythm heads-up needs a country with a period around the date, which 2026-10-12 has none for.
        let rhythm = DashboardInsightEngine.insights(
            for: makeSnapshot(deviceLocation: rhythmLocation("CN")),
            now: date(2027, 1, 30, 12, 0), calendar: parisCalendar, limit: 20
        )
        #expect(rhythm.map(\.kind) == [.localRhythm])
        #expect((nomad + evening + dark + rhythm).allSatisfy { $0.menuBarText.isEmpty == false && $0.menuBarText.count <= 13 })
    }

    @Test
    func severityIsComparable() {
        #expect(DashboardInsightSeverity.info < .caution)
        #expect(DashboardInsightSeverity.caution < .attention)
    }

    // MARK: - Data cap

    @Test
    func dataCapBelowThresholdProducesNothing() {
        let snapshot = makeSnapshot(metered: makeMetered(usedBytes: 799, capBytes: 1_000))
        #expect(insights(snapshot).isEmpty)
    }

    @Test
    func dataCapAtEightyPercentIsCaution() throws {
        let snapshot = makeSnapshot(metered: makeMetered(usedBytes: 850_000_000, capBytes: 1_000_000_000))
        let insight = try #require(insights(snapshot).first)

        #expect(insight.kind == .dataCap)
        #expect(insight.severity == .caution)
        #expect(insight.title == "Data cap at 85%")
        #expect(insight.menuBarText == "Cap 85%")
        #expect(insight.detail == "\(MeteredUsageFormatting.byteCount(850_000_000)) of \(MeteredUsageFormatting.byteCount(1_000_000_000)) used")
        #expect(insight.relatedCard == .meteredData)

        let boundary = makeSnapshot(metered: makeMetered(usedBytes: 800, capBytes: 1_000))
        #expect(insights(boundary).first?.title == "Data cap at 80%")
    }

    @Test
    func dataCapReachedIsAttentionWithPausedDownloads() throws {
        let snapshot = makeSnapshot(metered: makeMetered(usedBytes: 1_200_000_000, capBytes: 1_000_000_000))
        let insight = try #require(insights(snapshot).first)

        #expect(insight.severity == .attention)
        #expect(insight.title == "Data cap reached")
        #expect(insight.menuBarText == "Cap reached")
        #expect(insight.detail?.hasSuffix("· downloads paused") == true)

        let exact = makeSnapshot(metered: makeMetered(usedBytes: 1_000, capBytes: 1_000))
        #expect(insights(exact).first?.severity == .attention)
    }

    @Test
    func dataCapRequiresEnabledActiveMonitoringAndCap() {
        let disabled = makeSnapshot(metered: makeMetered(isEnabled: false, usedBytes: 2_000, capBytes: 1_000))
        let inactive = makeSnapshot(metered: makeMetered(isActive: false, usedBytes: 2_000, capBytes: 1_000))
        let noCap = makeSnapshot(metered: makeMetered(usedBytes: 2_000, capBytes: nil))
        let zeroCap = makeSnapshot(metered: makeMetered(usedBytes: 2_000, capBytes: 0))

        #expect(insights(disabled).isEmpty)
        #expect(insights(inactive).isEmpty)
        #expect(insights(noCap).isEmpty)
        #expect(insights(zeroCap).isEmpty)
    }

    @Test
    func dataCapUsesSessionBytesForSessionPeriodAndPeriodBytesOtherwise() {
        let session = makeSnapshot(metered: makeMetered(usedBytes: 900, capBytes: 1_000, period: .session, otherBytes: 0))
        let month = makeSnapshot(metered: makeMetered(usedBytes: 900, capBytes: 1_000, period: .calendarMonth, otherBytes: 0))

        #expect(insights(session).first?.title == "Data cap at 90%")
        #expect(insights(month).first?.title == "Data cap at 90%")
    }

    // MARK: - Travel alerts

    @Test
    func travelAlertSeverityMapping() {
        func severities(for severity: TravelAlertSeverity) -> [DashboardInsightSeverity] {
            insights(makeSnapshot(alerts: makeAlerts([(.advisory, severity)]))).map(\.severity)
        }

        #expect(severities(for: .clear).isEmpty)
        #expect(severities(for: .info).isEmpty)
        #expect(severities(for: .caution) == [.caution])
        #expect(severities(for: .warning) == [.attention])
        #expect(severities(for: .critical) == [.attention])
    }

    @Test
    func advisoryUsesSummaryAsTitle() throws {
        let snapshot = makeSnapshot(alerts: makeAlerts([(.advisory, .caution)]))
        let insight = try #require(insights(snapshot).first)

        #expect(insight.kind == .travelAdvisory)
        #expect(insight.title == "France: exercise a high degree of caution")
        #expect(insight.menuBarText == "Advisory")
        #expect(insight.detail == "Source: Smartraveller")
        #expect(insight.relatedCard == .travelAlerts)
    }

    @Test
    func weatherAlertAndSecurityTitles() throws {
        let snapshot = makeSnapshot(alerts: makeAlerts([(.weather, .warning), (.security, .caution)], weatherItemCount: 3))
        let all = insights(snapshot)

        let weather = try #require(all.first { $0.kind == .weatherAlert })
        #expect(weather.severity == .attention)
        #expect(weather.title == "3 weather alerts active")
        #expect(weather.menuBarText == "Weather alert")
        #expect((weather.detail?.count ?? 0) <= 44)

        let security = try #require(all.first { $0.kind == .regionalSecurity })
        #expect(security.severity == .caution)
        #expect(security.title == "Regional security watch")
        #expect(security.menuBarText == "Security")

        let single = makeSnapshot(alerts: makeAlerts([(.weather, .caution)], weatherItemCount: 1))
        #expect(insights(single).first?.title == "Weather alert active")
        let severe = makeSnapshot(alerts: makeAlerts([(.weather, .critical)], weatherItemCount: 1))
        #expect(insights(severe).first?.title == "Severe weather alert")
    }

    @Test
    func travelAlertsSkipNonReadyAndDisabledSignals() {
        let stale = makeAlerts([(.advisory, .critical)], status: .stale)
        let unavailable = makeAlerts([(.advisory, .critical)], status: .unavailable)
        let checking = makeAlerts([(.advisory, .critical)], status: .checking)
        let disabled = makeAlerts([(.advisory, .critical)], enabledKinds: [.weather])

        #expect(insights(makeSnapshot(alerts: stale)).isEmpty)
        #expect(insights(makeSnapshot(alerts: unavailable)).isEmpty)
        #expect(insights(makeSnapshot(alerts: checking)).isEmpty)
        #expect(insights(makeSnapshot(alerts: disabled)).isEmpty)
    }

    @Test
    func travelAlertsProduceOneInsightPerSignalType() {
        let snapshot = makeSnapshot(alerts: makeAlerts([(.advisory, .warning), (.weather, .caution), (.security, .warning)]))
        let kinds = insights(snapshot).map(\.kind)

        #expect(kinds == [.travelAdvisory, .regionalSecurity, .weatherAlert])
    }

    // MARK: - Strong wind

    @Test
    func windThresholds() {
        #expect(insights(makeSnapshot(weather: makeWeather(windKph: 39.9))).isEmpty)
        #expect(insights(makeSnapshot(weather: makeWeather(windKph: 40))).first?.severity == .caution)
        #expect(insights(makeSnapshot(weather: makeWeather(windKph: 59.9))).first?.severity == .caution)
        #expect(insights(makeSnapshot(weather: makeWeather(windKph: 60))).first?.severity == .attention)
    }

    @Test
    func windFromCurrentReadingSaysNow() throws {
        let weather = makeWeather(windKph: 45, windDegrees: 270)
        let insight = try #require(insights(makeSnapshot(weather: weather)).first)

        #expect(insight.kind == .strongWind)
        #expect(insight.title == "Wind up to 45 km/h")
        #expect(insight.menuBarText == "Wind 45")
        #expect(insight.detail == "From W now")
        #expect(insight.relatedCard == .weather)
    }

    @Test
    func windWithoutDirectionOmitsCompass() throws {
        let weather = makeWeather(windKph: 45, windDegrees: nil)
        #expect(try #require(insights(makeSnapshot(weather: weather)).first).detail == "Now")
    }

    @Test
    func windPeakInUpcomingSlotUsesSlotTimeAndDirection() throws {
        let weather = makeWeather(
            windKph: 20,
            windDegrees: 90,
            slots: [
                slot(hours: 1, windKph: 30, windDegrees: 0),
                slot(hours: 2, windKph: 64.4, windDegrees: 225),
                slot(hours: 3, windKph: 50, windDegrees: 270)
            ]
        )
        let insight = try #require(insights(makeSnapshot(weather: weather)).first)

        #expect(insight.severity == .attention)
        #expect(insight.title == "Wind up to 64 km/h")
        #expect(insight.detail == "From SW around 16:00")
    }

    @Test
    func windTieKeepsEarliestReading() throws {
        let weather = makeWeather(windKph: 50, windDegrees: 0, slots: [slot(hours: 2, windKph: 50, windDegrees: 180)])
        #expect(try #require(insights(makeSnapshot(weather: weather)).first).detail == "From N now")
    }

    @Test
    func windIgnoresPastAndBeyondSixHourSlots() {
        let weather = makeWeather(
            windKph: 10,
            slots: [
                slot(hours: -1, windKph: 90),
                slot(hours: 6.5, windKph: 90),
                slot(hours: 12, windKph: 90)
            ]
        )
        #expect(insights(makeSnapshot(weather: weather)).isEmpty)
    }

    @Test
    func windIncludesSlotExactlyAtSixHourBoundary() throws {
        let weather = makeWeather(windKph: 10, slots: [slot(hours: 6, windKph: 55, windDegrees: 0)])
        let insight = try #require(insights(makeSnapshot(weather: weather)).first)

        #expect(insight.detail == "From N around 20:00")
    }

    @Test
    func windCompassDirections() {
        func detail(_ degrees: Double) -> String? {
            insights(makeSnapshot(weather: makeWeather(windKph: 50, windDegrees: degrees))).first?.detail
        }

        #expect(detail(0) == "From N now")
        #expect(detail(359) == "From N now")
        #expect(detail(45) == "From NE now")
        #expect(detail(90) == "From E now")
        #expect(detail(135) == "From SE now")
        #expect(detail(180) == "From S now")
        #expect(detail(225) == "From SW now")
        #expect(detail(300) == "From NW now")
        #expect(detail(-90) == "From W now")
    }

    @Test
    func staleCurrentWindReadingIsIgnoredButForecastStillCounts() throws {
        let staleFetch = now.addingTimeInterval(-3 * 3_600)
        let onlyStale = makeWeather(windKph: 80, fetchedAt: staleFetch)
        #expect(insights(makeSnapshot(weather: onlyStale)).isEmpty)

        let withForecast = makeWeather(windKph: 80, slots: [slot(hours: 1, windKph: 42, windDegrees: 90)], fetchedAt: staleFetch)
        let insight = try #require(insights(makeSnapshot(weather: withForecast)).first)
        #expect(insight.title == "Wind up to 42 km/h")
    }

    // MARK: - Rain

    @Test
    func rainBelowThresholdProducesNothing() {
        let weather = makeWeather(rain: 0.59, slots: [slot(hours: 1, rain: 0.59)])
        #expect(insights(makeSnapshot(weather: weather)).isEmpty)
    }

    @Test
    func rainFromCurrentReadingSaysNow() throws {
        let weather = makeWeather(rain: 0.72, slots: [slot(hours: 1, rain: 0.9)])
        let insight = try #require(insights(makeSnapshot(weather: weather)).first)

        #expect(insight.kind == .rainSoon)
        #expect(insight.severity == .info)
        #expect(insight.title == "Rain likely now")
        #expect(insight.menuBarText == "Rain now")
        #expect(insight.detail == "72% chance")
        #expect(insight.relatedCard == .weather)
    }

    @Test
    func rainFromFirstQualifyingUpcomingSlot() throws {
        let weather = makeWeather(
            rain: 0.1,
            slots: [
                slot(hours: 1, rain: 0.3),
                slot(hours: 2, rain: 0.6),
                slot(hours: 3, rain: 0.95)
            ]
        )
        let insight = try #require(insights(makeSnapshot(weather: weather)).first)

        #expect(insight.title == "Rain likely from 16:00")
        #expect(insight.menuBarText == "Rain 16:00")
        #expect(insight.detail == "60% chance")
    }

    @Test
    func rainSlotCoveringNowCountsAsNow() throws {
        let weather = makeWeather(rain: nil, slots: [slot(minutes: -30, rain: 0.8), slot(hours: 1, rain: 0.3)])
        let insight = try #require(insights(makeSnapshot(weather: weather)).first)

        #expect(insight.title == "Rain likely now")
        #expect(insight.detail == "80% chance")
    }

    @Test
    func rainIgnoresPastAndBeyondSixHourSlots() {
        let weather = makeWeather(
            rain: 0.1,
            slots: [
                slot(hours: -2, rain: 0.95),
                slot(hours: 6.5, rain: 0.95),
                slot(hours: 9, rain: 0.95)
            ]
        )
        #expect(insights(makeSnapshot(weather: weather)).isEmpty)
    }

    @Test
    func rainAndWindCanBothAppearIndependently() {
        let weather = makeWeather(windKph: 45, rain: 0.8)
        let kinds = insights(makeSnapshot(weather: weather)).map(\.kind)

        #expect(kinds == [.strongWind, .rainSoon])
    }

    // MARK: - Public holiday

    @Test
    func holidayToday() throws {
        let snapshot = makeSnapshot(localInfo: makeLocalInfo(currentPeriod: holiday(dayOffset: 0, name: "Armistice")))
        let insight = try #require(insights(snapshot).first)

        #expect(insight.kind == .publicHoliday)
        #expect(insight.severity == .caution)
        #expect(insight.title == "Public holiday today")
        #expect(insight.menuBarText == "Holiday today")
        #expect(insight.detail == "Armistice · shops may close")
        #expect(insight.relatedCard == .localInfo)
    }

    @Test
    func holidayTomorrowAndWeekdayNames() throws {
        let tomorrow = makeSnapshot(localInfo: makeLocalInfo(nextPeriod: holiday(dayOffset: 1, name: "Armistice")))
        let tomorrowInsight = try #require(insights(tomorrow).first)
        #expect(tomorrowInsight.severity == .info)
        #expect(tomorrowInsight.title == "Public holiday tomorrow")
        #expect(tomorrowInsight.menuBarText == "Holiday")
        #expect(tomorrowInsight.detail == "Armistice")

        // 2026-10-12 is a Monday.
        let inTwo = makeSnapshot(localInfo: makeLocalInfo(nextPeriod: holiday(dayOffset: 2)))
        #expect(insights(inTwo).first?.title == "Public holiday Wednesday")
        let inThree = makeSnapshot(localInfo: makeLocalInfo(nextPeriod: holiday(dayOffset: 3)))
        #expect(insights(inThree).first?.title == "Public holiday Thursday")
        #expect(insights(inThree).first?.severity == .info)
    }

    @Test
    func holidayFurtherOutOrPastProducesNothing() {
        let far = makeSnapshot(localInfo: makeLocalInfo(nextPeriod: holiday(dayOffset: 4)))
        let past = makeSnapshot(localInfo: makeLocalInfo(nextPeriod: holiday(dayOffset: -1)))
        let none = makeSnapshot(localInfo: makeLocalInfo())

        #expect(insights(far).isEmpty)
        #expect(insights(past).isEmpty)
        #expect(insights(none).isEmpty)
    }

    @Test
    func holidayDayBoundariesUseInjectedCalendar() throws {
        let holidayDay = holiday(dayOffset: 0)
        let snapshot = makeSnapshot(localInfo: makeLocalInfo(currentPeriod: holidayDay))

        // 00:30 and 23:30 Paris time on the holiday are both "today".
        let earlyMorning = date(2026, 10, 12, 0, 30)
        let lateEvening = date(2026, 10, 12, 23, 30)
        #expect(try #require(DashboardInsightEngine.insights(for: snapshot, now: earlyMorning, calendar: parisCalendar).first).title == "Public holiday today")
        #expect(try #require(DashboardInsightEngine.insights(for: snapshot, now: lateEvening, calendar: parisCalendar).first).title == "Public holiday today")

        // 23:30 the evening before the holiday is "tomorrow" in Paris.
        let eveningBefore = date(2026, 10, 11, 23, 30)
        #expect(try #require(DashboardInsightEngine.insights(for: snapshot, now: eveningBefore, calendar: parisCalendar).first).title == "Public holiday tomorrow")

        // The holiday period starts at Paris midnight, which is the previous afternoon in Los Angeles, so a
        // Los Angeles calendar sees the same instants on a different civil day. The injected calendar decides.
        var losAngeles = parisCalendar
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let laInsight = try #require(DashboardInsightEngine.insights(for: snapshot, now: earlyMorning, calendar: losAngeles).first)
        #expect(laInsight.title == "Public holiday today")
    }

    @Test
    func holidayPrefersCurrentOverLaterNextAndStaleStateIsRecomputed() throws {
        // Stored state says "tomorrow", but the period is actually today relative to `now`.
        let status = LocalHolidayStatus(state: .tomorrow, currentPeriod: nil, nextPeriod: holiday(dayOffset: 0), note: nil)
        let info = makeLocalInfo(status: status)
        let insight = try #require(insights(makeSnapshot(localInfo: info)).first)

        #expect(insight.title == "Public holiday today")

        let both = makeLocalInfo(currentPeriod: holiday(dayOffset: 0, name: "Today"), nextPeriod: holiday(dayOffset: 2, name: "Later"))
        #expect(insights(makeSnapshot(localInfo: both)).first?.title == "Public holiday today")
    }

    @Test
    func multiDayCurrentPeriodCountsAsToday() {
        let period = HolidayPeriodSnapshot(name: "Long weekend", startDate: date(2026, 10, 10, 0, 0), endDate: date(2026, 10, 13, 0, 0))
        let snapshot = makeSnapshot(localInfo: makeLocalInfo(currentPeriod: period))

        #expect(insights(snapshot).first?.title == "Public holiday today")
    }

    // MARK: - Fuel

    @Test
    func fuelInsightFormatsPriceDistanceAndRadius() throws {
        let snapshot = makeSnapshot(fuel: makeFuel(diesel: station(.diesel, price: 1.689, distance: 2.4), radius: 50))
        let insight = try #require(insights(snapshot).first)

        #expect(insight.kind == .fuelNearby)
        #expect(insight.severity == .info)
        #expect(insight.title == "Diesel €1.689 · 2.4 km")
        #expect(insight.menuBarText == "€1.689")
        #expect(insight.detail == "Cheapest within 50 km")
        #expect(insight.relatedCard == .fuelPrices)
        #expect(insight.symbolName == "fuelpump.fill")
    }

    @Test
    func fuelDistanceRoundsAtTenKilometers() {
        let snapshot = makeSnapshot(fuel: makeFuel(diesel: station(.diesel, price: 1.5, distance: 12.4)))
        #expect(insights(snapshot).first?.title.hasSuffix("· 12 km") == true)
    }

    @Test
    func fuelPrefersDieselThenGasoline() {
        let both = makeSnapshot(fuel: makeFuel(diesel: station(.diesel), gasoline: station(.gasoline)))
        let gasolineOnly = makeSnapshot(fuel: makeFuel(gasoline: station(.gasoline)))

        #expect(insights(both).first?.title.hasPrefix("Diesel") == true)
        #expect(insights(gasolineOnly).first?.title.hasPrefix("Gasoline") == true)
    }

    @Test
    func fuelRequiresReadyStatusAndAStation() {
        let notReady = makeSnapshot(fuel: makeFuel(status: .unavailable, diesel: station(.diesel)))
        let empty = makeSnapshot(fuel: makeFuel())

        #expect(insights(notReady).isEmpty)
        #expect(insights(empty).isEmpty)
    }

    // MARK: - Daylight

    @Test
    func daylightIsRoadTripOnly() throws {
        let sunset = try #require(parisSun.sunset)
        let snapshot = makeSnapshot(deviceLocation: parisLocation)
        let nearSunset = sunset.addingTimeInterval(-30 * 60)

        #expect(roadTripInsights(snapshot, at: nearSunset).map(\.kind) == [.daylight])
        #expect(DashboardInsightEngine.insights(for: snapshot, now: nearSunset, calendar: parisCalendar).isEmpty)
        #expect(DashboardInsightEngine.insights(for: snapshot, now: nearSunset, calendar: parisCalendar, profile: .nomad).isEmpty)
    }

    @Test
    func daylightWithinAnHourBeforeSunsetIsCaution() throws {
        let sunset = try #require(parisSun.sunset)
        let dusk = try #require(parisSun.civilDusk)
        let insight = try #require(roadTripInsights(makeSnapshot(deviceLocation: parisLocation), at: sunset.addingTimeInterval(-45 * 60)).first)

        #expect(insight.kind == .daylight)
        #expect(insight.severity == .caution)
        #expect(insight.symbolName == "sunset")
        #expect(insight.title == "Sunset \(clock(sunset)) \u{B7} 45 min of daylight")
        #expect(insight.menuBarText == "Sunset \(clock(sunset))")
        #expect(insight.detail == "Dusk (civil twilight) ends \(clock(dusk))")
        #expect(insight.relatedCard == .weather)

        let boundary = try #require(roadTripInsights(makeSnapshot(deviceLocation: parisLocation), at: sunset.addingTimeInterval(-3_600)).first)
        #expect(boundary.severity == .caution)
        #expect(boundary.title.hasSuffix("1 h of daylight"))
    }

    @Test
    func daylightWithinTwoHoursBeforeSunsetIsInfoWithHoursAndMinutes() throws {
        let sunset = try #require(parisSun.sunset)
        let snapshot = makeSnapshot(deviceLocation: parisLocation)

        let insight = try #require(roadTripInsights(snapshot, at: sunset.addingTimeInterval(-110 * 60)).first)
        #expect(insight.severity == .info)
        #expect(insight.title == "Sunset \(clock(sunset)) \u{B7} 1 h 50 min of daylight")
        #expect(insight.menuBarText == "Sunset \(clock(sunset))")

        let twoHours = try #require(roadTripInsights(snapshot, at: sunset.addingTimeInterval(-7_200)).first)
        #expect(twoHours.severity == .info)
        #expect(twoHours.title.hasSuffix("2 h of daylight"))

        #expect(roadTripInsights(snapshot, at: sunset.addingTimeInterval(-7_201)).isEmpty)
        #expect(roadTripInsights(snapshot, at: sunset.addingTimeInterval(-6 * 3_600)).isEmpty)
    }

    @Test
    func daylightDarkAfterCivilDuskPlusGraceNamesTomorrowsSunrise() throws {
        let dusk = try #require(parisSun.civilDusk)
        let tomorrowSunrise = try #require(parisSolarDay(offsetDays: 1).sunrise)
        let snapshot = makeSnapshot(deviceLocation: parisLocation)

        let insight = try #require(roadTripInsights(snapshot, at: dusk.addingTimeInterval(30 * 60)).first)
        #expect(insight.kind == .daylight)
        #expect(insight.severity == .info)
        #expect(insight.symbolName == "moon.stars")
        #expect(insight.title == "Dark until \(clock(tomorrowSunrise))")
        #expect(insight.menuBarText == "Dark")
        #expect(insight.detail == "Sunrise tomorrow \(clock(tomorrowSunrise))")
        #expect(insight.relatedCard == .weather)
    }

    @Test
    func daylightBetweenSunsetAndTheDarkGraceProducesNothing() throws {
        let sunset = try #require(parisSun.sunset)
        let dusk = try #require(parisSun.civilDusk)
        let snapshot = makeSnapshot(deviceLocation: parisLocation)

        #expect(roadTripInsights(snapshot, at: sunset.addingTimeInterval(1)).isEmpty)
        #expect(roadTripInsights(snapshot, at: dusk).isEmpty)
        #expect(roadTripInsights(snapshot, at: dusk.addingTimeInterval(30 * 60 - 1)).isEmpty)
    }

    @Test
    func daylightStaysDarkAfterMidnightUntilTodaysSunrise() throws {
        let sunrise = try #require(parisSun.sunrise)
        let snapshot = makeSnapshot(deviceLocation: parisLocation)
        let afterMidnight = date(2026, 10, 12, 1, 30)

        let insight = try #require(roadTripInsights(snapshot, at: afterMidnight).first)
        #expect(insight.title == "Dark until \(clock(sunrise))")
        #expect(insight.detail == "Sunrise today \(clock(sunrise))")

        #expect(roadTripInsights(snapshot, at: sunrise.addingTimeInterval(-60)).first?.kind == .daylight)
        #expect(roadTripInsights(snapshot, at: sunrise.addingTimeInterval(60)).isEmpty)
    }

    @Test
    func daylightMiddayProducesNothing() {
        #expect(roadTripInsights(makeSnapshot(deviceLocation: parisLocation), at: now).isEmpty)
    }

    @Test
    func daylightNeedsCoordinatesAndUsesDeviceThenIPLocation() throws {
        let sunset = try #require(parisSun.sunset)
        let evening = sunset.addingTimeInterval(-30 * 60)

        #expect(roadTripInsights(makeSnapshot(), at: evening).isEmpty)
        #expect(roadTripInsights(makeSnapshot(deviceLocation: location(latitude: nil, longitude: nil, timeZone: nil)), at: evening).isEmpty)
        #expect(roadTripInsights(makeSnapshot(ipLocation: parisLocation), at: evening).first?.kind == .daylight)

        // The device location wins over a faraway IP location.
        let withFarawayIP = makeSnapshot(deviceLocation: parisLocation, ipLocation: location(latitude: -33.8688, longitude: 151.2093, timeZone: "Australia/Sydney"))
        #expect(roadTripInsights(withFarawayIP, at: evening).first?.title.hasPrefix("Sunset \(clock(sunset))") == true)
    }

    @Test
    func daylightFormatsTimesInTheLocationsTimeZoneNotTheCalendars() throws {
        // Lisbon is an hour behind the Paris calendar used for formatting everywhere else in this file.
        let lisbon = location(latitude: 38.7223, longitude: -9.1393, timeZone: "Europe/Lisbon")
        let lisbonZone = TimeZone(identifier: "Europe/Lisbon")!
        let sunSet = DaylightReference(latitude: 38.7223, longitude: -9.1393, timeZone: lisbonZone).solarDay(on: now)
        let sunset = try #require(sunSet.sunset)

        let insight = try #require(roadTripInsights(makeSnapshot(deviceLocation: lisbon, timeZoneIdentifier: "Europe/Lisbon"), at: sunset.addingTimeInterval(-30 * 60)).first)
        let expected = sunset.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: "en_GB"), timeZone: lisbonZone))
        #expect(insight.title.hasPrefix("Sunset \(expected)"))
    }

    @Test
    func daylightUsesTheIPLocationsOwnTimeZoneWhenOnlyIPIsKnown() throws {
        // The snapshot time zone follows the Mac when there is no device location; the IP location knows better.
        let sydney = location(latitude: -33.8688, longitude: 151.2093, timeZone: "Australia/Sydney")
        let zone = TimeZone(identifier: "Australia/Sydney")!
        let sunset = try #require(DaylightReference(latitude: -33.8688, longitude: 151.2093, timeZone: zone).solarDay(on: now).sunset)
        let snapshot = makeSnapshot(ipLocation: sydney, timeZoneIdentifier: "Europe/Paris")
        let insight = try #require(roadTripInsights(snapshot, at: sunset.addingTimeInterval(-30 * 60)).first)
        let expected = sunset.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: "en_GB"), timeZone: zone))
        #expect(insight.title.hasPrefix("Sunset \(expected)"))
    }

    @Test
    func daylightIsSilentInPolarDayAndPolarNight() {
        let tromso = location(latitude: 69.6492, longitude: 18.9553, timeZone: "Europe/Oslo")
        let snapshot = makeSnapshot(deviceLocation: tromso, timeZoneIdentifier: "Europe/Oslo")
        let midnightSun = Date(timeIntervalSince1970: 1_782_000_000) // 2026-06-21 00:00 UTC
        let polarNight = Date(timeIntervalSince1970: 1_797_800_000) // about 2026-12-20 21:00 UTC

        for instant in stride(from: 0.0, to: 24 * 3_600, by: 3 * 3_600) {
            #expect(roadTripInsights(snapshot, at: midnightSun.addingTimeInterval(instant)).isEmpty)
            #expect(roadTripInsights(snapshot, at: polarNight.addingTimeInterval(instant)).isEmpty)
        }
    }

    @Test
    func daylightWithoutCivilDuskOmitsTheDetailAndNeverReportsDark() throws {
        // At 64 N near midsummer the sun sets but civil twilight never ends.
        let highNorth = location(latitude: 64.0, longitude: 25.0, timeZone: "Europe/Helsinki")
        let zone = TimeZone(identifier: "Europe/Helsinki")!
        let reference = DaylightReference(latitude: 64.0, longitude: 25.0, timeZone: zone)
        let june = Date(timeIntervalSince1970: 1_782_043_200) // 2026-06-21 12:00 UTC
        let day = reference.solarDay(on: june)
        let sunset = try #require(day.sunset)
        #expect(day.civilDusk == nil)

        let snapshot = makeSnapshot(deviceLocation: highNorth, timeZoneIdentifier: "Europe/Helsinki")
        let caution = try #require(roadTripInsights(snapshot, at: sunset.addingTimeInterval(-30 * 60)).first)
        #expect(caution.detail == nil)
        #expect(roadTripInsights(snapshot, at: sunset.addingTimeInterval(2 * 3_600)).isEmpty)
    }

    @Test
    func daylightRanksRightAfterStrongWindForRoadTrips() throws {
        let sunset = try #require(parisSun.sunset)
        let evening = sunset.addingTimeInterval(-30 * 60) // daylight caution
        let snapshot = makeSnapshot(
            weather: makeWeather(windKph: 45, fetchedAt: evening), // wind caution
            fuel: makeFuel(diesel: station(.diesel)), // fuel info
            deviceLocation: parisLocation
        )

        let kinds = DashboardInsightEngine.insights(for: snapshot, now: evening, calendar: parisCalendar, limit: 20, profile: .roadTrip).map(\.kind)
        #expect(kinds == [.strongWind, .daylight, .fuelNearby])
    }

    // MARK: - Local rhythm

    // Reference (2027): Ramadan 8 Feb - 8 Mar (Umm al-Qura, 29 days), Nyepi 8 Mar (SKB 3 Menteri), Yom Kippur 11 Oct,
    // Songkran 13-15 Apr, Ferragosto 15 Aug, Spring Festival 5-12 Feb (Lunar New Year 6 Feb).

    @Test
    func upcomingPeriodIsAnInfoWithTheDaysUntilItStarts() throws {
        let insight = try #require(rhythmInsight("SA", 2027, 2, 3))

        #expect(insight.kind == .localRhythm)
        #expect(insight.severity == .info)
        #expect(insight.title == "Ramadan starts in 5 days")
        #expect(insight.detail == "Expected 8 Feb · may shift a day")
        #expect(insight.menuBarText == "Ramadan")
        #expect(insight.symbolName == "calendar.badge.clock")
        #expect(insight.relatedCard == .localInfo)

        #expect(try #require(rhythmInsight("SA", 2027, 2, 7)).title == "Ramadan starts tomorrow")
    }

    @Test
    func upcomingDetailIsTheStartDateWhenTheDateIsNotExpectedToShift() throws {
        let songkran = try #require(rhythmInsight("TH", 2027, 4, 1))
        #expect(songkran.title == "Songkran starts in 12 days")
        #expect(songkran.detail == "From 13 Apr")
        #expect(songkran.severity == .info)

        // A computed (not moon-sighted) date also reads "From".
        #expect(try #require(rhythmInsight("IL", 2027, 10, 8)).detail == "From 11 Oct")
    }

    @Test
    func activePeriodCountsTheDaysAndUsesTheFirstSentenceOfTheGuidance() throws {
        let insight = try #require(rhythmInsight("SA", 2027, 2, 19))

        #expect(insight.severity == .info)
        #expect(insight.title == "Ramadan · day 12 of 29")
        #expect(insight.menuBarText == "Ramadan")
        let detail = try #require(insight.detail)
        #expect(detail.hasPrefix("Many cafés and restaurants close during"))
        #expect(detail.hasSuffix("…"))
        #expect(detail.count <= 44)

        #expect(try #require(rhythmInsight("SA", 2027, 2, 8)).title == "Ramadan · day 1 of 29")
        #expect(try #require(rhythmInsight("SA", 2027, 3, 8)).title == "Ramadan · day 29 of 29")
        #expect(try #require(rhythmInsight("SA", 2027, 3, 9)).title == "Eid al-Fitr · until 11 Mar")
    }

    @Test
    func shortPeriodsNameTheirLastDayAndSingleDaysSayToday() throws {
        let songkran = try #require(rhythmInsight("TH", 2027, 4, 14))
        #expect(songkran.title == "Songkran · until 15 Apr")
        #expect(songkran.detail == "Thailand's New Year is a national holiday w…")
        #expect(songkran.menuBarText == "Songkran")

        #expect(try #require(rhythmInsight("IT", 2027, 8, 15)).title == "Ferragosto today")
    }

    @Test
    func anActivePeriodOutranksAnUpcomingOne() throws {
        // Ramadan is on its 28th day and Eid al-Fitr starts in two days.
        #expect(try #require(rhythmInsight("SA", 2027, 3, 7)).title == "Ramadan · day 28 of 29")
        // Without an active period the soonest upcoming one is reported.
        #expect(try #require(rhythmInsight("TH", 2027, 4, 1)).title == "Songkran starts in 12 days")
    }

    @Test
    func theWindowIsFourteenDays() throws {
        #expect(try #require(rhythmInsight("SA", 2027, 1, 25)).title == "Ramadan starts in 14 days")
        #expect(rhythmInsight("SA", 2027, 1, 24) == nil)
        #expect(rhythmInsight("SA", 2027, 3, 10) != nil) // Eid al-Fitr, 9-11 Mar
        #expect(rhythmInsight("SA", 2027, 3, 12) == nil)
    }

    @Test
    func noCountryOrAnUncoveredCountryProducesNothing() {
        #expect(rhythmInsight(device: nil, on: date(2027, 2, 19, 12, 0)) == nil)
        #expect(rhythmInsight("FR", 2027, 2, 19) == nil)
    }

    @Test
    func theCountryFallsBackToIPLocationAndLocalInfo() throws {
        let day = date(2027, 2, 19, 12, 0)
        #expect(rhythmInsight(device: nil, ip: rhythmLocation("SA"), on: day)?.title == "Ramadan · day 12 of 29")
        #expect(rhythmInsight(device: rhythmLocation("SA"), ip: rhythmLocation("TH"), on: day)?.title == "Ramadan · day 12 of 29")
    }

    @Test
    func fullShutdownsAreACautionTheDayBeforeAndOnTheDay() throws {
        let tomorrow = try #require(rhythmInsight("IL", 2027, 10, 10))
        #expect(tomorrow.severity == .caution)
        #expect(tomorrow.title == "Yom Kippur tomorrow: country stops for 25 h")
        #expect(tomorrow.detail == "From 11 Oct")
        #expect(tomorrow.menuBarText == "Yom Kippur")

        let today = try #require(rhythmInsight("IL", 2027, 10, 11))
        #expect(today.severity == .caution)
        #expect(today.title == "Yom Kippur today: country stops for 25 h")
        #expect(today.detail == "Starts the evening before")

        // Two days ahead it is an ordinary heads-up, and it is gone the day after.
        let early = try #require(rhythmInsight("IL", 2027, 10, 9))
        #expect(early.severity == .info)
        #expect(early.title == "Yom Kippur starts in 2 days")
        #expect(rhythmInsight("IL", 2027, 10, 12) == nil)
    }

    @Test
    func nyepiIsACautionWhenLocatedInBaliOrWhenTheRegionIsUnknown() throws {
        for device in [rhythmLocation("ID", region: "Bali"), rhythmLocation("ID", region: "Provinsi Bali"), rhythmLocation("ID")] {
            let tomorrow = try #require(rhythmInsight(device: device, on: date(2027, 3, 7, 12, 0)))
            #expect(tomorrow.severity == .caution)
            #expect(tomorrow.title == "Nyepi tomorrow: Bali shuts down for 24 h")
            #expect(tomorrow.menuBarText == "Nyepi")

            let today = try #require(rhythmInsight(device: device, on: date(2027, 3, 8, 12, 0)))
            #expect(today.severity == .caution)
            #expect(today.title == "Nyepi today: Bali shuts down for 24 h")
        }
    }

    @Test
    func nyepiOutranksARunningRamadanInIndonesia() throws {
        // Ramadan is on its last day on Nyepi, but the shutdown is what the traveller must plan for.
        let day = date(2027, 3, 8, 12, 0)
        #expect(rhythmInsight(device: rhythmLocation("ID", region: "Bali"), on: day)?.kind == .localRhythm)
        #expect(rhythmInsight(device: rhythmLocation("ID", region: "Bali"), on: day)?.title.hasPrefix("Nyepi") == true)
        #expect(rhythmInsight(device: rhythmLocation("ID", region: "Bali"), on: date(2027, 3, 6, 12, 0))?.title == "Ramadan · day 27 of 29")
    }

    @Test
    func nyepiIsDroppedOutsideBali() throws {
        let day = date(2027, 3, 7, 12, 0)
        for region in ["Jakarta", "Special Region of Yogyakarta", "Balikpapan"] {
            // Only Ramadan (on its 28th day) is left.
            let insight = try #require(rhythmInsight(device: rhythmLocation("ID", region: region), on: day))
            #expect(insight.title == "Ramadan · day 28 of 29")
            #expect(insight.severity == .info)
        }
    }

    @Test
    func nyepiRegionComesFromTheDeviceThenTheIPLocation() throws {
        let day = date(2027, 3, 7, 12, 0)
        // IP region alone decides when the device has none (or a blank region).
        #expect(rhythmInsight(device: nil, ip: rhythmLocation("ID", region: "Bali"), on: day)?.severity == .caution)
        #expect(rhythmInsight(device: nil, ip: rhythmLocation("ID", region: "Jakarta"), on: day)?.severity == .info)
        #expect(rhythmInsight(device: rhythmLocation("ID", region: " "), ip: rhythmLocation("ID", region: "Jakarta"), on: day)?.severity == .info)
        // The device location wins over the IP location.
        #expect(rhythmInsight(device: rhythmLocation("ID", region: "Jakarta"), ip: rhythmLocation("ID", region: "Bali"), on: day)?.severity == .info)
        #expect(rhythmInsight(device: rhythmLocation("ID", region: "Bali"), ip: rhythmLocation("ID", region: "Jakarta"), on: day)?.severity == .caution)
    }

    @Test
    func localRhythmRanksRightAfterThePublicHoliday() {
        // Public holiday tomorrow, Ramadan day 1 and diesel nearby are all info.
        let tomorrow = date(2027, 2, 9, 0, 0)
        let snapshot = makeSnapshot(
            localInfo: makeLocalInfo(nextPeriod: HolidayPeriodSnapshot(name: "Armistice", startDate: tomorrow, endDate: tomorrow)),
            fuel: makeFuel(diesel: station(.diesel)),
            deviceLocation: rhythmLocation("SA")
        )

        let kinds = DashboardInsightEngine.insights(for: snapshot, now: date(2027, 2, 8, 12, 0), calendar: parisCalendar, limit: 20).map(\.kind)
        #expect(kinds == [.publicHoliday, .localRhythm, .fuelNearby])
    }

    @Test
    func localRhythmTextsStayCompactForEveryCountryAndPeriod() {
        let countries = [
            "SA", "KW", "QA", "BH", "OM", "IR", "IQ", "LY", "MR", "PK", "JO", "MA", "DZ", "TN", "EG", "AE", "TR", "ID", "MY", "BN",
            "BD", "MV", "SN", "CN", "TW", "HK", "MO", "SG", "VN", "KR", "ES", "PT", "IT", "MT", "MX", "GT", "CO", "PE", "EC", "PH",
            "CR", "SV", "VE", "PY", "IL", "TH", "JP", "IN", "NP"
        ]
        var titles = Set<String>()
        for country in countries {
            // A weekly sweep with a two-week window sees every period of the year.
            for week in 0..<53 {
                let day = parisCalendar.date(byAdding: .day, value: week * 7, to: date(2027, 1, 1, 12, 0))!
                guard let insight = DashboardInsightEngine.insights(
                    for: makeSnapshot(deviceLocation: rhythmLocation(country)), now: day, calendar: parisCalendar, limit: 20
                ).first(where: { $0.kind == .localRhythm }) else {
                    continue
                }
                titles.insert(insight.title)
                #expect(insight.menuBarText.isEmpty == false && insight.menuBarText.count <= 12, "\(country): \(insight.menuBarText)")
                #expect(insight.title.count <= 44, "\(country): \(insight.title)")
                #expect(insight.detail.map { $0.count <= 44 } ?? false, "\(country): \(insight.detail ?? "")")
            }
        }
        #expect(titles.isEmpty == false)
    }

    @Test
    func longPeriodNamesFallBackToACompactMenuBarText() throws {
        // "Spring Festival", "Lunar New Year" and "Settimana Santa" are longer than the menu bar allows.
        #expect(try #require(rhythmInsight("CN", 2027, 1, 30)).title == "Spring Festival starts in 6 days")
        #expect(try #require(rhythmInsight("CN", 2027, 1, 30)).menuBarText == "New Year")
        #expect(try #require(rhythmInsight("HK", 2027, 1, 30)).menuBarText == "New Year")
        #expect(try #require(rhythmInsight("IT", 2027, 3, 20)).menuBarText == "Holy Week")
        #expect(try #require(rhythmInsight("VN", 2027, 1, 30)).menuBarText == "Tết")
    }

    // MARK: - Fixtures

    private let now = Date(timeIntervalSince1970: 1_791_806_400) // 2026-10-12 12:00:00 UTC == 14:00 Paris

    private var parisCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }

    private func roadTripInsights(_ snapshot: DashboardSnapshot, at instant: Date) -> [DashboardInsight] {
        DashboardInsightEngine.insights(for: snapshot, now: instant, calendar: parisCalendar, limit: 20, profile: .roadTrip)
    }

    private var parisLocation: IPLocationSnapshot {
        location(latitude: 48.8566, longitude: 2.3522, timeZone: "Europe/Paris")
    }

    private var parisReference: DaylightReference {
        DaylightReference(latitude: 48.8566, longitude: 2.3522, timeZone: TimeZone(identifier: "Europe/Paris")!)
    }

    private var parisSun: SolarDay {
        parisReference.solarDay(on: now)
    }

    private func parisSolarDay(offsetDays: Int) -> SolarDay {
        parisReference.solarDay(on: parisCalendar.date(byAdding: .day, value: offsetDays, to: now)!)
    }

    private func clock(_ instant: Date) -> String {
        instant.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: "en_GB"), timeZone: TimeZone(identifier: "Europe/Paris")!))
    }

    private func location(latitude: Double?, longitude: Double?, timeZone: String?) -> IPLocationSnapshot {
        IPLocationSnapshot(
            city: nil,
            region: nil,
            country: nil,
            countryCode: nil,
            latitude: latitude,
            longitude: longitude,
            timeZone: timeZone,
            provider: "test",
            fetchedAt: now
        )
    }

    private func rhythmLocation(_ countryCode: String, region: String? = nil) -> IPLocationSnapshot {
        IPLocationSnapshot(
            city: nil,
            region: region,
            country: nil,
            countryCode: countryCode,
            latitude: nil,
            longitude: nil,
            timeZone: nil,
            provider: "test",
            fetchedAt: now
        )
    }

    private func rhythmInsight(
        device: IPLocationSnapshot?,
        ip: IPLocationSnapshot? = nil,
        on day: Date
    ) -> DashboardInsight? {
        DashboardInsightEngine.insights(
            for: makeSnapshot(deviceLocation: device, ipLocation: ip), now: day, calendar: parisCalendar, limit: 20
        ).first { $0.kind == .localRhythm }
    }

    /// The local-rhythm heads-up for a device in `country` at noon on the given Paris date.
    private func rhythmInsight(_ country: String, _ year: Int, _ month: Int, _ day: Int) -> DashboardInsight? {
        rhythmInsight(device: rhythmLocation(country), on: date(year, month, day, 12, 0))
    }

    private func insights(_ snapshot: DashboardSnapshot) -> [DashboardInsight] {
        DashboardInsightEngine.insights(for: snapshot, now: now, calendar: parisCalendar, limit: 20)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        parisCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func makeSnapshot(
        metered: MeteredUsageSnapshot = .disabled,
        alerts: TravelAlertsSnapshot? = nil,
        weather: WeatherSnapshot? = nil,
        localInfo: LocalInfoSnapshot? = nil,
        fuel: FuelPriceSnapshot? = nil,
        deviceLocation: IPLocationSnapshot? = nil,
        ipLocation: IPLocationSnapshot? = nil,
        timeZoneIdentifier: String = "Europe/Paris",
        airQuality: AirQualitySnapshot? = nil
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
                timeZoneIdentifier: timeZoneIdentifier,
                deviceLocation: deviceLocation,
                publicIP: nil,
                location: ipLocation
            ),
            travelAlerts: alerts,
            weather: weather,
            localInfo: localInfo,
            fuelPrices: fuel,
            airQuality: airQuality,
            appState: AppStatusSnapshot(lastRefresh: nil, updateState: .idle, issues: []),
            meteredData: metered
        )
    }

    private func makeMetered(
        isEnabled: Bool = true,
        isActive: Bool = true,
        usedBytes: UInt64,
        capBytes: UInt64?,
        period: MeteredBillingPeriod = .calendarMonth,
        otherBytes: UInt64 = 0
    ) -> MeteredUsageSnapshot {
        let isSession = period == .session
        let reached = capBytes.map { $0 > 0 && usedBytes >= $0 } ?? false
        return MeteredUsageSnapshot(
            isFeatureEnabled: isEnabled,
            isMonitoringActive: isActive,
            networkKey: "wifi:Hotspot",
            networkDisplayName: "Hotspot",
            meteredInterfaceName: "en0",
            sessionStartedAt: nil,
            sessionBytesReceived: isSession ? usedBytes : otherBytes,
            sessionBytesSent: 0,
            periodBytesReceived: isSession ? otherBytes : usedBytes,
            periodBytesSent: 0,
            capBytes: capBytes,
            usageFraction: nil,
            isCapReached: reached,
            billingPeriod: period,
            manualSessionEnabled: false,
            isKnownMeteredNetwork: true,
            networkNameSource: .liveSSID,
            isWiFiConnected: true,
            needsLocationForWiFiNames: false,
            statusMessage: nil,
            capAlertSignal: nil
        )
    }

    private func makeAlerts(
        _ signals: [(TravelAlertKind, TravelAlertSeverity)],
        status: TravelAlertSignalStatus = .ready,
        enabledKinds: [TravelAlertKind] = TravelAlertKind.allCases,
        weatherItemCount: Int? = nil
    ) -> TravelAlertsSnapshot {
        // Signals are kept on checking/unavailable states too, to prove the engine relies on `status`.
        let states = signals.map { kind, severity in
            let signal = TravelAlertSignalSnapshot(
                kind: kind,
                severity: severity,
                title: "Title",
                summary: summary(for: kind),
                sourceName: kind == .advisory ? "Smartraveller" : "Source",
                sourceURL: nil,
                updatedAt: now,
                affectedCountryCodes: [],
                itemCount: kind == .weather ? weatherItemCount : nil
            )
            return TravelAlertSignalState(
                kind: kind,
                status: status,
                signal: signal,
                reason: nil,
                sourceName: signal.sourceName,
                sourceURL: nil,
                lastAttemptedAt: now,
                lastSuccessAt: now
            )
        }

        return TravelAlertsSnapshot(
            enabledKinds: enabledKinds,
            primaryCountryCode: "FR",
            primaryCountryName: "France",
            coverageCountryCodes: ["FR"],
            states: states,
            fetchedAt: now
        )
    }

    private func summary(for kind: TravelAlertKind) -> String {
        switch kind {
        case .advisory:
            "France: exercise a high degree of caution."
        case .weather:
            "Heavy thunderstorms expected across the region this evening and tonight."
        case .security:
            "Security reporting mentions France within the last 72 hours."
        }
    }

    private func makeWeather(
        windKph: Double? = nil,
        windDegrees: Double? = 270,
        rain: Double? = nil,
        slots: [WeatherHourlyForecastSlot] = [],
        fetchedAt: Date? = nil,
        uvIndex: Int? = nil
    ) -> WeatherSnapshot {
        WeatherSnapshot(
            currentTemperatureCelsius: 18,
            apparentTemperatureCelsius: 17,
            conditionDescription: "Cloudy",
            symbolName: "cloud.fill",
            precipitationChance: rain,
            windSpeedKph: windKph,
            windDirectionDegrees: windDegrees,
            uvIndex: uvIndex,
            hourlyForecastSlots: slots,
            fetchedAt: fetchedAt ?? now
        )
    }

    private func makeAirQuality(aqi: Int) -> AirQualitySnapshot {
        AirQualitySnapshot(
            latitude: 48.9,
            longitude: 2.4,
            sourceName: "Open-Meteo",
            europeanAQI: aqi,
            mainPollutant: .pm2_5,
            pm2_5: 40,
            pm10: 50,
            ozone: 60,
            nitrogenDioxide: 20,
            forecastSlots: [],
            fetchedAt: now
        )
    }

    private func slot(
        hours: Double = 0,
        minutes: Double = 0,
        rain: Double? = nil,
        windKph: Double? = nil,
        windDegrees: Double? = nil
    ) -> WeatherHourlyForecastSlot {
        WeatherHourlyForecastSlot(
            date: now.addingTimeInterval(hours * 3_600 + minutes * 60),
            symbolName: "cloud.fill",
            conditionDescription: "Cloudy",
            temperatureCelsius: 17,
            precipitationChance: rain,
            windSpeedKph: windKph,
            windDirectionDegrees: windDegrees
        )
    }

    private func holiday(dayOffset: Int, name: String = "Armistice") -> HolidayPeriodSnapshot {
        let start = parisCalendar.date(byAdding: .day, value: dayOffset, to: parisCalendar.startOfDay(for: now))!
        return HolidayPeriodSnapshot(name: name, startDate: start, endDate: start)
    }

    private func makeLocalInfo(
        currentPeriod: HolidayPeriodSnapshot? = nil,
        nextPeriod: HolidayPeriodSnapshot? = nil,
        status: LocalHolidayStatus? = nil
    ) -> LocalInfoSnapshot {
        let holidayStatus = status ?? LocalHolidayStatus(
            state: currentPeriod != nil ? .current : (nextPeriod != nil ? .upcoming : .unsupported),
            currentPeriod: currentPeriod,
            nextPeriod: nextPeriod,
            note: nil
        )
        return LocalInfoSnapshot(
            status: .ready,
            locality: "Paris",
            administrativeRegion: nil,
            countryCode: "FR",
            countryName: "France",
            timeZoneIdentifier: "Europe/Paris",
            subdivisionCode: nil,
            publicHolidayStatus: holidayStatus,
            schoolHolidayStatus: nil,
            localPriceLevel: nil,
            sources: [],
            fetchedAt: now,
            detail: nil,
            note: nil
        )
    }

    private func station(
        _ fuelType: FuelType,
        price: Double = 1.689,
        distance: Double = 2.4
    ) -> FuelStationPrice {
        FuelStationPrice(
            fuelType: fuelType,
            stationName: "Station",
            address: nil,
            locality: nil,
            pricePerLiter: price,
            currencyCode: "EUR",
            distanceKilometers: distance,
            latitude: 48.85,
            longitude: 2.35,
            updatedAt: now
        )
    }

    private func makeFuel(
        status: FuelPriceStatus = .ready,
        diesel: FuelStationPrice? = nil,
        gasoline: FuelStationPrice? = nil,
        radius: Double = 50
    ) -> FuelPriceSnapshot {
        FuelPriceSnapshot(
            status: status,
            sourceName: "Test",
            sourceURL: nil,
            countryCode: "FR",
            countryName: "France",
            searchRadiusKilometers: radius,
            diesel: diesel,
            gasoline: gasoline,
            fetchedAt: now,
            detail: nil
        )
    }
}
