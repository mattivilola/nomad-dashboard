import Foundation
import Testing
@testable import NomadCore

/// Reference dates (all checked on 2026-10-12):
/// - Umm al-Qura (Ramadan, Eid al-Fitr, Eid al-Adha): the AlAdhan.com tables
///   `https://aladhan.com/hijri-gregorian-calendar/<month>/<hijri year>`: 1 Ramadan 1447 = 18 Feb 2026 (30 days,
///   last day 19 Mar), 1 Shawwal 1447 = 20 Mar 2026, 10 Dhu al-Hijjah 1447 = 27 May 2026; 1 Ramadan 1448 =
///   8 Feb 2027 (29 days, last day 8 Mar), 1 Shawwal 1448 = 9 Mar 2027, 10 Dhu al-Hijjah 1448 = 16 May 2027.
///   National calendars follow local moon sighting and can be a day later: the Singapore MOM list has
///   Hari Raya Puasa on 21 Mar 2026 and 10 Mar 2027 and Hari Raya Haji on 27 May 2026 and 17 May 2027.
/// - Lunar New Year: Singapore MOM public holidays (17-18 Feb 2026, 6-7 Feb 2027,
///   `https://www.mom.gov.sg/employment-practices/public-holidays`), Hong Kong general holidays (17-19 Feb 2026;
///   6 Feb 2027, `https://www.gov.hk/en/about/abouthk/holiday/2026.htm` and `.../2027.htm`), Indonesian SKB 2027
///   (Imlek 6 Feb 2027). China's State Council notice on 2026 holidays has Spring Festival 15-23 Feb 2026.
/// - Easter: Indonesian SKB 2027 (Kebangkitan Yesus Kristus 28 Mar 2027) and Philippine Proclamation 1006 of 2025
///   (Maundy Thursday 2 Apr and Good Friday 3 Apr 2026, so Easter 5 Apr 2026). Other years (2024 31 Mar,
///   2025 20 Apr, 2028 16 Apr, 2029 1 Apr, 2030 21 Apr) are the well-known published Easter Sundays.
/// - Yom Kippur: publicholidays.com/yom-kippur and timeanddate.com/holidays/israel/yom-kippur (21 Sep 2026, 11 Oct 2027).
/// - Nyepi: SKB 3 Menteri on national holidays 2026 and 2027 (19 Mar 2026, 8 Mar 2027), `setneg.go.id`.
/// - Diwali (Lakshmi Puja): Drik Panchang (8 Nov 2026, 29 Oct 2027), Singapore MOM (8 Nov 2026, 28 Oct 2027).
struct LocalRhythmTests {
    // MARK: - Helpers

    private static func calendar(_ identifier: String = "UTC") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    private static func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0,
        in calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    private static func periods(
        _ country: String?,
        _ year: Int, _ month: Int, _ day: Int,
        lookahead: Int = 14,
        zone: String = "UTC"
    ) -> [LocalRhythmPeriod] {
        let calendar = calendar(zone)
        return LocalRhythmCalendar.periods(
            forCountryCode: country,
            around: date(year, month, day, 12, in: calendar),
            lookaheadDays: lookahead,
            calendar: calendar
        )
    }

    private static func period(_ kind: LocalRhythmKind, in periods: [LocalRhythmPeriod]) -> LocalRhythmPeriod? {
        periods.first { $0.kind == kind }
    }

    /// Expects `period` to span `from` 00:00:00 through `to` 23:59:59 in `zone`.
    private func expectSpan(
        _ period: LocalRhythmPeriod?,
        from: (Int, Int, Int),
        to: (Int, Int, Int),
        zone: String = "UTC",
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard let period else {
            Issue.record("Expected a period", sourceLocation: sourceLocation)
            return
        }
        let calendar = Self.calendar(zone)
        #expect(period.start == Self.date(from.0, from.1, from.2, in: calendar), sourceLocation: sourceLocation)
        #expect(period.end == Self.date(to.0, to.1, to.2, 23, 59, 59, in: calendar), sourceLocation: sourceLocation)
    }

    // MARK: - Ramadan and the Eids

