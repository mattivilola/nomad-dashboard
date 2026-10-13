import Foundation
import Testing
@testable import NomadCore

struct JetLagTests {
    private let now = Date(timeIntervalSince1970: 1_791_806_400) // 2026-10-12 14:00 Paris (UTC+2)
    private let locale = Locale(identifier: "en_GB")
    private let hour: TimeInterval = 3_600
    private let day: TimeInterval = 86_400

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.locale = locale
        return calendar
    }

    private var paris: DaylightReference {
        DaylightReference(latitude: 48.8566, longitude: 2.3522, timeZone: TimeZone(identifier: "Europe/Paris")!)
    }

    /// A record `ago` seconds before `now`.
    private func record(_ identifier: String, _ offsetHours: Double, ago: TimeInterval) -> TimeZoneShiftRecord {
        TimeZoneShiftRecord(date: now.addingTimeInterval(-ago), identifier: identifier, offsetSeconds: Int(offsetHours * 3_600))
    }

    private func assess(_ history: [TimeZoneShiftRecord], at date: Date? = nil) -> JetLagAssessment? {
        JetLagAdvisor.assessment(history: history, now: date ?? now, calendar: calendar)
    }

    // MARK: - Direction and size

    @Test
    func aShiftToTheEastIsDetectedWithItsSizeAndDay() throws {
        // Paris (UTC+2) to Bangkok (UTC+7), arrived yesterday.
        let assessment = try #require(assess([
            record("Europe/Paris", 2, ago: 10 * day),
            record("Asia/Bangkok", 7, ago: 1 * day)
        ]))

        #expect(assessment.direction == .east)
        #expect(assessment.shiftHours == 5)
        #expect(assessment.dayNumber == 2)
        #expect(assessment.adjustmentDays == 5)
        #expect(assessment.shiftedAt == now.addingTimeInterval(-day))
    }

    @Test
    func aShiftToTheWestIsDetectedAndTakesLonger() throws {
        // Paris to New York (UTC-4), arrived this morning.
        let assessment = try #require(assess([
            record("Europe/Paris", 2, ago: 5 * day),
            record("America/New_York", -4, ago: 4 * hour)
        ]))

        #expect(assessment.direction == .west)
        #expect(assessment.shiftHours == 6)
        #expect(assessment.dayNumber == 1)
        #expect(assessment.adjustmentDays == 4)
    }

    @Test
    func adjustmentIsAboutADayPerZoneEastwardAndOnePerOneAndAHalfWestward() {
        #expect(JetLagAdvisor.adjustmentDays(shiftHours: 3, direction: .east) == 3)
        #expect(JetLagAdvisor.adjustmentDays(shiftHours: 3, direction: .west) == 2)
        #expect(JetLagAdvisor.adjustmentDays(shiftHours: 8, direction: .west) == 5)
        #expect(JetLagAdvisor.adjustmentDays(shiftHours: 5.5, direction: .east) == 6)
        // Capped, and never below one day.
        #expect(JetLagAdvisor.adjustmentDays(shiftHours: 12, direction: .east) == JetLagAdvisor.maximumAdjustmentDays)
        #expect(JetLagAdvisor.adjustmentDays(shiftHours: 12, direction: .west) == JetLagAdvisor.maximumAdjustmentDays)
        #expect(JetLagAdvisor.adjustmentDays(shiftHours: 0.2, direction: .east) == 1)
    }

    @Test
    func threeHoursCountsAndLessDoesNot() {
        let exactly = assess([record("Europe/Paris", 2, ago: 5 * day), record("Asia/Dubai", 5, ago: hour)])
        let almost = assess([record("Europe/Paris", 2, ago: 5 * day), TimeZoneShiftRecord(
            date: now.addingTimeInterval(-hour), identifier: "Asia/Dubai", offsetSeconds: 7_200 + 10_740
        )])

        #expect(exactly?.shiftHours == 3)
        #expect(almost == nil)
    }

    @Test
    func halfHourZonesGiveHalfHours() throws {
        // Paris to Delhi (UTC+5:30).
        let assessment = try #require(assess([record("Europe/Paris", 2, ago: 5 * day), record("Asia/Kolkata", 5.5, ago: hour)]))
        #expect(assessment.shiftHours == 3.5)
        #expect(JetLagSummary(assessment: assessment, guidance: JetLagAdvisor.guidance(for: assessment, reference: nil, now: now))
            .shiftText == "Shifted 3.5 h east")
    }

    @Test
    func aDaylightSavingChangeIsNotATrip() {
        // The clocks went back or forward by an hour in the same place.
        #expect(assess([record("Europe/Paris", 2, ago: 200 * day), record("Europe/Paris", 1, ago: hour)]) == nil)
        #expect(assess([record("Europe/Paris", 1, ago: 200 * day), record("Europe/Paris", 2, ago: hour)]) == nil)
        // Neighbouring zones one hour apart.
        #expect(assess([record("Europe/Paris", 2, ago: 5 * day), record("Europe/Helsinki", 3, ago: hour)]) == nil)
    }

    @Test
    func aChangeOfIdentifierWithTheSameOffsetIsNotAShift() {
        #expect(assess([record("Europe/Paris", 2, ago: 5 * day), record("Europe/Berlin", 2, ago: hour)]) == nil)
    }

    @Test
    func noHistoryOrASingleRecordHasNoShift() {
        #expect(assess([]) == nil)
        #expect(assess([record("Europe/Paris", 2, ago: hour)]) == nil)
    }

    @Test
    func recordsAreReadInTimeOrderAndFutureOnesAreIgnored() throws {
        let history = [
            record("Asia/Bangkok", 7, ago: 1 * day),
            TimeZoneShiftRecord(date: now.addingTimeInterval(day), identifier: "Europe/Paris", offsetSeconds: 7_200),
            record("Europe/Paris", 2, ago: 10 * day)
        ]

        #expect(try #require(assess(history)).direction == .east)
    }

    // MARK: - Multi-step shifts

    @Test
    func stopoversWithinThreeDaysAddUpToOneShift() throws {
        // Paris to Bangkok two days ago, on to Tokyo (UTC+9) yesterday: seven hours from where the day started.
        let assessment = try #require(assess([
            record("Europe/Paris", 2, ago: 20 * day),
            record("Asia/Bangkok", 7, ago: 2 * day),
            record("Asia/Tokyo", 9, ago: 1 * day)
        ]))

        #expect(assessment.direction == .east)
        #expect(assessment.shiftHours == 7)
        #expect(assessment.shiftedAt == now.addingTimeInterval(-2 * day))
        #expect(assessment.dayNumber == 3)
        #expect(assessment.adjustmentDays == 7)
    }

    @Test
    func severalSmallStepsCanAddUpToAShift() throws {
        let assessment = try #require(assess([
            record("Europe/Paris", 2, ago: 20 * day),
            record("Europe/Moscow", 4, ago: 2 * day),
            record("Asia/Dubai", 6, ago: 1 * day)
        ]))

        #expect(assessment.shiftHours == 4)
    }

    @Test
    func goingOutAndBackCancelsOut() {
        #expect(assess([
            record("Europe/Paris", 2, ago: 20 * day),
            record("Asia/Bangkok", 7, ago: 2 * day),
            record("Europe/Paris", 2, ago: 1 * day)
        ]) == nil)
    }

    @Test
    func aStepAWeekLaterIsAnotherShiftNotPartOfTheFirst() throws {
        // Bangkok five days ago (a shift that has run its five days by now), then Tokyo yesterday (two hours more).
        #expect(assess([
            record("Europe/Paris", 2, ago: 20 * day),
            record("Asia/Bangkok", 7, ago: 5 * day),
            record("Asia/Tokyo", 9, ago: 1 * day)
        ]) == nil)

        // A big second shift is judged on its own, from Bangkok's clock.
        let second = try #require(assess([
            record("Europe/Paris", 2, ago: 20 * day),
            record("Asia/Bangkok", 7, ago: 8 * day),
            record("America/Los_Angeles", -7, ago: 1 * day)
        ]))
        #expect(second.direction == .west)
        #expect(second.shiftHours == 14)
        #expect(second.dayNumber == 2)
    }

    // MARK: - Day count and expiry

    @Test
    func theNudgeLastsTheAdjustmentDaysAndThenEnds() throws {
        // Three hours east: about three days.
        let history = [record("Europe/Paris", 2, ago: 30 * day), record("Asia/Dubai", 5, ago: 0)]
        let start = now

        func at(_ days: Int) -> JetLagAssessment? {
            assess(history, at: calendar.date(byAdding: .day, value: days, to: start))
        }

        #expect(try #require(at(0)).dayNumber == 1)
        #expect(try #require(at(1)).dayNumber == 2)
        #expect(try #require(at(2)).dayNumber == 3)
        // Past 72 hours it is still on, until the third day is over.
        #expect(try #require(at(2)).adjustmentDays == 3)
        #expect(at(3) == nil)
        #expect(at(10) == nil)
    }

    @Test
    func daysCountOnTheCalendarNotIn24HourBlocks() throws {
        // Arrived at 23:00 last night: this morning is already day 2.
        let lastNight = calendar.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 23))!
        let thisMorning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 7))!
        let assessment = try #require(assess([
            record("Europe/Paris", 2, ago: 10 * day),
            TimeZoneShiftRecord(date: lastNight, identifier: "Asia/Bangkok", offsetSeconds: 25_200)
        ], at: thisMorning))

        #expect(assessment.dayNumber == 2)
    }

    // MARK: - Guidance

    @Test
    func eastwardGuidanceSeeksMorningLightAndDimsTheEvening() throws {
        let assessment = JetLagAssessment(direction: .east, shiftHours: 5, shiftedAt: now, dayNumber: 2, adjustmentDays: 5)
        let guidance = JetLagAdvisor.guidance(for: assessment, reference: paris, now: now, locale: locale)

        let sunrise = try #require(paris.solarDay(on: now).sunrise)
        let window = try #require(guidance.seekLight)
        #expect(window.start == sunrise)
        #expect(window.duration == 2.5 * hour)
        #expect(guidance.avoidLightBefore == nil)
        let dim = try #require(guidance.dimLightsAfter)
        #expect(paris.clockTime(dim, locale: locale) == "21:00")
        #expect(guidance.text == "Get morning light \(paris.clockTime(sunrise, locale: locale))–\(paris.clockTime(window.end, locale: locale)) · dim lights after 21:00")
    }

    @Test
    func westwardGuidanceSeeksTheLateAfternoonAndAvoidsVeryEarlyLight() throws {
        let assessment = JetLagAssessment(direction: .west, shiftHours: 6, shiftedAt: now, dayNumber: 1, adjustmentDays: 4)
        let guidance = JetLagAdvisor.guidance(for: assessment, reference: paris, now: now, locale: locale)

        let sunset = try #require(paris.solarDay(on: now).sunset)
        let window = try #require(guidance.seekLight)
        #expect(window.end == sunset)
        #expect(window.duration == 2.5 * hour)
        #expect(guidance.dimLightsAfter == nil)
        #expect(paris.clockTime(try #require(guidance.avoidLightBefore), locale: locale) == "8:00")
        #expect(guidance.text.hasPrefix("Get afternoon light "))
        #expect(guidance.text.hasSuffix(" · avoid bright light before 8:00"))
    }

    @Test
    func guidanceWithoutCoordinatesOrASunriseStillSaysWhatToDo() {
        let east = JetLagAssessment(direction: .east, shiftHours: 5, shiftedAt: now, dayNumber: 2, adjustmentDays: 5)
        let west = JetLagAssessment(direction: .west, shiftHours: 5, shiftedAt: now, dayNumber: 2, adjustmentDays: 3)

        let noLocation = JetLagAdvisor.guidance(for: east, reference: nil, now: now, locale: locale)
        #expect(noLocation.seekLight == nil)
        #expect(noLocation.text.hasPrefix("Get bright morning light · dim lights after "))

        // Svalbard in midsummer: the sun does not set.
        let midnightSun = DaylightReference(latitude: 78.2, longitude: 15.6, timeZone: TimeZone(identifier: "Arctic/Longyearbyen")!)
        let june = Date(timeIntervalSince1970: 1_781_524_800)
        let polar = JetLagAdvisor.guidance(for: west, reference: midnightSun, now: june, locale: locale)
        #expect(polar.seekLight == nil)
        #expect(polar.text.hasPrefix("Get light in the late afternoon · avoid bright light before "))
    }

    // MARK: - Where the time zone comes from

    @Test
    func theEffectiveTimeZoneIsTheDeviceLocationsThenTheSnapshots() {
        func context(device: String?, snapshot: String) -> TravelContextSnapshot {
            TravelContextSnapshot(
                wifi: nil, vpn: nil, timeZoneIdentifier: snapshot,
                deviceLocation: device.map {
                    IPLocationSnapshot(city: nil, region: nil, country: nil, countryCode: nil, latitude: nil, longitude: nil, timeZone: $0, provider: "test", fetchedAt: .now)
                },
                publicIP: nil,
                location: IPLocationSnapshot(city: nil, region: nil, country: nil, countryCode: nil, latitude: nil, longitude: nil, timeZone: "America/Chicago", provider: "ip", fetchedAt: .now)
            )
        }

        #expect(context(device: "Asia/Bangkok", snapshot: "Europe/Paris").effectiveTimeZone?.identifier == "Asia/Bangkok")
        #expect(context(device: nil, snapshot: "Europe/Paris").effectiveTimeZone?.identifier == "Europe/Paris")
        // An identifier the system does not know is skipped; the IP location is never used.
        #expect(context(device: "Not/AZone", snapshot: "Europe/Paris").effectiveTimeZone?.identifier == "Europe/Paris")
        #expect(context(device: nil, snapshot: "Not/AZone").effectiveTimeZone == nil)
    }

    // MARK: - Heads-up

    private func snapshot(timeZone: String = "Asia/Bangkok") -> DashboardSnapshot {
        let placeholder = DashboardSnapshot.placeholder
        return DashboardSnapshot(
            network: placeholder.network,
            power: placeholder.power,
            travelContext: TravelContextSnapshot(
                wifi: nil,
                vpn: nil,
                timeZoneIdentifier: timeZone,
                deviceLocation: IPLocationSnapshot(
                    city: "Bangkok", region: nil, country: "Thailand", countryCode: "TH",
                    latitude: 13.7563, longitude: 100.5018, timeZone: timeZone, provider: "Core Location", fetchedAt: now
                ),
                publicIP: nil,
                location: nil
            ),
            weather: nil,
            appState: placeholder.appState
        )
    }

    private var bangkokCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        calendar.locale = locale
        return calendar
    }

    private func headsUp(_ history: [TimeZoneShiftRecord], at date: Date? = nil) -> DashboardInsight? {
        DashboardInsightEngine.insights(
            for: snapshot(), now: date ?? now, calendar: bangkokCalendar, limit: 20, timeZoneShifts: history
        ).first { $0.kind == .jetLag }
    }

    @Test
    func theHeadsUpNamesTheDayAndTheLightAdvice() throws {
        let insight = try #require(headsUp([
            record("Europe/Paris", 2, ago: 10 * day),
            record("Asia/Bangkok", 7, ago: 1 * day)
        ]))

        #expect(insight.title == "Jet lag: day 2 of about 5")
        #expect(insight.menuBarText == "Jet lag")
        #expect(insight.severity == .info)
        #expect(insight.symbolName == "moon.zzz")
        #expect(insight.relatedCard == .travelContext)
        #expect(insight.detail?.hasPrefix("Get morning light ") == true)
        #expect(insight.detail?.hasSuffix(" · dim lights after 21:00") == true)
    }

    @Test
    func theHeadsUpIsGoneWithoutAShiftAndAfterTheAdjustmentDays() {
        #expect(headsUp([]) == nil)
        #expect(headsUp([record("Europe/Paris", 1, ago: 10 * day), record("Europe/Paris", 2, ago: hour)]) == nil)
        let history = [record("Europe/Paris", 2, ago: 30 * day), record("Asia/Dubai", 5, ago: 4 * day)]
        #expect(headsUp(history) == nil)
    }

    @Test
    func jetLagFollowsTheUpcomingTripInTheTieBreakOrderOfBothProfiles() {
        for profile in TravelProfile.allCases {
            let order = DashboardInsightKind.tieBreakOrder(for: profile)
            #expect(order.firstIndex(of: .jetLag) == order.firstIndex(of: .upcomingTrip).map { $0 + 1 })
        }
    }

    // MARK: - Arrival briefing

    @Test
    func anArrivalWithAShiftGetsAJetLagSection() throws {
        let history = [record("Europe/Paris", 2, ago: 10 * day), record("Asia/Bangkok", 7, ago: 4 * hour)]
        let event = ArrivalEvent(countryCode: "TH", previousCountryCode: "FR", arrivedOn: VisitedCountryDayStamp(date: now, calendar: bangkokCalendar))

        func briefing(_ shifts: [TimeZoneShiftRecord]) -> ArrivalBriefing {
            ArrivalBriefing.make(
                event: event, snapshot: snapshot(), settings: AppSettings(), homeTimeZoneIdentifier: "Europe/Paris",
                timeZoneShifts: shifts, now: now, calendar: bangkokCalendar, locale: locale
            )
        }

        let jetLag = try #require(briefing(history).jetLag)
        #expect(jetLag.assessment.direction == .east)
        #expect(jetLag.assessment.shiftHours == 5)
        #expect(jetLag.title == "Jet lag: day 1 of about 5")
        #expect(jetLag.guidance.text.hasPrefix("Get morning light "))
        #expect(briefing([]).jetLag == nil)
        #expect(briefing([record("Europe/Paris", 1, ago: 10 * day), record("Europe/Paris", 2, ago: hour)]).jetLag == nil)
    }

    // MARK: - Store

    private func makeStore() -> FileTimeZoneShiftStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return FileTimeZoneShiftStore(fileURL: directory.appendingPathComponent("time-zone-shifts.json"))
    }

    @Test
    func theStoreKeepsRecordsOldestFirstAndSkipsAnUnchangedZone() async throws {
        let store = makeStore()
        #expect(try await store.loadAll().isEmpty)

        let paris = record("Europe/Paris", 2, ago: 5 * day)
        let bangkok = record("Asia/Bangkok", 7, ago: 1 * day)
        try await store.record(bangkok)
        try await store.record(paris)
        try await store.record(TimeZoneShiftRecord(date: now, identifier: "Asia/Bangkok", offsetSeconds: 25_200))

        let records = try await store.loadAll()
        #expect(records == [paris, bangkok])
    }

    @Test
    func theStoreRecordsADaylightSavingChangeOfTheSameZone() async throws {
        let store = makeStore()
        try await store.record(record("Europe/Paris", 2, ago: 2 * day))
        try await store.record(record("Europe/Paris", 1, ago: 1 * day))

        #expect(try await store.loadAll().map(\.offsetSeconds) == [7_200, 3_600])
    }

    @Test
    func theStoreKeepsOnlyTheLastTenRecords() async throws {
        let store = makeStore()
        for index in 0..<15 {
            try await store.record(TimeZoneShiftRecord(
                date: now.addingTimeInterval(Double(index) * hour),
                identifier: index.isMultiple(of: 2) ? "Europe/Paris" : "Asia/Bangkok",
                offsetSeconds: index.isMultiple(of: 2) ? 7_200 : 25_200
            ))
        }

        let records = try await store.loadAll()
        #expect(records.count == FileTimeZoneShiftStore.maximumRecords)
        #expect(records.first?.date == now.addingTimeInterval(5 * hour))
        #expect(records.last?.date == now.addingTimeInterval(14 * hour))
    }

    @Test
    func theStorePersistsAcrossInstancesAndResets() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("time-zone-shifts.json")
        let first = FileTimeZoneShiftStore(fileURL: url)
        try await first.record(record("Europe/Paris", 2, ago: day))

        let second = FileTimeZoneShiftStore(fileURL: url)
        #expect(try await second.loadAll().count == 1)

        try await second.reset()
        #expect(try await first.loadAll().isEmpty)
    }
}
