import Foundation

// MARK: - Schengen area

/// The Schengen area and the 90/180-day rule for short stays of third-country nationals.
///
/// Source: European Commission, DG Migration and Home Affairs, "Schengen Area"
/// https://home-affairs.ec.europa.eu/policies/schengen/schengen-area_en
/// Verified 2026-10: 29 countries, 25 EU member states plus Iceland, Liechtenstein, Norway and
/// Switzerland.
/// - Bulgaria and Romania have been full members since 1 January 2025.
/// - Ireland is not a member (it opted out under the Schengen Protocol and keeps its own border policy).
/// - Cyprus is not a member yet: it takes part in Schengen cooperation, but the Council has not decided
///   to lift internal border checks (status per the Commission page above and its 2026 State of
///   Schengen report). Re-verify when the Council takes that decision.
///
/// Free movement (no 90/180 limit) applies to citizens of every EU member state, including Ireland and
/// Cyprus, to citizens of the EEA states Iceland, Liechtenstein and Norway, and to Swiss citizens.
/// - EEA = EU member states plus IS, LI, NO: https://www.efta.int/eea/eea-agreement (verified 2026-10).
/// - Swiss citizens (and EEA citizens) are "persons enjoying the right of free movement" under the
///   EU-Switzerland Agreement on the Free Movement of Persons and are outside the 90/180 rule per
///   Article 2(5) of the Schengen Borders Code, Regulation (EU) 2016/399:
///   https://eur-lex.europa.eu/eli/reg/2016/399/oj
public enum SchengenArea {
    /// EU member states that are not (yet) in the Schengen area.
    static let euStatesOutsideSchengen: [String] = ["CY", "IE"]

    /// EEA states outside the EU. All three are Schengen members and have free movement rights.
    public static let eeaStatesOutsideEU: [String] = ["IS", "LI", "NO"]

    /// Switzerland is neither EU nor EEA, but its citizens have free movement rights through bilateral
    /// agreements and Switzerland is a Schengen member.
    public static let switzerland = "CH"

    /// Schengen member states (ISO 3166-1 alpha-2), sorted: the EU states except Cyprus and Ireland,
    /// plus Iceland, Liechtenstein, Norway and Switzerland. Microstates with open borders (Monaco,
    /// San Marino, Vatican City, Andorra) are not members and are not counted.
    public static let memberStates: [String] = (
        DiplomaticMissionDirectory.euMemberStates.filter { euStatesOutsideSchengen.contains($0) == false }
            + eeaStatesOutsideEU
            + [switzerland]
    ).sorted()

    /// Citizens of these states (EU, EEA, Switzerland) have free movement and no 90/180-day limit.
    public static let freeMovementStates: [String] = (
        DiplomaticMissionDirectory.euMemberStates + eeaStatesOutsideEU + [switzerland]
    ).sorted()

    /// Days a third-country national may stay within any rolling window of `windowDays`.
    public static let maximumStayDays = 90
    public static let windowDays = 180

    public static func isMember(_ countryCode: String) -> Bool {
        memberStates.contains(countryCode.uppercased())
    }

    /// True when any of the citizenships has free movement rights, so the 90/180-day limit does not apply.
    public static func isExempt(citizenships: [String]) -> Bool {
        citizenships.contains { freeMovementStates.contains($0.trimmingCharacters(in: .whitespaces).uppercased()) }
    }
}

public struct SchengenAllowance: Equatable, Sendable {
    /// Days with Schengen presence in the rolling window, counting entry and exit days as full days.
    /// Can exceed `SchengenArea.maximumStayDays` after an overstay.
    public let usedDays: Int
    /// Days left of the 90-day allowance, never below zero.
    public let remainingDays: Int
    /// The last day (start of that day in the calculator's calendar) the user can still be in Schengen
    /// without exceeding 90 days, if they stay. Today when the allowance is used up or exceeded.
    /// Nil when the user is not in Schengen today.
    public let mustLeaveBy: Date?
    /// First day (start of day) of the rolling 180-day window that ends today.
    public let windowStart: Date

    public init(usedDays: Int, remainingDays: Int, mustLeaveBy: Date?, windowStart: Date) {
        self.usedDays = usedDays
        self.remainingDays = remainingDays
        self.mustLeaveBy = mustLeaveBy
        self.windowStart = windowStart
    }
}

public enum SchengenStatus: Equatable, Sendable {
    /// A citizenship with free movement rights: no limit applies.
    case exempt
    /// The 90/180 limit applies to the user's citizenships.
    case counting(SchengenAllowance)
    /// No citizenship is set, so it is unknown whether the limit applies. Counts are still provided.
    case unknownCitizenship(SchengenAllowance)

