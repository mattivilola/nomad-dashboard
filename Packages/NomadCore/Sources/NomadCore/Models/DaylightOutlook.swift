import Foundation

/// Today's light at a place, kept as plain dates so it can be stored, shown in a widget and
/// replayed later without the coordinates it was computed from.
///
/// It holds the sunrise and sunset of the day it was made for and the sunrise after that, which is
/// enough to answer "how long until sunset" or "when does it get light" at any moment of the
/// following day.
public struct DaylightOutlook: Codable, Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// The sun is up and sets at `sunset`.
        case daylight(sunset: Date)
        /// The sun is below the horizon. `sunrise` is the next sunrise when it is known.
        case dark(sunrise: Date?)
        /// The sun stays up all day.
        case midnightSun
        /// The sun stays down all day.
        case polarNight
    }

    public let sunrise: Date?
    public let sunset: Date?
    /// The sunrise of the day after the one this outlook was made for.
    public let nextSunrise: Date?
    public let isPolarDay: Bool
    public let isPolarNight: Bool
    /// Time zone of the place, so clock times read the way they do there.
    public let timeZoneIdentifier: String

    public init(
        sunrise: Date?,
        sunset: Date?,
        nextSunrise: Date?,
        isPolarDay: Bool,
        isPolarNight: Bool,
        timeZoneIdentifier: String
    ) {
        self.sunrise = sunrise
        self.sunset = sunset
        self.nextSunrise = nextSunrise
        self.isPolarDay = isPolarDay
        self.isPolarNight = isPolarNight
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    /// Computed on the Mac from the reference location: no network request.
    public init(reference: DaylightReference, now: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = reference.timeZone
        let today = reference.solarDay(on: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now).map(reference.solarDay(on:))

        self.init(
            sunrise: today.sunrise,
            sunset: today.sunset,
            nextSunrise: tomorrow?.sunrise,
            isPolarDay: today.isPolarDay,
            isPolarNight: today.isPolarNight,
            timeZoneIdentifier: reference.timeZone.identifier
        )
    }

    /// Nil without a location with coordinates.
    public init?(travelContext: TravelContextSnapshot, now: Date) {
        guard let reference = DaylightReference(travelContext: travelContext) else {
            return nil
        }
        self.init(reference: reference, now: now)
    }

    public var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }

    /// The moments at which `phase(at:)` changes, in order.
    public var transitions: [Date] {
        [sunrise, sunset, nextSunrise].compactMap(\.self).sorted()
    }

    /// What the light is doing at `date`, nil once `date` is past the sunrise this outlook knows about.
    public func phase(at date: Date) -> Phase? {
        if isPolarDay {
            return .midnightSun
        }
        if isPolarNight {
            return .polarNight
        }
        guard let sunrise, let sunset else {
            return nil
        }

        if date < sunrise {
            return .dark(sunrise: sunrise)
        }
        if date < sunset {
            return .daylight(sunset: sunset)
        }
        guard let nextSunrise else {
            return .dark(sunrise: nil)
        }
        return date < nextSunrise ? .dark(sunrise: nextSunrise) : nil
    }

    /// A short clock time (for example "18:12" or "6:12 PM") in the place's time zone.
    public func clockTime(_ date: Date, locale: Locale = .autoupdatingCurrent) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone))
    }

    /// Whether `date` falls on the same calendar day as `reference` in the place's time zone.
    public func isSameDay(_ date: Date, as reference: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.isDate(date, inSameDayAs: reference)
    }
}
