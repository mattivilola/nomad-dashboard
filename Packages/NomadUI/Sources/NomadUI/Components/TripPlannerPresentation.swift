import Foundation
import NomadCore

// What the Trip Planner window says about the list of planned trips, and the rules for adding, editing and
// deleting one. Planned trips and the home country are sensitive: everything here is computed locally and is
// never part of analytics.

/// Wording shared by the window and its tests.
enum TripPlannerText {
    static let windowTitle = "Trip Planner"
    static let subtitle = "Know what to expect before you go."
    static let addTripTitle = "Add trip"
    static let editTripTitle = "Edit trip"
    static let emptyTitle = "Plan your next trip"
    static let emptyMessage = "Add a destination and dates to see emergency numbers, your embassy, plugs, holidays and what the trip does to your Schengen days."
    static let footer = "Trips stay on this Mac. Holidays and advisories send only the destination country code."
    static let chooseCountryTitle = "Choose country…"
    static let destinationPickerTitle = "Choose destination"
    static let notePlaceholder = "Note (optional)"
    static let deleteTitle = "Delete trip…"
    static let deleteConfirmTitle = "Delete trip"
    static let saveTitle = "Save"
    static let cancelTitle = "Cancel"

    /// "You can plan up to 20 trips." Shown once the list is full.
    static var limitText: String {
        "You can plan up to \(AppSettings.maximumPlannedTrips) trips."
    }

    /// "Characters left in the note", for the counter under the field.
    static func noteCounter(_ note: String) -> String {
        "\(note.count)/\(PlannedTrip.maximumNoteLength)"
    }

    static func deleteConfirmationMessage(countryName: String) -> String {
        "The trip to \(countryName) is removed from this Mac."
    }

    static let retentionHint = "Trips that ended more than \(PlannedTrip.retentionDays) days ago are not kept."
}

/// When a trip is, in words: "in 12 days", "tomorrow", "today", "now" or "ended".
enum TripTiming {
    static func text(daysUntilStart: Int, daysSinceEnd: Int) -> String {
        if daysSinceEnd > 0 {
            return "ended"
        }

        switch daysUntilStart {
        case ..<0: return "now"
        case 0: return "today"
        case 1: return "tomorrow"
        default: return "in \(daysUntilStart) days"
        }
    }

    static func text(for trip: PlannedTrip, now: Date, calendar: Calendar) -> String {
        text(
            daysUntilStart: trip.daysUntilStart(now: now, calendar: calendar),
            daysSinceEnd: trip.daysSinceEnd(now: now, calendar: calendar)
        )
    }
}

enum TripDateFormatting {
    /// "12–26 Jan 2027" in the locale's own style; a one-day trip is one date.
    static func range(of trip: PlannedTrip, calendar: Calendar, locale: Locale) -> String {
        let first = trip.firstDay(calendar: calendar)
        let last = trip.lastDay(calendar: calendar)
        let style = Date.IntervalFormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .day().month(.abbreviated).year()
        return (first..<last).formatted(style)
    }

    /// "14 days (13 nights)", or "1 day" for a trip within one day.
    static func length(dayCount: Int, nightCount: Int) -> String {
        guard dayCount > 1 else {
            return "1 day"
        }

        return "\(dayCount) days (\(nightCount) \(nightCount == 1 ? "night" : "nights"))"
    }
}

/// One row of the trip list.
struct TripListRow: Identifiable, Equatable {
    let id: UUID
    let countryName: String
    /// "12–26 Jan 2027".
    let dates: String
    /// "in 12 days", "tomorrow", "today", "now" or "ended".
    let timing: String
    let hasEnded: Bool
    let note: String?

    init(trip: PlannedTrip, now: Date, calendar: Calendar, locale: Locale) {
        id = trip.id
        countryName = CountryNames.displayName(forCode: trip.countryCode, locale: locale)
        dates = TripDateFormatting.range(of: trip, calendar: calendar, locale: locale)
        timing = TripTiming.text(for: trip, now: now, calendar: calendar)
        hasEnded = trip.daysSinceEnd(now: now, calendar: calendar) > 0
        note = trip.note
    }

    /// Spoken as one sentence: "Morocco, 12–26 Jan 2027, in 12 days".
    var accessibilityLabel: String {
        [countryName, dates, timing].joined(separator: ", ")
    }

    static func rows(for trips: [PlannedTrip], now: Date, calendar: Calendar, locale: Locale) -> [TripListRow] {
        trips.map { TripListRow(trip: $0, now: now, calendar: calendar, locale: locale) }
    }
}