    public var allowance: SchengenAllowance? {
        switch self {
        case .exempt: nil
        case let .counting(allowance), let .unknownCitizenship(allowance): allowance
        }
    }
}

/// When a stay, Schengen or tax-residence count starts to warrant a warning. Shared by the heads-up items
/// and the Stays & Visas card so both turn sand and coral together.
public enum StayWarningThresholds {
    /// Days left at or below which a visa allowance or the Schengen limit is a caution (sand).
    public static let cautionDays = 14
    /// Days left at or below which it is an attention (coral). Overstays are always attention.
    public static let attentionDays = 3
    /// A tax-residence count is informational from this many days before the threshold.
    public static let taxResidenceInfoLeadDays = 30
    /// A tax-residence count is a caution (sand) from this many days before the threshold.
    public static let taxResidenceCautionLeadDays = 7
}

// MARK: - Result types

public struct CurrentStay: Equatable, Sendable {
    public let countryCode: String
    /// The first day of the stay, as recorded.
    public let startDay: VisitedCountryDayStamp
    /// Start of `startDay` in the calculator's calendar.
    public let startDate: Date
    /// Calendar days from `startDay` to today, both included. Unrecorded gap days inside the stay
    /// (see `unrecordedGapDays`) are counted: they are assumed to have been spent in the country.
    public let dayCount: Int
    /// Days inside the stay that have no record at all (a single missing day is bridged).
    public let unrecordedGapDays: Int

    public init(
        countryCode: String,
        startDay: VisitedCountryDayStamp,
        startDate: Date,
        dayCount: Int,
        unrecordedGapDays: Int
    ) {
        self.countryCode = countryCode
        self.startDay = startDay
        self.startDate = startDate
        self.dayCount = dayCount
        self.unrecordedGapDays = unrecordedGapDays
    }
}

public struct StayAllowanceStatus: Equatable, Sendable {
    public let countryCode: String
    public let allowanceDays: Int
    /// Days of the current stay so far, today included.
    public let usedDays: Int
    /// Days left, never below zero. Zero means today is the last permitted day, or the allowance is exceeded.
    public let remainingDays: Int
    /// How many days past the allowance the stay already is; zero within the allowance.
    public let overstayDays: Int
    /// The last permitted day (start of that day): in the past after an overstay.
    public let lastPermittedDay: Date
    public let stay: CurrentStay

    public init(
        countryCode: String,
        allowanceDays: Int,
        usedDays: Int,
        remainingDays: Int,
        overstayDays: Int,
        lastPermittedDay: Date,
        stay: CurrentStay
    ) {
        self.countryCode = countryCode
        self.allowanceDays = allowanceDays
        self.usedDays = usedDays
        self.remainingDays = remainingDays
        self.overstayDays = overstayDays
        self.lastPermittedDay = lastPermittedDay
        self.stay = stay
    }
}

public struct CountryDayCount: Equatable, Sendable, Identifiable {
    public let countryCode: String?
    public let country: String
    public let days: Int

    public init(countryCode: String?, country: String, days: Int) {
        self.countryCode = countryCode
        self.country = country
        self.days = days
    }

    public var id: String {
        countryCode ?? country
    }
}

public struct TaxYearDays: Equatable, Sendable {
    public let year: Int
    /// Days per country, most days first. A border day with two countries counts once for each.
    public let countries: [CountryDayCount]
    /// Days of the year so far (up to today) without any record.
    public let unrecordedDays: Int

    public init(year: Int, countries: [CountryDayCount], unrecordedDays: Int) {
        self.year = year
        self.countries = countries
        self.unrecordedDays = unrecordedDays
    }

    public func days(inCountry countryCode: String) -> Int {
        let code = countryCode.uppercased()
        return countries.first { $0.countryCode == code }?.days ?? 0
    }
}

// MARK: - Calculator

/// Stay arithmetic over the recorded country days: current stay streaks, the Schengen 90/180 rule,
/// calendar-year day counts for tax residence and per-country stay allowances.
///
/// Rules:
/// - Everything is counted in whole calendar days of `calendar`. "Today" is the day of `now`. Days are
///   compared by calendar-day distance, never by 24-hour spans, so daylight-saving changes do not
///   shift or lose a day. Days after today are ignored.
/// - A recorded day counts for every country recorded on it. The store keeps one country per day today,
///   but if a day holds two (a border crossing) both get the full day: entry and exit days count.
/// - Inferred and manual days count like observed ones.
/// - A stay is a run of days in one country. One unrecorded day between two days in the country is
///   bridged (the Mac was off for a day); two or more unrecorded days in a row end the stay, and so
///   does any day recorded only in other countries.
public struct StayCalculator: Sendable {
    private struct Entry {
        let offset: Int
        let day: VisitedCountryDay
    }

