import Foundation
import NomadCore
import Testing
@testable import NomadUI

struct LocalRhythmPresentationTests {
    private typealias Support = StaysTestSupport

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        Support.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func period(
        start: Date,
        end: Date,
        name: String = "Ramadan",
        confidence: LocalRhythmDateConfidence = .expected
    ) -> LocalRhythmPeriod {
        LocalRhythmPeriod(
            kind: .ramadan,
            name: name,
            countryCode: "MA",
            start: start,
            end: end,
            confidence: confidence,
            guidance: "Shops and offices keep shorter hours."
        )
    }

    private func model(_ period: LocalRhythmPeriod, now: Date) -> LocalRhythmRowModel {
        LocalRhythmRowModel(period: period, now: now, calendar: Support.calendar, locale: Support.locale)
    }

    @Test
    func anExpectedPeriodShowsItsRangeAndTheShiftNote() {
        let row = model(
            period(start: date(2027, 2, 8), end: date(2027, 3, 9, hour: 23, minute: 59)),
            now: date(2027, 2, 20, hour: 12)
        )

        #expect(row.name == "Ramadan")
        #expect(row.dates == "8 Feb – 9 Mar (expected; may shift a day)")
        #expect(row.timing == "Now")
        #expect(row.guidance == "Shops and offices keep shorter hours.")
    }

    @Test
    func aComputedOrFixedPeriodHasNoShiftNote() {
        let row = model(
            period(start: date(2026, 8, 15), end: date(2026, 8, 15, hour: 23, minute: 59), name: "Ferragosto", confidence: .fixed),
            now: date(2026, 8, 14, hour: 12)
        )

        #expect(row.dates == "15 Aug")
        #expect(row.timing == "Tomorrow")
    }

    @Test
    func anUpcomingPeriodSaysHowFarAway() {
        let row = model(
            period(start: date(2027, 2, 8), end: date(2027, 3, 9, hour: 23, minute: 59)),
            now: date(2027, 2, 3, hour: 12)
        )

        #expect(row.timing == "In 5 days")
    }

    @Test
    func theNameDropsTheExplanatoryParenthetical() {
        let row = model(
            period(start: date(2027, 2, 6), end: date(2027, 2, 10), name: "Tết (Lunar New Year)"),
            now: date(2027, 2, 6, hour: 12)
        )

        #expect(row.name == "Tết")
    }

    @Test
    func rowsComeFromTheCurrentCountryCalendar() {
        // Holy Week 2026 runs 29 Mar - 5 Apr in Spain, the country of the preview snapshot.
        let rows = LocalRhythmRowModel.rows(
            snapshot: .preview,
            now: date(2026, 4, 1, hour: 12),
            calendar: Support.calendar,
            locale: Support.locale
        )

        #expect(rows.count == 1)
        #expect(rows.first?.dates.hasPrefix("29 Mar – 5 Apr") == true)
        #expect(rows.first?.timing == "Now")
    }

    @Test
    func noRowsOutsideThePeriodsAndLookAhead() {
        let rows = LocalRhythmRowModel.rows(
            snapshot: .preview,
            now: date(2026, 10, 12, hour: 12),
            calendar: Support.calendar,
            locale: Support.locale
        )

        #expect(rows.isEmpty)
    }

    @Test
    func theLocalInfoCardCarriesTheRhythmRows() {
        let settings = AppSettings(localInfoEnabled: true)
        let during = LocalInfoSectionPresentation(
            settings: settings,
            snapshot: .preview,
            locationStatusDetail: nil,
            now: date(2026, 4, 1, hour: 12),
            calendar: Support.calendar,
            locale: Support.locale
        )
        let outside = LocalInfoSectionPresentation(
            settings: settings,
            snapshot: .preview,
            locationStatusDetail: nil,
            now: date(2026, 10, 12, hour: 12),
            calendar: Support.calendar,
            locale: Support.locale
        )

        #expect(during.rhythm.count == 1)
        #expect(outside.rhythm.isEmpty)
    }

    @Test
    func aTurnedOffLocalInfoCardHasNoRhythm() {
        let off = LocalInfoSectionPresentation(
            settings: AppSettings(localInfoEnabled: false),
            snapshot: .preview,
            locationStatusDetail: nil,
            now: date(2026, 4, 1, hour: 12),
            calendar: Support.calendar,
            locale: Support.locale
        )

        #expect(off.rhythm.isEmpty)
    }
}
