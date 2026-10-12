import Foundation
import Testing
@testable import NomadCore

struct StayRulesTests {
    // MARK: - Schengen membership

    @Test
    func schengenMemberStatesAreTheTwentyNineVerifiedCountries() {
        // Verified 2026-10: 25 EU states (all but Cyprus and Ireland) plus IS, LI, NO and CH.
        let expected = [
            "AT", "BE", "BG", "CH", "CZ", "DE", "DK", "EE", "ES", "FI", "FR", "GR", "HR", "HU", "IS",
            "IT", "LI", "LT", "LU", "LV", "MT", "NL", "NO", "PL", "PT", "RO", "SE", "SI", "SK"
        ]
        #expect(SchengenArea.memberStates == expected)
        #expect(SchengenArea.memberStates.count == 29)
        #expect(SchengenArea.isMember("bg") && SchengenArea.isMember("RO"))
        #expect(SchengenArea.isMember("IE") == false && SchengenArea.isMember("CY") == false)
        #expect(SchengenArea.isMember("GB") == false)
    }

    @Test
    func freeMovementCoversEUEEAAndSwitzerlandIncludingIrelandAndCyprus() {
        #expect(SchengenArea.freeMovementStates.count == 27 + 3 + 1)
        for code in ["FI", "IE", "CY", "DE", "IS", "LI", "NO", "CH"] {
            #expect(SchengenArea.isExempt(citizenships: [code]))
        }
        #expect(SchengenArea.isExempt(citizenships: [" fi "]))
        #expect(SchengenArea.isExempt(citizenships: ["US", "DE"]))
        #expect(SchengenArea.isExempt(citizenships: ["US"]) == false)
        #expect(SchengenArea.isExempt(citizenships: ["GB", "AU"]) == false)
        #expect(SchengenArea.isExempt(citizenships: []) == false)
    }

    // MARK: - Schengen 90/180

    // Reference: today is Mon 2026-10-12. FR every day 2026-08-01 ... 2026-10-12 is 31 + 30 + 12 = 73
    // days: used 73, remaining 17, the window starts 2026-04-16 (today - 179), and staying 17 more days
    // makes the 90th day 2026-10-29.
    @Test
    func countsDaysInTheWindowAndFindsTheLastPermittedDay() throws {
        let days = run(2026, 8, 1, through: (2026, 10, 12), "FR")
        let allowance = try #require(schengen(days, now: today, citizenships: ["US"]).allowance)

        #expect(schengen(days, now: today, citizenships: ["US"]) == .counting(allowance))
        #expect(allowance.usedDays == 73)
        #expect(allowance.remainingDays == 17)
        #expect(allowance.mustLeaveBy == startOfDay(2026, 10, 29))
        #expect(allowance.windowStart == startOfDay(2026, 4, 16))
    }

    // Reference: FR 2026-07-15 ... 2026-10-12 is 17 + 31 + 30 + 12 = 90 days: exactly 90 used, 0 left,
    // and today is the last permitted day.
    @Test
    func exactlyNinetyDaysLeavesNothingAndTodayIsTheLastDay() throws {
        let days = run(2026, 7, 15, through: (2026, 10, 12), "FR")
        let allowance = try #require(schengen(days, now: today, citizenships: ["US"]).allowance)

        #expect(allowance.usedDays == 90)
        #expect(allowance.remainingDays == 0)
        #expect(allowance.mustLeaveBy == startOfDay(2026, 10, 12))
    }

    // Reference: 95 days (2026-07-10 ... 2026-10-12) is an overstay of 5: used 95, remaining clamped to 0.
    @Test
    func anOverstayReportsTheRealCountAndNoRemainingDays() throws {
        let days = run(2026, 7, 10, through: (2026, 10, 12), "ES")
        let allowance = try #require(schengen(days, now: today, citizenships: ["US"]).allowance)

        #expect(allowance.usedDays == 95)
        #expect(allowance.remainingDays == 0)
        #expect(allowance.mustLeaveBy == startOfDay(2026, 10, 12))
    }