    @Test
    func ramadanDates() {
        expectSpan(Self.period(.ramadan, in: Self.periods("SA", 2026, 3, 1)), from: (2026, 2, 18), to: (2026, 3, 19))
        expectSpan(Self.period(.ramadan, in: Self.periods("SA", 2027, 2, 20)), from: (2027, 2, 8), to: (2027, 3, 8))
    }

    @Test
    func eidAlFitrDates() {
        expectSpan(Self.period(.eidAlFitr, in: Self.periods("SA", 2026, 3, 21)), from: (2026, 3, 20), to: (2026, 3, 22))
        expectSpan(Self.period(.eidAlFitr, in: Self.periods("SA", 2027, 3, 10)), from: (2027, 3, 9), to: (2027, 3, 11))
    }

    @Test
    func eidAlAdhaDates() {
        expectSpan(Self.period(.eidAlAdha, in: Self.periods("SA", 2026, 5, 28)), from: (2026, 5, 27), to: (2026, 5, 30))
        expectSpan(Self.period(.eidAlAdha, in: Self.periods("SA", 2027, 5, 17)), from: (2027, 5, 16), to: (2027, 5, 19))
    }

    @Test
    func islamicPeriodsAreExpectedDates() {
        let periods = Self.periods("MA", 2027, 2, 20, lookahead: 120)
        for kind in [LocalRhythmKind.ramadan, .eidAlFitr, .eidAlAdha] {
            #expect(Self.period(kind, in: periods)?.confidence == .expected)
        }
    }

    @Test
    func ramadanStartingInTheNextHijriYearIsFound() {
        // 1 Ramadan 1449 falls in January 2028, in a different Hijri and Gregorian year than 2027.
        let ramadan = Self.period(.ramadan, in: Self.periods("SA", 2027, 12, 25, lookahead: 60))
        let start = ramadan?.start
        let parts = start.map { Self.calendar().dateComponents([.year, .month], from: $0) }
        #expect(parts?.year == 2028)
        #expect(parts?.month == 1)
    }

    @Test
    func ramadanGuidanceDiffersBetweenCountries() throws {
        let saudi = try #require(Self.period(.ramadan, in: Self.periods("SA", 2027, 2, 10)))
        let turkey = try #require(Self.period(.ramadan, in: Self.periods("TR", 2027, 2, 10)))
        let indonesia = try #require(Self.period(.ramadan, in: Self.periods("ID", 2027, 2, 10)))
        #expect(saudi.guidance.contains("Avoid eating, drinking or smoking in public"))
        #expect(turkey.guidance != saudi.guidance)
        #expect(turkey.guidance.contains("most restaurants and cafés in cities and tourist areas stay open"))
        #expect(indonesia.guidance != saudi.guidance)
        #expect(indonesia.guidance != turkey.guidance)
    }

    // MARK: - Lunar New Year

    @Test
    func lunarNewYearDatesInSingapore() {
        expectSpan(Self.period(.lunarNewYear, in: Self.periods("SG", 2026, 2, 10)), from: (2026, 2, 17), to: (2026, 2, 18))
        expectSpan(Self.period(.lunarNewYear, in: Self.periods("SG", 2027, 2, 1)), from: (2027, 2, 6), to: (2027, 2, 7))
    }

    @Test
    func lunarNewYearSpansPerCountry() {
        // New Year's Day 17 Feb 2026 and 6 Feb 2027; spans are offsets from it (see the file header).
        let expectations: [(String, (Int, Int, Int), (Int, Int, Int))] = [
            ("CN", (2026, 2, 16), (2026, 2, 23)),
            ("TW", (2026, 2, 15), (2026, 2, 19)),
            ("VN", (2026, 2, 16), (2026, 2, 20)),
            ("KR", (2026, 2, 16), (2026, 2, 18)),
            ("SG", (2026, 2, 17), (2026, 2, 18)),
            ("MY", (2026, 2, 17), (2026, 2, 18)),
            ("HK", (2026, 2, 17), (2026, 2, 19)),
            ("MO", (2026, 2, 17), (2026, 2, 19))
        ]
        for (country, from, to) in expectations {
            expectSpan(Self.period(.lunarNewYear, in: Self.periods(country, 2026, 2, 12)), from: from, to: to)
        }
    }

    @Test
    func lunarNewYear2027InChinaStartsOnTheEve() {
        expectSpan(Self.period(.lunarNewYear, in: Self.periods("CN", 2027, 2, 1)), from: (2027, 2, 5), to: (2027, 2, 12))
    }

