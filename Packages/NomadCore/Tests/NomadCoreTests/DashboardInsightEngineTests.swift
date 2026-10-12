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
    }

    @Test
    func everyInsightCarriesCompactMenuBarText() {
        let snapshot = makeSnapshot(
            metered: makeMetered(usedBytes: 850, capBytes: 1_000),
            alerts: makeAlerts([(.advisory, .caution), (.weather, .caution), (.security, .caution)]),
            weather: makeWeather(windKph: 45, slots: [slot(hours: 2, rain: 0.8)]),
            localInfo: makeLocalInfo(currentPeriod: holiday(dayOffset: 0)),
            fuel: makeFuel(diesel: station(.diesel))
        )

        let all = insights(snapshot)
        #expect(Set(all.map(\.kind)) == Set(DashboardInsightKind.allCases))
        #expect(all.allSatisfy { $0.menuBarText.isEmpty == false && $0.menuBarText.count <= 13 })
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

    // MARK: - Fixtures

    private let now = Date(timeIntervalSince1970: 1_791_806_400) // 2026-10-12 12:00:00 UTC == 14:00 Paris

    private var parisCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
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
        fuel: FuelPriceSnapshot? = nil
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
                deviceLocation: nil,
                publicIP: nil,
                location: nil
            ),
            travelAlerts: alerts,
            weather: weather,
            localInfo: localInfo,
            fuelPrices: fuel,
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
        fetchedAt: Date? = nil
    ) -> WeatherSnapshot {
        WeatherSnapshot(
            currentTemperatureCelsius: 18,
            apparentTemperatureCelsius: 17,
            conditionDescription: "Cloudy",
            symbolName: "cloud.fill",
            precipitationChance: rain,
            windSpeedKph: windKph,
            windDirectionDegrees: windDegrees,
            hourlyForecastSlots: slots,
            fetchedAt: fetchedAt ?? now
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