    // Reference: FR 2026-01-01 ... 2026-03-31 is 90 days. On 2026-06-29 the window [2026-01-01, 2026-06-29]
    // still holds all 90 (used 90); one day later 2026-01-01 has slid out (used 89); and by 2026-09-29 all
    // of it is gone. Outside Schengen there is no leave-by date.
    @Test
    func theWindowSlidesOneDayAtATime() throws {
        let days = run(2026, 1, 1, through: (2026, 3, 31), "FR") + run(2026, 4, 1, through: (2026, 9, 29), "GB")

        let onLastFullDay = try #require(schengen(days, now: at(2026, 6, 29), citizenships: ["US"]).allowance)
        #expect(onLastFullDay.usedDays == 90)
        #expect(onLastFullDay.windowStart == startOfDay(2026, 1, 1))
        #expect(onLastFullDay.mustLeaveBy == nil)

        let nextDay = try #require(schengen(days, now: at(2026, 6, 30), citizenships: ["US"]).allowance)
        #expect(nextDay.usedDays == 89)
        #expect(nextDay.remainingDays == 1)
        #expect(nextDay.windowStart == startOfDay(2026, 1, 2))

        let later = try #require(schengen(days, now: at(2026, 9, 29), citizenships: ["US"]).allowance)
        #expect(later.usedDays == 0)
        #expect(later.remainingDays == 90)
    }

    // Reference: FR 2026-01-01 ... 2026-02-28 (59 days), then outside, then FR 2026-06-20 ... 2026-06-29
    // (10 days). On 2026-06-29 used is 69. Staying on, the old block slides out as fast as new days are
    // added, so the total stays 69 for 59 days; after that it is 10 + d. The 90th day is d = 80, which is
    // 2026-09-17 (a naive 90 - 69 = 21 days would say 2026-07-20).
    @Test
    func leaveByAccountsForOldDaysSlidingOutOfTheWindow() throws {
        let days = run(2026, 1, 1, through: (2026, 2, 28), "FR")
            + run(2026, 3, 1, through: (2026, 6, 19), "GB")
            + run(2026, 6, 20, through: (2026, 6, 29), "FR")
        let allowance = try #require(schengen(days, now: at(2026, 6, 29), citizenships: ["US"]).allowance)

        #expect(allowance.usedDays == 69)
        #expect(allowance.remainingDays == 21)
        #expect(allowance.mustLeaveBy == startOfDay(2026, 9, 17))
    }

    // Reference: FR 2026-06-01 ... 06-30 (30), GB 07-01 ... 08-31 (62 days outside), FR 09-01 ... 10-12 (42):
    // used 72, the days outside do not count, 18 left, last permitted day 2026-10-30.
    @Test
    func reEntryAfterDaysOutsideOnlyCountsSchengenDays() throws {
        let days = run(2026, 6, 1, through: (2026, 6, 30), "FR")
            + run(2026, 7, 1, through: (2026, 8, 31), "GB")
            + run(2026, 9, 1, through: (2026, 10, 12), "FR")
        let allowance = try #require(schengen(days, now: today, citizenships: ["US"]).allowance)

        #expect(allowance.usedDays == 72)
        #expect(allowance.remainingDays == 18)
        #expect(allowance.mustLeaveBy == startOfDay(2026, 10, 30))
    }

    // Reference: GB 10-01 ... 10-10, with 10-10 also recorded in FR (a border day), FR 10-11 ... 10-12.
    // Entry day counts as a full Schengen day: used 3 (10-10, 10-11, 10-12). The GB stay seen from
    // 2026-10-10 is 10 days and the FR stay then is 1 day, so the border day belongs to both.
    @Test
    func aBorderDayWithTwoCountriesCountsForBoth() throws {
        let days = run(2026, 10, 1, through: (2026, 10, 10), "GB")
            + [visit(2026, 10, 10, "FR")]
            + run(2026, 10, 11, through: (2026, 10, 12), "FR")

        let allowance = try #require(schengen(days, now: today, citizenships: ["US"]).allowance)
        #expect(allowance.usedDays == 3)

        let onBorderDay = StayCalculator(days: days, now: at(2026, 10, 10), calendar: calendar)
        #expect(onBorderDay.currentStay(in: "GB")?.dayCount == 10)
        #expect(onBorderDay.currentStay(in: "FR")?.dayCount == 1)

        // A day recorded twice in the same country is still one day.
        let duplicated = run(2026, 10, 10, through: (2026, 10, 12), "FR") + [visit(2026, 10, 12, "FR"), visit(2026, 10, 12, "GB")]
        #expect(try #require(schengen(duplicated, now: today, citizenships: ["US"]).allowance).usedDays == 3)
    }