    @Test
    func lunarNewYearNamesAreLocalised() {
        #expect(Self.period(.lunarNewYear, in: Self.periods("VN", 2026, 2, 12))?.name == "Tết (Lunar New Year)")
        #expect(Self.period(.lunarNewYear, in: Self.periods("KR", 2026, 2, 12))?.name == "Seollal (Lunar New Year)")
        #expect(Self.period(.lunarNewYear, in: Self.periods("CN", 2026, 2, 12))?.name == "Spring Festival (Lunar New Year)")
        #expect(Self.period(.lunarNewYear, in: Self.periods("SG", 2026, 2, 12))?.name == "Lunar New Year")
    }

    @Test
    func lunarNewYearInJanuaryOfTheNextYearIsFound() {
        // Lunar New Year 2028 is 26 Jan, so the eve (25 Jan) is within 14 days of 20 Jan but the year differs from 2027.
        let found = Self.period(.lunarNewYear, in: Self.periods("CN", 2028, 1, 20))
        expectSpan(found, from: (2028, 1, 25), to: (2028, 2, 1))
        #expect(Self.period(.lunarNewYear, in: Self.periods("CN", 2027, 12, 20, lookahead: 60))?.start == found?.start)
    }

    // MARK: - Holy Week

    @Test
    func holyWeekDates() {
        expectSpan(Self.period(.holyWeek, in: Self.periods("ES", 2026, 3, 25)), from: (2026, 3, 29), to: (2026, 4, 5))
        expectSpan(Self.period(.holyWeek, in: Self.periods("ES", 2027, 3, 15)), from: (2027, 3, 21), to: (2027, 3, 28))
    }

    @Test(arguments: [
        (2024, 3, 31), (2025, 4, 20), (2026, 4, 5), (2027, 3, 28), (2028, 4, 16), (2029, 4, 1), (2030, 4, 21)
    ])
    func easterSundayIsTheLastDayOfHolyWeek(year: Int, month: Int, day: Int) {
        let calendar = Self.calendar()
        let holyWeek = Self.period(.holyWeek, in: Self.periods("MT", year, month, day, lookahead: 0))
        #expect(holyWeek?.end == Self.date(year, month, day, 23, 59, 59, in: calendar))
        let weekday = holyWeek.map { calendar.component(.weekday, from: $0.start) }
        #expect(weekday == 1, "Palm Sunday is a Sunday")
    }

    @Test
    func holyWeekNamesAndGuidance() throws {
        #expect(Self.period(.holyWeek, in: Self.periods("ES", 2027, 3, 21))?.name == "Semana Santa (Holy Week)")
        #expect(Self.period(.holyWeek, in: Self.periods("IT", 2027, 3, 21))?.name == "Settimana Santa (Holy Week)")
        let mexico = try #require(Self.period(.holyWeek, in: Self.periods("MX", 2027, 3, 21)))
        let spain = try #require(Self.period(.holyWeek, in: Self.periods("ES", 2027, 3, 21)))
        #expect(mexico.guidance != spain.guidance)
    }

    // MARK: - Yom Kippur and fixed dates

    @Test
    func yomKippurDates() {
        expectSpan(Self.period(.yomKippur, in: Self.periods("IL", 2026, 9, 20)), from: (2026, 9, 21), to: (2026, 9, 21))
        expectSpan(Self.period(.yomKippur, in: Self.periods("IL", 2027, 10, 11)), from: (2027, 10, 11), to: (2027, 10, 11))
        #expect(Self.period(.yomKippur, in: Self.periods("IL", 2027, 10, 1))?.guidance.hasPrefix("Starts the evening before.") == true)
    }

    @Test
    func fixedDates() {
        for year in [2026, 2027] {
            expectSpan(Self.period(.songkran, in: Self.periods("TH", year, 4, 10)), from: (year, 4, 13), to: (year, 4, 15))
            expectSpan(Self.period(.goldenWeek, in: Self.periods("JP", year, 4, 20)), from: (year, 4, 29), to: (year, 5, 5))
            expectSpan(Self.period(.ferragosto, in: Self.periods("IT", year, 8, 10)), from: (year, 8, 15), to: (year, 8, 15))
        }
        #expect(Self.period(.songkran, in: Self.periods("TH", 2026, 4, 10))?.confidence == .fixed)
        #expect(Self.period(.ferragosto, in: Self.periods("IT", 2026, 8, 10))?.guidance.contains("mid-August") == true)
    }