    let now: Date
    let calendar: Calendar
    private let entries: [Entry]
    /// Country codes recorded per day, keyed by days before today (0 is today). Read by the trip
    /// projections in `StayProjection.swift`.
    let presence: [Int: Set<String>]
    /// Days before today that have any record, including days without a country code.
    private let recordedOffsets: Set<Int>

    /// - Parameter liveCountryCode: the country the Mac is in right now. When today has no record yet
    ///   (the location has not been recorded since launch) today counts as spent there.
    public init(
        days: [VisitedCountryDay],
        now: Date,
        calendar: Calendar,
        liveCountryCode: String? = nil
    ) {
        self.now = now
        self.calendar = calendar

        let todayStart = calendar.startOfDay(for: now)
        var offsetsByStamp: [VisitedCountryDayStamp: Int] = [:]
        var entries: [Entry] = []
        for day in days {
            let offset = offsetsByStamp[day.day]
                ?? Self.dayOffset(of: day.day, todayStart: todayStart, calendar: calendar)
            guard let offset else {
                continue
            }
            offsetsByStamp[day.day] = offset
            if offset >= 0 {
                entries.append(Entry(offset: offset, day: day))
            }
        }

        if entries.contains(where: { $0.offset == 0 }) == false,
           let live = liveCountryCode?.trimmingCharacters(in: .whitespaces).uppercased(), live.isEmpty == false
        {
            let today = VisitedCountryDay(
                day: VisitedCountryDayStamp(date: now, calendar: calendar),
                country: live,
                countryCode: live,
                source: .deviceLocation,
                isInferred: true
            )
            entries.append(Entry(offset: 0, day: today))
        }

        var presence: [Int: Set<String>] = [:]
        var recordedOffsets: Set<Int> = []
        for entry in entries {
            recordedOffsets.insert(entry.offset)
            if let code = entry.day.countryCode {
                presence[entry.offset, default: []].insert(code)
            }
        }

        self.entries = entries
        self.presence = presence
        self.recordedOffsets = recordedOffsets
    }

    // MARK: Current stay

    /// The run of days ending today in `country` (ISO alpha-2), or nil when the user is not there.
    /// Today may be the one unrecorded day of the run.
    public func currentStay(in country: String) -> CurrentStay? {
        let code = country.trimmingCharacters(in: .whitespaces).uppercased()
        guard code.isEmpty == false, let oldest = recordedOffsets.max() else {
            return nil
        }

        var earliestPresent: Int?
        var consecutiveGap = 0
        for offset in 0...oldest {
            if presence[offset]?.contains(code) == true {
                earliestPresent = offset
                consecutiveGap = 0
            } else if recordedOffsets.contains(offset) {
                break
            } else {
                consecutiveGap += 1
                if consecutiveGap > 1 {
                    break
                }
            }
        }

        guard let earliestPresent else {
            return nil
        }

        let startDate = date(daysBeforeToday: earliestPresent)
        let gapDays = (0...earliestPresent).count { recordedOffsets.contains($0) == false }
        return CurrentStay(
            countryCode: code,
            startDay: VisitedCountryDayStamp(date: startDate, calendar: calendar),
            startDate: startDate,
            dayCount: earliestPresent + 1,
            unrecordedGapDays: gapDays
        )
    }

    /// The current stay in `country` measured against a user-set allowance of `allowanceDays`.
    /// The arrival day is day one, so an allowance of 90 days that began on 1 January ends on 31 March.
    public func allowanceStatus(country: String, allowanceDays: Int) -> StayAllowanceStatus? {
        guard allowanceDays > 0, let stay = currentStay(in: country) else {
            return nil
        }

        let remaining = allowanceDays - stay.dayCount
        return StayAllowanceStatus(
            countryCode: stay.countryCode,
            allowanceDays: allowanceDays,
            usedDays: stay.dayCount,
            remainingDays: max(remaining, 0),
            overstayDays: max(-remaining, 0),
            lastPermittedDay: date(daysBeforeToday: -remaining),
            stay: stay
        )
    }

    // MARK: Schengen

