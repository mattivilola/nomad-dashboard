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

extension StaysTestSupport {
    /// A day of `calendar` at noon.
    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    /// A trip from one day to another, both included.
    static func trip(
        _ code: String = "MA",
        from start: (Int, Int, Int),
        to end: (Int, Int, Int),
        note: String? = nil,
        id: UUID = UUID()
    ) -> PlannedTrip {
        PlannedTrip(
            id: id,
            countryCode: code,
            startDate: date(start.0, start.1, start.2),
            endDate: date(end.0, end.1, end.2),
            note: note
        )
    }

    /// Settings with the trips stored as given. The initializer would drop trips that ended long before the
    /// real current date, which makes tests that use fixed dates age badly.
    static func settings(trips: [PlannedTrip], citizenships: [String] = ["FI"], home: String? = nil) -> AppSettings {
        var settings = AppSettings(citizenshipCountryCodes: citizenships, homeCountryCode: home)
        settings.plannedTrips = trips
        return settings
    }
}
