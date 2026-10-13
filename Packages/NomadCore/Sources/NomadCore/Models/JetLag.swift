import Foundation

// Jet-lag nudge: notices when the Mac's local time zone moved several hours and turns that into a rough
// recovery length and general light-timing guidance. Everything is computed on the Mac from a short local
// history of time zone changes (`TimeZoneShiftStore`), and sent nowhere.
//
// Sources for the guidance (general information, not medical advice):
//  - CDC Yellow Book, "Jet Lag Disorder" (https://www.cdc.gov/yellow-book/hcp/travel-air-sea/jet-lag-disorder.html):
//    * Eastward travel needs the body clock shifted earlier. Bright light in the morning (after the
//      circadian nadir, about 2-4 h before the habitual wake time) advances it; evening light pushes it
//      later and should be avoided.
//    * Westward travel needs the clock shifted later. Evening light helps; early-morning bright light
//      should be avoided.
//    * The body clock adapts by about 1 h per day after eastward travel and about 1.5 h per day after
//      westward travel, so westward is generally easier.
//    * Exact light (and melatonin) timing depends on direction and on the number of zones crossed; the
//      chapter recommends a jet lag calculator for individual plans. The wording here therefore stays
//      general and says nothing about crossing very many zones.

// MARK: - History

/// The local time zone the Mac was in from `date` on, with its UTC offset then. The offset is stored, not
/// derived later, because it is the offset the traveller's body clock was living in at that time.
public struct TimeZoneShiftRecord: Codable, Equatable, Sendable {
    public let date: Date
    /// IANA identifier, for example "Asia/Bangkok".
    public let identifier: String
    /// UTC offset in seconds at `date`.
    public let offsetSeconds: Int

    public init(date: Date, identifier: String, offsetSeconds: Int) {
        self.date = date
        self.identifier = identifier
        self.offsetSeconds = offsetSeconds
    }

    /// The record for `timeZone` as it is at `date`.
    public init(date: Date, timeZone: TimeZone) {
        self.init(date: date, identifier: timeZone.identifier, offsetSeconds: timeZone.secondsFromGMT(for: date))
    }
}

public extension TravelContextSnapshot {
    /// The time zone the traveller's clocks follow: the device location's own zone, else the snapshot's
    /// time zone. The IP location is not used, as a VPN would make it wrong. Nil when neither identifier is
    /// known to the system.
    var effectiveTimeZone: TimeZone? {
        [deviceLocation?.timeZone, timeZoneIdentifier]
            .lazy
            .compactMap { $0.flatMap(TimeZone.init(identifier:)) }
            .first
    }
}

// MARK: - Assessment

/// A recent shift of the local clock that is big enough to cause jet lag.
public struct JetLagAssessment: Equatable, Sendable {
    public enum Direction: String, Sendable {
        /// The local clock moved later relative to the body clock (the UTC offset grew).
        case east
        /// The local clock moved earlier (the UTC offset shrank).
        case west
    }

    public let direction: Direction
    /// The size of the shift in hours, always positive; half hours are possible (India, Nepal).
    public let shiftHours: Double
    /// When the shift began: the first change of the time zone that is part of it.
    public let shiftedAt: Date
    /// 1 on the day of `shiftedAt`, counted in calendar days.
    public let dayNumber: Int
    /// Rough days the body clock needs to adapt; at least 1 and at most `JetLagAdvisor.maximumAdjustmentDays`.
    public let adjustmentDays: Int

    public init(direction: Direction, shiftHours: Double, shiftedAt: Date, dayNumber: Int, adjustmentDays: Int) {
        self.direction = direction
        self.shiftHours = shiftHours
        self.shiftedAt = shiftedAt
        self.dayNumber = dayNumber
        self.adjustmentDays = adjustmentDays
    }
}