    @Test
    func goldenWeekIsActiveWhileItRuns() {
        let periods = Self.periods("JP", 2026, 5, 3, lookahead: 0)
        expectSpan(Self.period(.goldenWeek, in: periods), from: (2026, 4, 29), to: (2026, 5, 5))
    }

    // MARK: - Tables: Nyepi and Diwali

    @Test
    func nyepiDates() {
        expectSpan(Self.period(.nyepi, in: Self.periods("ID", 2026, 3, 10)), from: (2026, 3, 19), to: (2026, 3, 19))
        expectSpan(Self.period(.nyepi, in: Self.periods("ID", 2027, 3, 1)), from: (2027, 3, 8), to: (2027, 3, 8))
        #expect(Self.period(.nyepi, in: Self.periods("ID", 2027, 3, 1))?.guidance.contains("airport") == true)
    }

    @Test
    func diwaliDatesInIndia() {
        // Lakshmi Puja 8 Nov 2026 and 29 Oct 2027; the period runs from the day before to the day after.
        expectSpan(Self.period(.diwali, in: Self.periods("IN", 2026, 11, 1)), from: (2026, 11, 7), to: (2026, 11, 9))
        expectSpan(Self.period(.diwali, in: Self.periods("IN", 2027, 10, 20)), from: (2027, 10, 28), to: (2027, 10, 30))
        #expect(Self.period(.diwali, in: Self.periods("IN", 2026, 11, 1))?.confidence == .expected)
    }

    @Test
    func diwaliDatesInOtherCountries() {
        expectSpan(Self.period(.diwali, in: Self.periods("SG", 2026, 11, 1)), from: (2026, 11, 8), to: (2026, 11, 8))
        expectSpan(Self.period(.diwali, in: Self.periods("SG", 2027, 10, 20)), from: (2027, 10, 28), to: (2027, 10, 28))
        expectSpan(Self.period(.diwali, in: Self.periods("MY", 2026, 11, 1)), from: (2026, 11, 8), to: (2026, 11, 8))
        expectSpan(Self.period(.diwali, in: Self.periods("NP", 2026, 11, 1)), from: (2026, 11, 8), to: (2026, 11, 10))
        #expect(Self.period(.diwali, in: Self.periods("NP", 2026, 11, 1))?.name == "Tihar (Festival of Lights)")
    }

    @Test
    func tableYearsOutsideTheTableReturnNothing() {
        // Nyepi has a decree for 2026 and 2027 only.
        for (year, month) in [(2025, 3), (2028, 3), (2029, 3), (2030, 3)] {
            let periods = Self.periods("ID", year, month, 1, lookahead: 60)
            #expect(Self.period(.nyepi, in: periods) == nil, "Nyepi \(year)")
        }
        // India is tabled for 2026-2032 only.
        for (year, month) in [(2025, 10), (2033, 10), (2033, 11)] {
            let periods = Self.periods("IN", year, month, 1, lookahead: 60)
            #expect(Self.period(.diwali, in: periods) == nil, "Diwali \(year)")
        }
        // Singapore 2028, Malaysia 2027 and Nepal 2028 are not tabled.
        #expect(Self.period(.diwali, in: Self.periods("SG", 2028, 10, 1, lookahead: 60)) == nil)
        #expect(Self.period(.diwali, in: Self.periods("MY", 2027, 10, 1, lookahead: 60)) == nil)
        #expect(Self.period(.diwali, in: Self.periods("NP", 2028, 10, 1, lookahead: 60)) == nil)
    }

    @Test
    func computedDatesAreNotLimitedByATable() {
        // Easter 2035 is 25 Mar; Holy Week is computed, not tabled.
        expectSpan(Self.period(.holyWeek, in: Self.periods("ES", 2035, 3, 15)), from: (2035, 3, 18), to: (2035, 3, 25))
    }

    // MARK: - Country applicability