    @Test
    func exemptCitizenshipsAreNeverCounted() {
        let days = run(2026, 6, 1, through: (2026, 10, 12), "FR")

        #expect(schengen(days, now: today, citizenships: ["FI"]) == .exempt)
        #expect(schengen(days, now: today, citizenships: ["US", "NO"]) == .exempt)
        #expect(schengen(days, now: today, citizenships: ["IE"]) == .exempt)
        #expect(schengen(days, now: today, citizenships: ["CH"]) == .exempt)
        #expect(schengen(days, now: today, citizenships: ["FI"]).allowance == nil)
    }

    @Test
    func withoutACitizenshipTheCountsAreStillProvided() throws {
        let days = run(2026, 8, 1, through: (2026, 10, 12), "FR")
        let status = schengen(days, now: today, citizenships: [])

        guard case let .unknownCitizenship(allowance) = status else {
            Issue.record("expected unknownCitizenship, got \(status)")
            return
        }
        #expect(allowance.usedDays == 73)
        #expect(allowance.remainingDays == 17)
        #expect(allowance.mustLeaveBy == startOfDay(2026, 10, 29))
        #expect(schengen(days, now: today, citizenships: ["US"]).allowance == allowance)
    }

    @Test
    func inferredAndManualDaysCountLikeObservedOnes() throws {
        let days = [
            visit(2026, 10, 8, "DE", inferred: true),
            visit(2026, 10, 9, "DE", inferred: true),
            visit(2026, 10, 10, "DE", manual: true),
            visit(2026, 10, 11, "DE"),
            visit(2026, 10, 12, "DE")
        ]
        let allowance = try #require(schengen(days, now: today, citizenships: ["US"]).allowance)

        #expect(allowance.usedDays == 5)
        #expect(StayCalculator(days: days, now: today, calendar: calendar).currentStay(in: "DE")?.dayCount == 5)
    }

    @Test
    func daysWithoutACountryCodeAndFutureDaysAreIgnored() throws {
        let days = [
            VisitedCountryDay(day: stamp(2026, 10, 11), country: "Atlantis", countryCode: nil, source: .deviceLocation, isInferred: false),
            visit(2026, 10, 12, "FR"),
            visit(2026, 10, 13, "FR"),
            visit(2026, 10, 14, "FR")
        ]
        let allowance = try #require(schengen(days, now: today, citizenships: ["US"]).allowance)

        #expect(allowance.usedDays == 1)
        #expect(StayCalculator(days: days, now: today, calendar: calendar).currentStay(in: "FR")?.dayCount == 1)
    }

    // Reference: Paris falls back on 2026-10-25 (a 25-hour day). DE 2026-10-20 ... 10-26, now 2026-10-26
    // 23:30: 7 days used and 7-day stay, 83 left, last day 2027-01-17, window starts 2026-04-30 (CEST).
    @Test
    func daylightSavingEndDoesNotLoseOrAddADay() throws {
        let days = run(2026, 10, 20, through: (2026, 10, 26), "DE")
        let now = at(2026, 10, 26, hour: 23, minute: 30)
        let allowance = try #require(schengen(days, now: now, citizenships: ["US"]).allowance)

        #expect(allowance.usedDays == 7)
        #expect(allowance.remainingDays == 83)
        #expect(allowance.mustLeaveBy == startOfDay(2027, 1, 17))
        #expect(allowance.windowStart == startOfDay(2026, 4, 30))
        #expect(StayCalculator(days: days, now: now, calendar: calendar).currentStay(in: "DE")?.dayCount == 7)
    }