/// When to seek and when to avoid bright light after a shift. Times are for today in the time zone of the
/// location the daylight comes from. This is general guidance, not medical advice.
public struct JetLagGuidance: Equatable, Sendable {
    /// Eastward: the morning; westward: late afternoon until sunset. Nil without coordinates, or when the
    /// sun does not rise or set today.
    public let seekLight: DateInterval?
    /// Eastward only: avoid bright light from then on (evening).
    public let dimLightsAfter: Date?
    /// Westward only: avoid bright light before then (early morning).
    public let avoidLightBefore: Date?
    /// One line, for example "Get morning light 07:45–10:00 · dim lights after 21:00".
    public let text: String

    public init(seekLight: DateInterval?, dimLightsAfter: Date?, avoidLightBefore: Date?, text: String) {
        self.seekLight = seekLight
        self.dimLightsAfter = dimLightsAfter
        self.avoidLightBefore = avoidLightBefore
        self.text = text
    }
}

/// An assessment together with its guidance, as shown in the heads-up and the arrival briefing.
public struct JetLagSummary: Equatable, Sendable {
    public let assessment: JetLagAssessment
    public let guidance: JetLagGuidance

    public init(assessment: JetLagAssessment, guidance: JetLagGuidance) {
        self.assessment = assessment
        self.guidance = guidance
    }

    /// For example "Jet lag: day 2 of about 5".
    public var title: String {
        "Jet lag: day \(assessment.dayNumber) of about \(assessment.adjustmentDays)"
    }

    /// For example "Shifted 7 h east".
    public var shiftText: String {
        let hours = assessment.shiftHours
        let amount = hours.rounded() == hours ? "\(Int(hours))" : String(format: "%.1f", hours)
        return "Shifted \(amount) h \(assessment.direction.rawValue)"
    }
}

public enum JetLagAdvisor {
    /// The smallest shift that counts. A daylight saving change (1 h) is not a trip.
    public static let minimumShiftSeconds = 3 * 3_600
    /// Changes of the time zone that are at most this far apart are one shift: the offset before the
    /// first of them is compared with the offset now.
    public static let shiftWindow: TimeInterval = 72 * 3_600
    /// The body clock adapts about 1 h per day eastward and 1.5 h per day westward (CDC Yellow Book).
    static let eastwardHoursPerDay = 1.0
    static let westwardHoursPerDay = 1.5
    public static let maximumAdjustmentDays = 7
    /// The morning light window runs this long from sunrise ("about 2-3 h after").
    static let morningLightDuration: TimeInterval = 2.5 * 3_600
    /// The late-afternoon light window starts this long before sunset.
    static let afternoonLightDuration: TimeInterval = 2.5 * 3_600
    /// Dim the lights from this local hour: about two hours before a typical bedtime.
    static let dimLightsHour = 21
    /// "Very early morning" ends at this local hour: about an hour after a typical wake-up time.
    static let earlyMorningEndHour = 8

    /// The jet lag to talk about now, or nil.
    ///
    /// - The shift: the offset in force 72 h before the most recent change of offset, compared with the offset
    ///   now. So several steps within 72 h (a stopover, a connection) add up to one shift, while going out and
    ///   back cancels out. A change of identifier without a change of offset is not a change. When no record is
    ///   that old, the oldest record is the baseline.
    /// - Detected from 3 h up, in either direction (`minimumShiftSeconds`); the one-hour daylight saving
    ///   change never qualifies.
    /// - Duration: the nudge stays for the adjustment days and then ends (decision: it does not end after 72 h
    ///   with no further shift, because 72 h is only how changes are grouped; recovery from a big shift takes
    ///   longer, and the light advice stays valid until then). A new shift replaces it.
    ///
    /// - Parameter history: Records from `TimeZoneShiftStore`, in any order; the latest one is the zone now.
    public static func assessment(
        history: [TimeZoneShiftRecord],
        now: Date,
        calendar: Calendar = .current
    ) -> JetLagAssessment? {
        let records = history.filter { $0.date <= now }.sorted { $0.date < $1.date }
        guard records.count >= 2, let current = records.last,
              let lastChange = records.indices.last(where: { $0 > 0 && records[$0].offsetSeconds != records[$0 - 1].offsetSeconds })
        else {
            return nil
        }

        let anchor = records[lastChange].date.addingTimeInterval(-shiftWindow)
        let baseline = records.lastIndex { $0.date <= anchor } ?? 0
        let shiftSeconds = current.offsetSeconds - records[baseline].offsetSeconds
        guard abs(shiftSeconds) >= minimumShiftSeconds,
              let firstChange = ((baseline + 1)...lastChange).first(where: {
                  records[$0].offsetSeconds != records[$0 - 1].offsetSeconds
              })
        else {
            return nil
        }

        let direction: JetLagAssessment.Direction = shiftSeconds > 0 ? .east : .west
        let hours = Double(abs(shiftSeconds)) / 3_600
        let shiftedAt = records[firstChange].date
        let dayNumber = PlannedTrip.days(from: shiftedAt, to: now, calendar: calendar) + 1
        let adjustment = adjustmentDays(shiftHours: hours, direction: direction)
        guard dayNumber <= adjustment else {
            return nil
        }

        return JetLagAssessment(
            direction: direction,
            shiftHours: hours,
            shiftedAt: shiftedAt,
            dayNumber: dayNumber,
            adjustmentDays: adjustment
        )
    }

