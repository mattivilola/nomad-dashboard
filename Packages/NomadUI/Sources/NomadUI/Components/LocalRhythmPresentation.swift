import Foundation
import NomadCore

/// One cultural or religious period of the current country in the Local Info card: Ramadan, Lunar New Year,
/// Holy Week. These change opening hours, traffic and prices, so the card names the dates and what to expect.
struct LocalRhythmRowModel: Identifiable, Equatable {
    /// How far ahead a period is listed, as for the heads-up item.
    static let lookAheadDays = 14
    static let sectionTitle = "Local rhythm"
    static let shiftNote = "expected; may shift a day"

    let id: String
    let name: String
    /// "Now", "Tomorrow" or "In 5 days".
    let timing: String
    /// "8 Feb – 9 Mar (expected; may shift a day)".
    let dates: String
    let guidance: String

    init(period: LocalRhythmPeriod, now: Date, calendar: Calendar, locale: Locale) {
        id = period.id
        name = period.shortName
        guidance = period.guidance

        let startsIn = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: period.start)
        ).day ?? 0
        timing = switch startsIn {
        case ...0: "Now"
        case 1: "Tomorrow"
        default: "In \(startsIn) days"
        }

        let dayStyle = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .day().month(.abbreviated)
        let first = period.start.formatted(dayStyle)
        let last = period.end.formatted(dayStyle)
        let range = first == last ? first : "\(first) – \(last)"
        dates = period.confidence == .expected ? "\(range) (\(Self.shiftNote))" : range
    }

    /// The periods that are on or start within `lookAheadDays` for the current country. Nyepi only shows
    /// for a location in Bali (or one whose region is unknown).
    static func rows(
        snapshot: DashboardSnapshot,
        now: Date,
        calendar: Calendar,
        locale: Locale
    ) -> [LocalRhythmRowModel] {
        LocalRhythmCalendar.periods(
            forCountryCode: snapshot.currentCountryCode,
            travelContext: snapshot.travelContext,
            around: now,
            lookaheadDays: lookAheadDays,
            calendar: calendar
        )
        .map { LocalRhythmRowModel(period: $0, now: now, calendar: calendar, locale: locale) }
    }
}