/// The trip a window opens first: the first one that has not ended, else the first.
enum TripSelection {
    static func initial(among trips: [PlannedTrip], now: Date, calendar: Calendar) -> UUID? {
        (trips.first { $0.daysSinceEnd(now: now, calendar: calendar) <= 0 } ?? trips.first)?.id
    }

    /// Keeps `current` while it still exists, else falls back to the initial choice.
    static func reconciled(_ current: UUID?, among trips: [PlannedTrip], now: Date, calendar: Calendar) -> UUID? {
        if let current, trips.contains(where: { $0.id == current }) {
            return current
        }

        return initial(among: trips, now: now, calendar: calendar)
    }
}

// MARK: - Editing

/// The values in the add/edit sheet.
struct TripDraft: Equatable {
    /// The id of the trip being edited; nil for a new trip.
    var id: UUID?
    var countryCode: String?
    var startDate: Date
    var endDate: Date
    var note: String

    /// A new trip a week from today that lasts a week.
    static func new(now: Date, calendar: Calendar) -> TripDraft {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: 7, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        return TripDraft(id: nil, countryCode: nil, startDate: start, endDate: end, note: "")
    }

    init(id: UUID?, countryCode: String?, startDate: Date, endDate: Date, note: String) {
        self.id = id
        self.countryCode = countryCode
        self.startDate = startDate
        self.endDate = endDate
        self.note = note
    }

    init(trip: PlannedTrip) {
        self.init(
            id: trip.id,
            countryCode: trip.countryCode,
            startDate: trip.startDate,
            endDate: trip.endDate,
            note: trip.note ?? ""
        )
    }

    var isNew: Bool {
        id == nil
    }

    /// Moves the start and pulls the end along when it would fall before it.
    mutating func setStart(_ date: Date) {
        startDate = date
        if endDate < date {
            endDate = date
        }
    }

    /// Keeps the note within `PlannedTrip.maximumNoteLength`.
    mutating func limitNote() {
        if note.count > PlannedTrip.maximumNoteLength {
            note = String(note.prefix(PlannedTrip.maximumNoteLength))
        }
    }

    /// The dates the end can be set to: from the start to the longest trip that is kept.
    func endDateRange(calendar: Calendar) -> ClosedRange<Date> {
        let longest = calendar.date(byAdding: .day, value: PlannedTrip.maximumDurationDays - 1, to: startDate) ?? startDate
        return startDate...longest
    }

    enum Problem: Equatable {
        case noCountry
        /// The trip ended so long ago that it would be dropped right away.
        case tooLongAgo
    }

    func problem(now: Date, calendar: Calendar) -> Problem? {
        guard let countryCode, countryCode.count == 2, countryCode.allSatisfy({ $0.isASCII && $0.isLetter }) else {
            return .noCountry
        }

        let ended = PlannedTrip(countryCode: countryCode, startDate: startDate, endDate: max(startDate, endDate))
        return ended.daysSinceEnd(now: now, calendar: calendar) > PlannedTrip.retentionDays ? .tooLongAgo : nil
    }

    /// The hint under the form when the draft cannot be saved, nil when it can (or needs no hint).
    func hint(now: Date, calendar: Calendar) -> String? {
        switch problem(now: now, calendar: calendar) {
        case .tooLongAgo: TripPlannerText.retentionHint
        case .noCountry, nil: nil
        }
    }

    func canSave(now: Date, calendar: Calendar) -> Bool {
        problem(now: now, calendar: calendar) == nil
    }

    /// The trip to store, nil while the draft has no country. The id of the edited trip is kept.
    func trip() -> PlannedTrip? {
        guard let countryCode else {
            return nil
        }

        return PlannedTrip(
            id: id ?? UUID(),
            countryCode: countryCode,
            startDate: startDate,
            endDate: max(startDate, endDate),
            note: note
        )
    }
}

/// Changes to the stored list. Every write goes through `AppSettings.sanitizedPlannedTrips`.
enum TripPlannerEditing {
    static func canAddTrip(to trips: [PlannedTrip]) -> Bool {
        trips.count < AppSettings.maximumPlannedTrips
    }

    /// `trips` with `trip` added, or replacing the trip with the same id, sanitized and sorted.
    static func saving(_ trip: PlannedTrip, into trips: [PlannedTrip], now: Date, calendar: Calendar) -> [PlannedTrip] {
        AppSettings.sanitizedPlannedTrips(
            trips.filter { $0.id != trip.id } + [trip],
            now: now,
            calendar: calendar
        )
    }

    static func deleting(_ id: UUID, from trips: [PlannedTrip], now: Date, calendar: Calendar) -> [PlannedTrip] {
        AppSettings.sanitizedPlannedTrips(trips.filter { $0.id != id }, now: now, calendar: calendar)
    }
}