    public func schengenStatus(citizenships: [String]) -> SchengenStatus {
        if SchengenArea.isExempt(citizenships: citizenships) {
            return .exempt
        }

        let allowance = schengenAllowance()
        let hasCitizenship = citizenships.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty == false }
        return hasCitizenship ? .counting(allowance) : .unknownCitizenship(allowance)
    }

    private func schengenAllowance() -> SchengenAllowance {
        let windowDays = SchengenArea.windowDays
        let limit = SchengenArea.maximumStayDays
        let members = Set(SchengenArea.memberStates)

        // inSchengen[offset]: any Schengen presence that day; offset 0 is today, 179 the window start.
        var inSchengen = [Bool](repeating: false, count: windowDays)
        for offset in 0..<windowDays where presence[offset]?.isDisjoint(with: members) == false {
            inSchengen[offset] = true
        }
        let used = inSchengen.filter { $0 }.count

        var mustLeaveBy: Date?
        if inSchengen[0] {
            // Staying d more days: the window then starts d days later, so the d oldest window days
            // fall out and d new days are added. The stay is allowed while that total stays within 90.
            var prefix = [Int](repeating: 0, count: windowDays)
            var running = 0
            for offset in 0..<windowDays {
                running += inSchengen[offset] ? 1 : 0
                prefix[offset] = running
            }

            var lastAllowedExtraDays = 0
            for extraDays in 0..<windowDays {
                let total = prefix[windowDays - 1 - extraDays] + extraDays
                guard total <= limit else {
                    break
                }
                lastAllowedExtraDays = extraDays
            }
            mustLeaveBy = date(daysBeforeToday: -lastAllowedExtraDays)
        }

        return SchengenAllowance(
            usedDays: used,
            remainingDays: max(limit - used, 0),
            mustLeaveBy: mustLeaveBy,
            windowStart: date(daysBeforeToday: windowDays - 1)
        )
    }

    // MARK: Calendar year

    /// Days per country in calendar `year`, up to today, most days first. A day counts once per country
    /// even if it is recorded more than once.
    public func taxYearDays(year: Int) -> TaxYearDays {
        struct Tally {
            var countryCode: String?
            var country: String
            var days: Int
        }

        let yearEntries = entries.filter { $0.day.day.year == year }
        var tallies: [String: Tally] = [:]
        for (_, dayEntries) in Dictionary(grouping: yearEntries, by: \.day.day) {
            var seen = Set<String>()
            for entry in dayEntries {
                let key = entry.day.countryCode
                    ?? entry.day.country.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
                guard seen.insert(key).inserted else {
                    continue
                }
                var tally = tallies[key] ?? Tally(countryCode: entry.day.countryCode, country: entry.day.country, days: 0)
                tally.days += 1
                tallies[key] = tally
            }
        }

        let countries = tallies.values
            .map { CountryDayCount(countryCode: $0.countryCode, country: $0.country, days: $0.days) }
            .sorted { lhs, rhs in
                if lhs.days != rhs.days {
                    return lhs.days > rhs.days
                }
                return lhs.country.localizedCaseInsensitiveCompare(rhs.country) == .orderedAscending
            }

        let recordedDays = Set(yearEntries.map(\.day.day)).count
        return TaxYearDays(
            year: year,
            countries: countries,
            unrecordedDays: max(daysElapsed(inYear: year) - recordedDays, 0)
        )
    }

    /// Days of `year` up to and including today; the whole year once it is over, zero before it starts.
    private func daysElapsed(inYear year: Int) -> Int {
        let todayStart = calendar.startOfDay(for: now)
        guard let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1, hour: 12))
            .map(calendar.startOfDay(for:)),
            yearStart <= todayStart,
            let nextYearStart = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1, hour: 12))
            .map(calendar.startOfDay(for:))
        else {
            return 0
        }

        let end = min(todayStart, nextYearStart)
        let elapsed = calendar.dateComponents([.day], from: yearStart, to: end).day ?? 0
        // `end` is today (inclusive) in the current year, and the start of the next year once the year is over.
        return todayStart < nextYearStart ? elapsed + 1 : elapsed
    }

    // MARK: Calendar helpers

    /// Start of the day `offset` days before today (a negative offset is in the future).
    func date(daysBeforeToday offset: Int) -> Date {
        let shifted = calendar.date(byAdding: .day, value: -offset, to: now) ?? now
        return calendar.startOfDay(for: shifted)
    }

    private static func dayOffset(of stamp: VisitedCountryDayStamp, todayStart: Date, calendar: Calendar) -> Int? {
        guard let noon = calendar.date(from: DateComponents(
            year: stamp.year, month: stamp.month, day: stamp.day, hour: 12
        )) else {
            return nil
        }

        return calendar.dateComponents([.day], from: calendar.startOfDay(for: noon), to: todayStart).day
    }
}