    /// About 1 day per hour eastward and 1 per 1.5 h westward, rounded, at least 1 and at most
    /// `maximumAdjustmentDays`.
    public static func adjustmentDays(shiftHours: Double, direction: JetLagAssessment.Direction) -> Int {
        let perDay = direction == .east ? eastwardHoursPerDay : westwardHoursPerDay
        return min(max(Int((shiftHours / perDay).rounded()), 1), maximumAdjustmentDays)
    }

    /// Light timing for today. Eastward: seek bright morning light from sunrise on and avoid bright light
    /// late in the evening. Westward: seek light in the late afternoon until sunset and avoid bright light
    /// very early in the morning. Without a `reference` (no coordinates) the advice carries no times.
    public static func guidance(
        for assessment: JetLagAssessment,
        reference: DaylightReference?,
        now: Date,
        locale: Locale = .autoupdatingCurrent
    ) -> JetLagGuidance {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = reference?.timeZone ?? .current
        func today(hour: Int) -> Date? {
            var parts = calendar.dateComponents([.year, .month, .day], from: now)
            parts.hour = hour
            return calendar.date(from: parts)
        }
        func clock(_ date: Date) -> String {
            reference?.clockTime(date, locale: locale)
                ?? date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: calendar.timeZone))
        }

        let day = reference?.solarDay(on: now)
        switch assessment.direction {
        case .east:
            let window = day?.sunrise.map { DateInterval(start: $0, duration: morningLightDuration) }
            let dim = today(hour: dimLightsHour)
            let seek = window.map { "Get morning light \(clock($0.start))–\(clock($0.end))" } ?? "Get bright morning light"
            let avoid = dim.map { "dim lights after \(clock($0))" } ?? "dim lights in the evening"
            return JetLagGuidance(seekLight: window, dimLightsAfter: dim, avoidLightBefore: nil, text: "\(seek) · \(avoid)")
        case .west:
            let window = day?.sunset.map { DateInterval(start: $0.addingTimeInterval(-afternoonLightDuration), end: $0) }
            let early = today(hour: earlyMorningEndHour)
            let seek = window.map { "Get afternoon light \(clock($0.start))–\(clock($0.end))" } ?? "Get light in the late afternoon"
            let avoid = early.map { "avoid bright light before \(clock($0))" } ?? "avoid very early morning light"
            return JetLagGuidance(seekLight: window, dimLightsAfter: nil, avoidLightBefore: early, text: "\(seek) · \(avoid)")
        }
    }

    /// The assessment for the shifts in `history` together with today's guidance for the place in
    /// `travelContext`, or nil when there is no jet lag to talk about.
    public static func summary(
        history: [TimeZoneShiftRecord],
        travelContext: TravelContextSnapshot,
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> JetLagSummary? {
        assessment(history: history, now: now, calendar: calendar).map {
            JetLagSummary(
                assessment: $0,
                guidance: guidance(
                    for: $0,
                    reference: DaylightReference(travelContext: travelContext),
                    now: now,
                    locale: locale
                )
            )
        }
    }
}