    // Reference: Paris springs forward on 2026-03-29 (a 23-hour day). ES 2026-03-27 ... 03-29, now
    // 2026-03-29 00:30 (the day in Paris, still the previous UTC day): 3 days, last day 2026-06-24.
    @Test
    func daylightSavingStartAndLateNightLocalTimeStayOnTheLocalDay() throws {
        let days = run(2026, 3, 27, through: (2026, 3, 29), "ES")
        let now = at(2026, 3, 29, hour: 0, minute: 30)
        let allowance = try #require(schengen(days, now: now, citizenships: ["US"]).allowance)

        #expect(allowance.usedDays == 3)
        #expect(allowance.mustLeaveBy == startOfDay(2026, 6, 24))
        #expect(StayCalculator(days: days, now: now, calendar: calendar).currentStay(in: "ES")?.startDay == stamp(2026, 3, 27))
    }

    // MARK: - Current stay

    @Test
    func aStayIsTheUnbrokenRunEndingToday() throws {
        let days = run(2026, 9, 20, through: (2026, 9, 30), "FR") + run(2026, 10, 1, through: (2026, 10, 12), "DE")
        let stay = try #require(StayCalculator(days: days, now: today, calendar: calendar).currentStay(in: "DE"))

        #expect(stay.countryCode == "DE")
        #expect(stay.startDay == stamp(2026, 10, 1))
        #expect(stay.startDate == startOfDay(2026, 10, 1))
        #expect(stay.dayCount == 12)
        #expect(stay.unrecordedGapDays == 0)
        #expect(StayCalculator(days: days, now: today, calendar: calendar).currentStay(in: "FR") == nil)
        #expect(StayCalculator(days: days, now: today, calendar: calendar).currentStay(in: "de")?.dayCount == 12)
        #expect(StayCalculator(days: [], now: today, calendar: calendar).currentStay(in: "DE") == nil)
    }

    @Test
    func aSingleUnrecordedDayIsBridgedAndReported() throws {
        let days = run(2026, 10, 1, through: (2026, 10, 5), "DE") + run(2026, 10, 7, through: (2026, 10, 12), "DE")
        let stay = try #require(StayCalculator(days: days, now: today, calendar: calendar).currentStay(in: "DE"))

        #expect(stay.startDay == stamp(2026, 10, 1))
        #expect(stay.dayCount == 12)
        #expect(stay.unrecordedGapDays == 1)
    }

    @Test
    func twoUnrecordedDaysInARowEndTheStay() throws {
        let days = run(2026, 10, 1, through: (2026, 10, 5), "DE") + run(2026, 10, 8, through: (2026, 10, 12), "DE")
        let stay = try #require(StayCalculator(days: days, now: today, calendar: calendar).currentStay(in: "DE"))

        #expect(stay.startDay == stamp(2026, 10, 8))
        #expect(stay.dayCount == 5)
        #expect(stay.unrecordedGapDays == 0)
    }

    @Test
    func aDayInAnotherCountryEndsTheStayEvenWithoutAGap() throws {
        let days = run(2026, 10, 1, through: (2026, 10, 5), "DE") + [visit(2026, 10, 6, "TR")] + run(2026, 10, 7, through: (2026, 10, 12), "DE")
        let stay = try #require(StayCalculator(days: days, now: today, calendar: calendar).currentStay(in: "DE"))

        #expect(stay.startDay == stamp(2026, 10, 7))
        #expect(stay.dayCount == 6)
    }

    @Test
    func todayMayBeTheOneUnrecordedDayButNotTwo() throws {
        let throughYesterday = run(2026, 10, 1, through: (2026, 10, 11), "DE")
        let stay = try #require(StayCalculator(days: throughYesterday, now: today, calendar: calendar).currentStay(in: "DE"))
        #expect(stay.dayCount == 12)
        #expect(stay.unrecordedGapDays == 1)

        let throughTwoDaysAgo = run(2026, 10, 1, through: (2026, 10, 10), "DE")
        #expect(StayCalculator(days: throughTwoDaysAgo, now: today, calendar: calendar).currentStay(in: "DE") == nil)
    }

    @Test
    func theLiveCountryStandsInForAnUnrecordedToday() throws {
        let throughYesterday = run(2026, 10, 1, through: (2026, 10, 11), "DE")
        let live = StayCalculator(days: throughYesterday, now: today, calendar: calendar, liveCountryCode: "de")
        let stay = try #require(live.currentStay(in: "DE"))
        #expect(stay.dayCount == 12)
        #expect(stay.unrecordedGapDays == 0)
        #expect(live.schengenStatus(citizenships: ["US"]).allowance?.usedDays == 12)
        #expect(live.taxYearDays(year: 2026).days(inCountry: "DE") == 12)

        // A record for today wins over the live country.
        let recorded = StayCalculator(days: throughYesterday + [visit(2026, 10, 12, "TR")], now: today, calendar: calendar, liveCountryCode: "DE")
        #expect(recorded.currentStay(in: "DE") == nil)
        #expect(recorded.currentStay(in: "TR")?.dayCount == 1)
    }