    @Test
    func countriesWithoutAVisiblePeriodReturnNothing() {
        for country in ["FI", "DE", "US", "GB", "CH", "AZ", "UZ", "KZ"] {
            for month in 1...12 {
                #expect(Self.periods(country, 2027, month, 1, lookahead: 31).isEmpty, "\(country) month \(month)")
            }
        }
    }

    @Test
    func everyKindAppliesToItsDocumentedCountries() {
        let documented: [LocalRhythmKind: [String]] = [
            .ramadan: ["MA", "DZ", "TN", "LY", "EG", "JO", "SA", "AE", "QA", "KW", "BH", "OM", "TR", "ID", "MY", "BN", "PK", "BD", "SN", "MV", "IR", "IQ", "MR"],
            .eidAlFitr: ["MA", "SA", "AE", "TR", "ID", "MY", "PK", "BD"],
            .eidAlAdha: ["MA", "SA", "AE", "TR", "ID", "MY", "PK", "BD"],
            .lunarNewYear: ["CN", "HK", "MO", "TW", "SG", "MY", "VN", "KR"],
            .holyWeek: ["ES", "PT", "IT", "MT", "MX", "GT", "CO", "PE", "EC", "PH", "CR", "SV", "VE", "PY"],
            .yomKippur: ["IL"],
            .songkran: ["TH"],
            .goldenWeek: ["JP"],
            .nyepi: ["ID"],
            .diwali: ["IN", "NP", "SG", "MY"],
            .ferragosto: ["IT"]
        ]
        #expect(Set(documented.keys) == Set(LocalRhythmKind.allCases))

        // Query a day inside each kind's 2026 period, with a window wide enough to find it.
        let probes: [LocalRhythmKind: (Int, Int, Int)] = [
            .ramadan: (2026, 2, 25), .eidAlFitr: (2026, 3, 21), .eidAlAdha: (2026, 5, 28),
            .lunarNewYear: (2026, 2, 17), .holyWeek: (2026, 4, 2), .yomKippur: (2026, 9, 21),
            .songkran: (2026, 4, 14), .goldenWeek: (2026, 5, 1), .nyepi: (2026, 3, 19),
            .diwali: (2026, 11, 8), .ferragosto: (2026, 8, 15)
        ]
        for (kind, countries) in documented {
            let (year, month, day) = probes[kind]!
            for country in countries {
                let found = Self.period(kind, in: Self.periods(country, year, month, day, lookahead: 0))
                #expect(found != nil, "\(kind) in \(country)")
            }
        }
    }

    @Test
    func countryCodeIsNormalised() {
        let reference = Self.periods("SA", 2027, 2, 20, lookahead: 0)
        #expect(!reference.isEmpty)
        #expect(Self.periods(" sa\n", 2027, 2, 20, lookahead: 0) == reference)
        #expect(Self.periods("sA", 2027, 2, 20, lookahead: 0) == reference)
        #expect(reference.allSatisfy { $0.countryCode == "SA" })
    }

    @Test
    func missingOrUnknownCountryReturnsNothing() {
        #expect(Self.periods(nil, 2027, 2, 20).isEmpty)
        #expect(Self.periods("", 2027, 2, 20).isEmpty)
        #expect(Self.periods("   ", 2027, 2, 20).isEmpty)
        #expect(Self.periods("ZZ", 2027, 2, 20).isEmpty)
        #expect(Self.periods("SAU", 2027, 2, 20).isEmpty)
    }

    // MARK: - Lookahead window

    @Test
    func upcomingPeriodWithinTheLookaheadIsReturned() {
        // Ramadan 2027 starts at 00:00 on 8 Feb. The helper asks at noon, so the window ends at noon.
        #expect(Self.period(.ramadan, in: Self.periods("SA", 2027, 1, 24, lookahead: 14)) == nil)
        #expect(Self.period(.ramadan, in: Self.periods("SA", 2027, 1, 25, lookahead: 14)) != nil)
        #expect(Self.period(.ramadan, in: Self.periods("SA", 2027, 1, 23, lookahead: 15)) == nil)
        #expect(Self.period(.ramadan, in: Self.periods("SA", 2027, 1, 24, lookahead: 15)) != nil)
        #expect(Self.period(.ramadan, in: Self.periods("SA", 2027, 1, 1, lookahead: 14)) == nil)
    }

