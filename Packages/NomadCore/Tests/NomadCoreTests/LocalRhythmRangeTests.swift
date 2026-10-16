import Foundation
@testable import NomadCore
import Testing

/// The date-range API used by trip previews. Reference dates are the ones documented in `LocalRhythmTests`:
/// Ramadan 1448 is 8 Feb - 8 Mar 2027, Eid al-Fitr starts 9 Mar 2027, Nyepi is 8 Mar 2027 and Lunar New Year
/// is 6 Feb 2027.
struct LocalRhythmRangeTests {
    private func calendar(_ identifier: String = "UTC") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, zone: String = "UTC") -> Date {
        calendar(zone).date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func periods(
        _ country: String?,
        from first: Date,
        to last: Date,
        zone: String = "UTC"
    ) -> [LocalRhythmPeriod] {
        LocalRhythmCalendar.periods(forCountryCode: country, from: first, to: last, calendar: calendar(zone))
    }

    @Test
    func aTripCollectsEveryPeriodThatOverlapsItsDaysEarliestFirst() {
        // Indonesia 1-15 Mar 2027: Ramadan is in its last week, then Nyepi on its last day, then Eid al-Fitr.
        let found = periods("ID", from: date(2_027, 3, 1), to: date(2_027, 3, 15))

        #expect(found.map(\.kind) == [.ramadan, .nyepi, .eidAlFitr])
        #expect(found.allSatisfy { $0.countryCode == "ID" })
    }

    @Test
    func nyepiIsKeptForAnyIndonesianTripBecauseThereIsNoRegion() {
        let found = periods("id", from: date(2_027, 3, 8), to: date(2_027, 3, 8))

        #expect(found.map(\.kind).contains(.nyepi))
        #expect(found.first { $0.kind == .nyepi }?.guidance.contains("Bali") == true)
    }

    @Test
    func theFirstAndLastDaysOfTheTripAreIncluded() {
        // Ramadan is 8 Feb - 8 Mar 2027.
        #expect(periods("SA", from: date(2_027, 2, 1), to: date(2_027, 2, 8)).map(\.kind) == [.ramadan])
        #expect(periods("SA", from: date(2_027, 3, 8), to: date(2_027, 3, 8)).map(\.kind) == [.ramadan])
    }

    @Test
    func aPeriodThatEndedTheDayBeforeOrStartsTheDayAfterIsOutside() {
        #expect(periods("SA", from: date(2_027, 2, 1), to: date(2_027, 2, 7)).isEmpty)
        // The day after Ramadan is the first day of Eid al-Fitr.
        #expect(periods("SA", from: date(2_027, 3, 9), to: date(2_027, 3, 9)).map(\.kind) == [.eidAlFitr])
    }

    @Test
    func aPeriodThatSurroundsTheWholeTripCounts() {
        let found = periods("SA", from: date(2_027, 2, 20), to: date(2_027, 2, 22))

        #expect(found.map(\.kind) == [.ramadan])
    }

    @Test
    func theTimeOfDayOfTheEndsDoesNotMatter() {
        let late = periods("SA", from: date(2_027, 2, 1, 23, 59), to: date(2_027, 2, 8, 0, 1))
        let early = periods("SA", from: date(2_027, 2, 1, 0, 1), to: date(2_027, 2, 8, 23, 59))

        #expect(late == early)
        #expect(late.map(\.kind) == [.ramadan])
    }

    @Test
    func daysAreCivilDaysInTheCalendarsTimeZone() throws {
        let found = periods("ID", from: date(2_027, 3, 8, zone: "Asia/Jakarta"), to: date(2_027, 3, 8, zone: "Asia/Jakarta"), zone: "Asia/Jakarta")
        let nyepi = try #require(found.first { $0.kind == .nyepi })

        #expect(nyepi.start == date(2_027, 3, 8, zone: "Asia/Jakarta"))
        #expect(nyepi.end == date(2_027, 3, 9, zone: "Asia/Jakarta").addingTimeInterval(-1))
    }

    @Test
    func aTripOverTheNewYearFindsThePeriodsOfBothYears() {
        // Songkran is 13-15 Apr every year: none around the New Year, one in each April of a year-long trip.
        #expect(periods("TH", from: date(2_026, 12, 20), to: date(2_027, 1, 10)).isEmpty)
        #expect(periods("TH", from: date(2_026, 4, 14), to: date(2_027, 4, 14)).map(\.kind) == [.songkran, .songkran])
    }

    @Test
    func missingInvertedAndUnknownInputsGiveNothing() {
        #expect(periods(nil, from: date(2_027, 3, 1), to: date(2_027, 3, 15)).isEmpty)
        #expect(periods("  ", from: date(2_027, 3, 1), to: date(2_027, 3, 15)).isEmpty)
        #expect(periods("ZZ", from: date(2_027, 3, 1), to: date(2_027, 3, 15)).isEmpty)
        #expect(periods("SA", from: date(2_027, 3, 15), to: date(2_027, 3, 1)).isEmpty)
    }

    @Test
    func theRangeAgreesWithTheLookAheadWindowWhereTheyOverlap() {
        let calendar = calendar()
        let now = date(2_027, 2, 1, 12)
        let around = LocalRhythmCalendar.periods(forCountryCode: "MY", around: now, lookaheadDays: 10, calendar: calendar)
        let range = periods("MY", from: now, to: date(2_027, 2, 11))

        // Lunar New Year (6-7 Feb) and the start of Ramadan (8 Feb) are in both.
        #expect(range.map(\.kind) == around.map(\.kind))
        #expect(range.map(\.start) == around.map(\.start))
    }
}