    // MARK: - Calendar year

    // Reference for 2026 on 2026-10-12 (285 days elapsed): ES 01-01 ... 06-30 (181), PT 07-01 ... 08-31 without
    // 08-15 (61), ES 09-01 ... 10-12 (42), plus PT also recorded on the border day 10-01. ES 223, PT 62,
    // unrecorded 1 (08-15), so the order is ES then PT.
    @Test
    func taxYearCountsDaysPerCountryAndUnrecordedDays() {
        let days = run(2026, 1, 1, through: (2026, 6, 30), "ES")
            + run(2026, 7, 1, through: (2026, 8, 14), "PT")
            + run(2026, 8, 16, through: (2026, 8, 31), "PT")
            + run(2026, 9, 1, through: (2026, 10, 12), "ES")
            + [visit(2026, 10, 1, "PT")]
        let summary = StayCalculator(days: days, now: today, calendar: calendar).taxYearDays(year: 2026)

        #expect(summary.year == 2026)
        #expect(summary.countries.map(\.countryCode) == ["ES", "PT"])
        #expect(summary.countries.map(\.days) == [223, 62])
        #expect(summary.unrecordedDays == 1)
        #expect(summary.days(inCountry: "es") == 223)
        #expect(summary.days(inCountry: "FR") == 0)
    }

    // Reference: 2025 on 2026-10-12 is over, so all 365 days count: FR on 12-30 and 12-31 only gives
    // FR 2 and 363 unrecorded. 2024 is a leap year with every one of its 366 days recorded in IT: IT 366,
    // 0 unrecorded. 2027 has not started: nothing, nothing unrecorded.
    @Test
    func taxYearHandlesPastLeapAndFutureYears() {
        let days = run(2024, 1, 1, through: (2024, 12, 31), "IT")
            + run(2025, 12, 30, through: (2025, 12, 31), "FR")
            + [visit(2026, 10, 12, "FR")]
        let calculator = StayCalculator(days: days, now: today, calendar: calendar)

        let leap = calculator.taxYearDays(year: 2024)
        #expect(leap.countries.map(\.days) == [366])
        #expect(leap.unrecordedDays == 0)

        let past = calculator.taxYearDays(year: 2025)
        #expect(past.countries.map(\.days) == [2])
        #expect(past.unrecordedDays == 363)

        let future = calculator.taxYearDays(year: 2027)
        #expect(future.countries.isEmpty)
        #expect(future.unrecordedDays == 0)

        // Today is day 285 of 2026 and the only recorded day.
        #expect(calculator.taxYearDays(year: 2026).unrecordedDays == 284)
    }

    @Test
    func taxYearGroupsCountriesWithoutACodeByNameAndBreaksTiesByName() {
        let days = [
            VisitedCountryDay(day: stamp(2026, 10, 10), country: "Atlantis", countryCode: nil, source: .deviceLocation, isInferred: false),
            VisitedCountryDay(day: stamp(2026, 10, 11), country: "atlantis", countryCode: nil, source: .deviceLocation, isInferred: false),
            visit(2026, 10, 12, "FR")
        ]
        let summary = StayCalculator(days: days, now: today, calendar: calendar).taxYearDays(year: 2026)

        #expect(summary.countries.count == 2)
        #expect(summary.countries.first?.days == 2)
        #expect(summary.countries.first?.countryCode == nil)
    }

    // MARK: - Allowance

    // Reference: MA 2026-07-22 ... 10-12 is 10 + 31 + 30 + 12 = 83 days of a 90-day allowance: 7 left, so
    // the last permitted day is 2026-10-19.
    @Test
    func allowanceCountsFromTheArrivalDay() throws {
        let days = run(2026, 7, 22, through: (2026, 10, 12), "MA")
        let status = try #require(allowance(days, now: today, country: "MA", allowanceDays: 90))

        #expect(status.usedDays == 83)
        #expect(status.remainingDays == 7)
        #expect(status.overstayDays == 0)
        #expect(status.lastPermittedDay == startOfDay(2026, 10, 19))
        #expect(status.stay.startDay == stamp(2026, 7, 22))
    }

