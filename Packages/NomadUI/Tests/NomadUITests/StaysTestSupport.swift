import Foundation
import NomadCore

/// Fixed clock and visited-day builders shared by the stay, arrival and weather presentation tests.
enum StaysTestSupport {
    /// 2026-10-12 12:00 UTC, a Monday.
    static let now = Date(timeIntervalSince1970: 1_791_806_400)
    static let locale = Locale(identifier: "en_GB")

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = locale
        return calendar
    }

    static func stamp(daysBeforeToday offset: Int) -> VisitedCountryDayStamp {
        VisitedCountryDayStamp(date: calendar.date(byAdding: .day, value: -offset, to: now)!, calendar: calendar)
    }

    static func day(_ offset: Int, _ code: String) -> VisitedCountryDay {
        VisitedCountryDay(
            day: stamp(daysBeforeToday: offset),
            country: code,
            countryCode: code,
            source: .deviceLocation,
            isInferred: false
        )
    }

    /// `count` consecutive days in `code` ending `endingOffset` days before today (0 = through today).
    static func run(_ count: Int, _ code: String, endingOffset: Int = 0) -> [VisitedCountryDay] {
        (0..<count).map { day(endingOffset + $0, code) }
    }
}