    @Test
    func lookaheadBoundaryIsExactToTheSecond() {
        let calendar = Self.calendar()
        let start = Self.date(2027, 2, 8, in: calendar)
        let exactly = LocalRhythmCalendar.periods(
            forCountryCode: "SA", around: calendar.date(byAdding: .day, value: -14, to: start)!,
            lookaheadDays: 14, calendar: calendar
        )
        let oneSecondEarlier = LocalRhythmCalendar.periods(
            forCountryCode: "SA", around: calendar.date(byAdding: .day, value: -14, to: start)!.addingTimeInterval(-1),
            lookaheadDays: 14, calendar: calendar
        )
        #expect(Self.period(.ramadan, in: exactly) != nil)
        #expect(Self.period(.ramadan, in: oneSecondEarlier) == nil)
    }

    @Test
    func activePeriodIsReturnedWithoutLookahead() {
        let periods = Self.periods("SA", 2027, 2, 20, lookahead: 0)
        expectSpan(Self.period(.ramadan, in: periods), from: (2027, 2, 8), to: (2027, 3, 8))
        #expect(periods.count == 1)
    }

    @Test
    func periodAlreadyActiveStaysInTheListUntilItsLastSecond() {
        let calendar = Self.calendar()
        let lastSecond = Self.date(2027, 3, 8, 23, 59, 59, in: calendar)
        let during = LocalRhythmCalendar.periods(forCountryCode: "SA", around: lastSecond, lookaheadDays: 0, calendar: calendar)
        let after = LocalRhythmCalendar.periods(forCountryCode: "SA", around: lastSecond.addingTimeInterval(1), lookaheadDays: 0, calendar: calendar)
        #expect(during.map(\.kind) == [.ramadan])
        #expect(after.map(\.kind) == [.eidAlFitr])
    }

    @Test
    func endedPeriodsAreNotReturned() {
        let periods = Self.periods("SA", 2027, 4, 1, lookahead: 7)
        #expect(Self.period(.ramadan, in: periods) == nil)
        #expect(Self.period(.eidAlFitr, in: periods) == nil)
    }

    @Test
    func negativeLookaheadBehavesLikeZero() {
        let negative = Self.periods("SA", 2027, 2, 1, lookahead: -5)
        #expect(negative == Self.periods("SA", 2027, 2, 1, lookahead: 0))
    }

    @Test
    func resultsAreSortedByStart() {
        // Mid-March 2027 in Indonesia: Nyepi (8 Mar), Ramadan (ended 8 Mar), Eid al-Fitr (9 Mar) all lie around the window.
        let periods = Self.periods("ID", 2027, 3, 8, lookahead: 60)
        #expect(periods.map(\.kind) == [.ramadan, .nyepi, .eidAlFitr])
        #expect(periods.map(\.start) == periods.map(\.start).sorted())
        #expect(Set(periods.map(\.id)).count == periods.count)
    }

    @Test
    func overlappingPeriodsAreAllReturned() {
        // Malaysia, 8 Mar 2027: Ramadan is on its last day and Eid al-Fitr starts tomorrow.
        let kinds = Self.periods("MY", 2027, 3, 8, lookahead: 14).map(\.kind)
        #expect(kinds.contains(.ramadan))
        #expect(kinds.contains(.eidAlFitr))
    }

    // MARK: - Time zones

    @Test
    func periodBoundariesFollowTheCalendarTimeZone() throws {
        let auckland = Self.calendar("Pacific/Auckland")
        let honolulu = Self.calendar("Pacific/Honolulu")
        let aucklandPeriod = try #require(Self.period(.ramadan, in: Self.periods("SA", 2027, 2, 10, zone: "Pacific/Auckland")))
        let honoluluPeriod = try #require(Self.period(.ramadan, in: Self.periods("SA", 2027, 2, 10, zone: "Pacific/Honolulu")))

        #expect(aucklandPeriod.start == Self.date(2027, 2, 8, in: auckland))
        #expect(honoluluPeriod.start == Self.date(2027, 2, 8, in: honolulu))
        // The same civil day starts 23 hours apart (UTC+13 in February against UTC-10).
        #expect(honoluluPeriod.start.timeIntervalSince(aucklandPeriod.start) == 23 * 3600)
        #expect(aucklandPeriod.end == Self.date(2027, 3, 8, 23, 59, 59, in: auckland))
        #expect(honoluluPeriod.end == Self.date(2027, 3, 8, 23, 59, 59, in: honolulu))
    }