    // Reference: arriving 2026-01-01 with 90 days, the 90th day is 2026-03-31; on 03-15 (day 74) 16 are left.
    @Test
    func theArrivalDayIsDayOneOfTheAllowance() throws {
        let days = run(2026, 1, 1, through: (2026, 3, 15), "MA")
        let status = try #require(allowance(days, now: at(2026, 3, 15), country: "MA", allowanceDays: 90))

        #expect(status.usedDays == 74)
        #expect(status.remainingDays == 16)
        #expect(status.lastPermittedDay == startOfDay(2026, 3, 31))
    }

    // Reference: MA 2026-07-14 ... 10-12 is 91 days: 1 day over a 90-day allowance, which ended 2026-10-11.
    @Test
    func anExceededAllowanceReportsTheOverstay() throws {
        let days = run(2026, 7, 14, through: (2026, 10, 12), "MA")
        let status = try #require(allowance(days, now: today, country: "MA", allowanceDays: 90))

        #expect(status.usedDays == 91)
        #expect(status.remainingDays == 0)
        #expect(status.overstayDays == 1)
        #expect(status.lastPermittedDay == startOfDay(2026, 10, 11))

        let lastDay = try #require(allowance(run(2026, 7, 15, through: (2026, 10, 12), "MA"), now: today, country: "MA", allowanceDays: 90))
        #expect(lastDay.remainingDays == 0)
        #expect(lastDay.overstayDays == 0)
        #expect(lastDay.lastPermittedDay == startOfDay(2026, 10, 12))
    }

    @Test
    func noAllowanceStatusWithoutAStayOrAPositiveAllowance() {
        let days = run(2026, 7, 22, through: (2026, 10, 12), "MA")

        #expect(allowance(days, now: today, country: "ES", allowanceDays: 90) == nil)
        #expect(allowance(days, now: today, country: "MA", allowanceDays: 0) == nil)
        #expect(allowance([], now: today, country: "MA", allowanceDays: 90) == nil)
    }

    // MARK: - Helpers

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }

    /// 2026-10-12 14:00 Paris.
    private var today: Date {
        at(2026, 10, 12)
    }

    private func at(_ year: Int, _ month: Int, _ day: Int, hour: Int = 14, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func startOfDay(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.startOfDay(for: at(year, month, day))
    }

    private func stamp(_ year: Int, _ month: Int, _ day: Int) -> VisitedCountryDayStamp {
        VisitedCountryDayStamp(year: year, month: month, day: day)
    }

    private func visit(_ year: Int, _ month: Int, _ day: Int, _ code: String, inferred: Bool = false, manual: Bool = false) -> VisitedCountryDay {
        VisitedCountryDay(
            day: stamp(year, month, day),
            country: code,
            countryCode: code,
            source: .deviceLocation,
            isInferred: inferred,
            isManual: manual
        )
    }

    /// One record per day from the start day through the end day, both included.
    private func run(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        through end: (Int, Int, Int),
        _ code: String
    ) -> [VisitedCountryDay] {
        let start = startOfDay(year, month, day)
        let last = startOfDay(end.0, end.1, end.2)
        let count = calendar.dateComponents([.day], from: start, to: last).day! + 1
        return (0..<count).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            return VisitedCountryDay(
                day: VisitedCountryDayStamp(date: date, calendar: calendar),
                country: code,
                countryCode: code,
                source: .deviceLocation,
                isInferred: false
            )
        }
    }

    private func schengen(_ days: [VisitedCountryDay], now: Date, citizenships: [String]) -> SchengenStatus {
        StayCalculator(days: days, now: now, calendar: calendar).schengenStatus(citizenships: citizenships)
    }

    private func allowance(_ days: [VisitedCountryDay], now: Date, country: String, allowanceDays: Int) -> StayAllowanceStatus? {
        StayCalculator(days: days, now: now, calendar: calendar).allowanceStatus(country: country, allowanceDays: allowanceDays)
    }
}
