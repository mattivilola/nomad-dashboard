import Foundation

/// A trip the user plans: a destination country with start and end dates. Stored locally in
/// `AppSettings.plannedTrips` and never sent anywhere; only the destination country code is ever used to
/// look up public data (see `TripPreviewService`).
///
/// `startDate` and `endDate` stand for whole calendar days: the day of each in the calendar that reads
/// them, both included. Store the start of the day (or any moment of it); the time of day never matters.
public struct PlannedTrip: Codable, Equatable, Hashable, Sendable, Identifiable {
    /// The longest trip that is kept; a later end date is pulled back to this many days after the start.
    public static let maximumDurationDays = 731
    /// Trips that ended more than this many days ago are dropped when settings are sanitized.
    public static let retentionDays = 30
    /// The longest note that is kept.
    public static let maximumNoteLength = 200

    public let id: UUID
    /// Upper-case ISO 3166-1 alpha-2 code of the destination country.
    public var countryCode: String
    public var startDate: Date
    public var endDate: Date
    public var note: String?

    public init(id: UUID = UUID(), countryCode: String, startDate: Date, endDate: Date, note: String? = nil) {
        self.id = id
        self.countryCode = countryCode
        self.startDate = startDate
        self.endDate = endDate
        self.note = note
    }
}

// MARK: - Calendar days

public extension PlannedTrip {
    /// Start of the first day of the trip in `calendar`.
    func firstDay(calendar: Calendar) -> Date {
        calendar.startOfDay(for: startDate)
    }

    /// Start of the last day of the trip in `calendar`; never before `firstDay`.
    func lastDay(calendar: Calendar) -> Date {
        max(calendar.startOfDay(for: endDate), firstDay(calendar: calendar))
    }

    /// Calendar days of the trip, the first and the last included (a one-day trip is 1).
    func dayCount(calendar: Calendar) -> Int {
        Self.days(from: firstDay(calendar: calendar), to: lastDay(calendar: calendar), calendar: calendar) + 1
    }

    /// Nights between the first and the last day (a one-day trip is 0).
    func nightCount(calendar: Calendar) -> Int {
        dayCount(calendar: calendar) - 1
    }

    /// Whole days from the day of `now` to the first day: 0 on the day the trip starts, negative once it
    /// has started.
    func daysUntilStart(now: Date, calendar: Calendar) -> Int {
        Self.days(from: calendar.startOfDay(for: now), to: firstDay(calendar: calendar), calendar: calendar)
    }

    /// Whole days from the last day to the day of `now`: 0 on the last day, negative before it.
    func daysSinceEnd(now: Date, calendar: Calendar) -> Int {
        Self.days(from: lastDay(calendar: calendar), to: calendar.startOfDay(for: now), calendar: calendar)
    }

    /// Whether `now` falls on a day of the trip.
    func isOngoing(now: Date, calendar: Calendar) -> Bool {
        daysUntilStart(now: now, calendar: calendar) <= 0 && daysSinceEnd(now: now, calendar: calendar) <= 0
    }

    /// Whole calendar days from the start of one day to the start of another (DST-safe).
    internal static func days(from first: Date, to second: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: first), to: calendar.startOfDay(for: second)).day ?? 0
    }
}

// MARK: - Sanitizing

extension PlannedTrip {
    /// The trip with a normalized country code, an end not before the start and within
    /// `maximumDurationDays`, and a trimmed note; nil when the country code is not a letter pair.
    func sanitized(calendar: Calendar) -> PlannedTrip? {
        guard let code = AppSettings.normalizedCountryCode(countryCode) else {
            return nil
        }

        var end = max(endDate, startDate)
        if let limit = calendar.date(byAdding: .day, value: Self.maximumDurationDays - 1, to: startDate),
           calendar.startOfDay(for: end) > calendar.startOfDay(for: limit)
        {
            end = limit
        }

        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return PlannedTrip(
            id: id,
            countryCode: code,
            startDate: startDate,
            endDate: end,
            note: trimmedNote.flatMap { $0.isEmpty ? nil : String($0.prefix(Self.maximumNoteLength)) }
        )
    }

    /// Orders by start, then end, then id so the order is stable.
    static func isOrderedBefore(_ lhs: PlannedTrip, _ rhs: PlannedTrip) -> Bool {
        if lhs.startDate != rhs.startDate {
            return lhs.startDate < rhs.startDate
        }
        if lhs.endDate != rhs.endDate {
            return lhs.endDate < rhs.endDate
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

/// Decodes one element of an array without failing the whole array when the element is malformed.
struct LossyDecodable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? decoder.singleValueContainer().decode(Value.self)
    }
}