    @Test
    func sameInstantCanBeActiveInOneZoneOnly() {
        // 8 Feb 2027 00:30 in Auckland is still 7 Feb in Honolulu (UTC-10).
        let auckland = Self.calendar("Pacific/Auckland")
        let instant = Self.date(2027, 2, 8, 0, 30, in: auckland)
        let inAuckland = LocalRhythmCalendar.periods(forCountryCode: "SA", around: instant, lookaheadDays: 0, calendar: auckland)
        let inHonolulu = LocalRhythmCalendar.periods(forCountryCode: "SA", around: instant, lookaheadDays: 0, calendar: Self.calendar("Pacific/Honolulu"))
        #expect(Self.period(.ramadan, in: inAuckland) != nil)
        #expect(Self.period(.ramadan, in: inHonolulu) == nil)
    }

    @Test
    func midnightIsTheExactStartOfTheFirstDay() {
        let tokyo = Self.calendar("Asia/Tokyo")
        let midnight = Self.date(2026, 4, 29, in: tokyo)
        let atMidnight = LocalRhythmCalendar.periods(forCountryCode: "JP", around: midnight, lookaheadDays: 0, calendar: tokyo)
        let aSecondBefore = LocalRhythmCalendar.periods(forCountryCode: "JP", around: midnight.addingTimeInterval(-1), lookaheadDays: 0, calendar: tokyo)
        #expect(atMidnight.map(\.kind) == [.goldenWeek])
        #expect(aSecondBefore.isEmpty)
    }

    @Test
    func daylightSavingTimeDoesNotShiftTheDays() throws {
        // Spanish clocks change on the first day of Holy Week 2026 (29 Mar).
        let madrid = Self.calendar("Europe/Madrid")
        let period = try #require(Self.period(.holyWeek, in: Self.periods("ES", 2026, 3, 25, zone: "Europe/Madrid")))
        #expect(period.start == Self.date(2026, 3, 29, in: madrid))
        #expect(period.end == Self.date(2026, 4, 5, 23, 59, 59, in: madrid))
        // 8 civil days, one of them 23 hours long.
        #expect(period.end.timeIntervalSince(period.start) == 8 * 86400 - 3600 - 1)
    }

    @Test
    func nonGregorianCallerCalendarStillUsesGregorianDays() {
        var hebrewCalendar = Calendar(identifier: .hebrew)
        hebrewCalendar.timeZone = TimeZone(identifier: "Asia/Jerusalem")!
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = hebrewCalendar.timeZone
        let now = Self.date(2027, 10, 1, 12, in: gregorian)
        let periods = LocalRhythmCalendar.periods(forCountryCode: "IL", around: now, lookaheadDays: 14, calendar: hebrewCalendar)
        expectSpan(Self.period(.yomKippur, in: periods), from: (2027, 10, 11), to: (2027, 10, 11), zone: "Asia/Jerusalem")
    }

    // MARK: - Content

    @Test
    func everyPeriodHasShortGuidance() {
        let countries = ["SA", "AE", "TR", "ID", "MY", "MA", "EG", "IL", "TH", "JP", "IT", "ES", "MX", "PH", "MT", "CN", "VN", "KR", "TW", "HK", "IN", "NP", "SG"]
        var kindsSeen: Set<LocalRhythmKind> = []
        for country in countries {
            for (month, day) in [(1, 15), (2, 10), (3, 10), (4, 10), (5, 20), (8, 10), (9, 15), (10, 20), (11, 5)] {
                for period in Self.periods(country, 2027, month, day, lookahead: 31) + Self.periods(country, 2026, month, day, lookahead: 31) {
                    kindsSeen.insert(period.kind)
                    #expect(!period.name.isEmpty)
                    #expect(!period.guidance.isEmpty)
                    #expect(period.guidance.count <= 330, "\(period.kind) in \(country) is too long")
                    #expect(period.guidance.hasSuffix("."), "\(period.kind) in \(country)")
                    #expect(period.start < period.end)
                    #expect(period.countryCode == country)
                }
            }
        }
        #expect(kindsSeen == Set(LocalRhythmKind.allCases))
    }
}
