import Foundation

// "What if" arithmetic for planned trips: how a trip changes the Schengen 90/180 count, a stay allowance
// and the days in a country this year, on top of what is already recorded.
//
// Rules, on top of the ones in `StayCalculator`:
// - A planned day counts from today on. Planned days before today are ignored: what was recorded is what
//   happened, and the plan does not fill in gaps or contradict it. A day can hold the recorded country and
//   the planned one (the day a trip starts, before the traveller has left): both count, as on a border day.
// - Planned trips are applied in order of their start date. Where trips overlap, a day belongs to the later
//   trip's country and counts once.
// - A trip is a run of whole calendar days, the first and the last included.

// MARK: - Result types

/// How a planned trip plays out against the Schengen 90/180 rule.
public enum SchengenProjection: Equatable, Sendable {
    /// A citizenship with free movement rights: no limit applies.
    case exempt
    /// The 90/180 limit applies to the user's citizenships.
    case counting(SchengenTripWindow)
    /// No citizenship is set, so it is unknown whether the limit applies. Counts are still provided.
    case unknownCitizenship(SchengenTripWindow)

    public var window: SchengenTripWindow? {
        switch self {
        case .exempt: nil
        case let .counting(window), let .unknownCitizenship(window): window
        }
    }
}

/// The Schengen counts around a trip. A day's count is the number of Schengen days in the 180 days ending
/// that day, that day included, with entry and exit days counted as full days.
public struct SchengenTripWindow: Equatable, Sendable {
    /// Days of the trip spent in Schengen, recorded or planned.
    public let tripSchengenDays: Int
    /// The count on the day before the trip starts: recorded days and earlier planned trips.
    public let usedDaysBeforeTrip: Int
    /// The highest count on any day of the trip spent in Schengen; zero when there is none.
    public let peakUsedDays: Int
    /// The first day (start of day) the count was at its highest.
    public let peakDay: Date?
    /// The first day of the trip (start of day) the count is above `SchengenArea.maximumStayDays`, if any.
    public let firstExceededOn: Date?

    public init(
        tripSchengenDays: Int,
        usedDaysBeforeTrip: Int,
        peakUsedDays: Int,
        peakDay: Date?,
        firstExceededOn: Date?
    ) {
        self.tripSchengenDays = tripSchengenDays
        self.usedDaysBeforeTrip = usedDaysBeforeTrip
        self.peakUsedDays = peakUsedDays
        self.peakDay = peakDay
        self.firstExceededOn = firstExceededOn
    }

    /// Days of the 90-day allowance left at the peak, never below zero.
    public var remainingDaysAtPeak: Int {
        max(SchengenArea.maximumStayDays - peakUsedDays, 0)
    }

    public var exceedsLimit: Bool {
        firstExceededOn != nil
    }
}

/// A trip measured against the days the user may stay per visit in the destination.
public struct StayAllowanceProjection: Equatable, Sendable {
    public let countryCode: String
    public let allowanceDays: Int
    /// Days of the trip, the first and the last included.
    public let tripDays: Int
    /// Days left of the allowance by the end of the trip, never below zero.
    public let remainingDays: Int
    /// How many days past the allowance the trip is; zero within it.
    public let overstayDays: Int
    /// The last permitted day (start of day), counting the first day of the trip as day one; before the
    /// end of the trip when the trip is too long.
    public let lastPermittedDay: Date

    public init(
        countryCode: String,
        allowanceDays: Int,
        tripDays: Int,
        remainingDays: Int,
        overstayDays: Int,
        lastPermittedDay: Date
    ) {
        self.countryCode = countryCode
        self.allowanceDays = allowanceDays
        self.tripDays = tripDays
        self.remainingDays = remainingDays
        self.overstayDays = overstayDays
        self.lastPermittedDay = lastPermittedDay
    }
}

/// Days in the destination in one calendar year, recorded plus planned, against the tax-residence
/// threshold. Not tax advice.
public struct TaxYearProjection: Equatable, Sendable {
    public let year: Int
    /// Days of the year already recorded in the destination, up to and including today.
    public let recordedDays: Int
    /// Planned days of the year in the destination that are not recorded yet.
    public let plannedDays: Int
    public let thresholdDays: Int
    /// The day (start of day) the count reaches the threshold, if it does.
    public let thresholdReachedOn: Date?

    public init(year: Int, recordedDays: Int, plannedDays: Int, thresholdDays: Int, thresholdReachedOn: Date?) {
        self.year = year
        self.recordedDays = recordedDays
        self.plannedDays = plannedDays
        self.thresholdDays = thresholdDays
        self.thresholdReachedOn = thresholdReachedOn
    }

    public var totalDays: Int {
        recordedDays + plannedDays
    }

    public var reachesThreshold: Bool {
        totalDays >= thresholdDays
    }
}

/// What a planned trip does to the user's stays. Each part is nil (or empty) when it does not apply.
public struct TripVisaOutlook: Equatable, Sendable {
    /// Nil when the Schengen counter is off, or the trip has no day in Schengen.
    public let schengen: SchengenProjection?
    /// Nil when the user set no allowance for the destination.
    public let allowance: StayAllowanceProjection?
    /// One entry per calendar year the trip touches, in order; empty when tax-residence days are off.
    public let taxYears: [TaxYearProjection]

    public init(schengen: SchengenProjection?, allowance: StayAllowanceProjection?, taxYears: [TaxYearProjection]) {
        self.schengen = schengen
        self.allowance = allowance
        self.taxYears = taxYears
    }

    public var isEmpty: Bool {
        schengen == nil && allowance == nil && taxYears.isEmpty
    }
}

// MARK: - Projection

public extension StayCalculator {
    /// How `trip` changes the user's stays when all `plannedTrips` happen, on top of the recorded days.
    /// `trip` is part of the plan even when `plannedTrips` does not list it. Which parts apply follows
    /// `settings` (citizenships, stay allowances, the Schengen and tax-residence switches and threshold).
    func outlook(for trip: PlannedTrip, among plannedTrips: [PlannedTrip], settings: AppSettings) -> TripVisaOutlook {
        let plan = TripPlan(calculator: self, trips: plannedTrips.contains { $0.id == trip.id } ? plannedTrips : plannedTrips + [trip])
        let range = plan.offsetRange(of: trip)
        let code = trip.countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        return TripVisaOutlook(
            schengen: settings.schengenCounterEnabled
                ? plan.schengenProjection(over: range, citizenships: settings.citizenshipCountryCodes)
                : nil,
            allowance: settings.stayAllowances[code].flatMap { allowanceDays in
                allowanceProjection(for: trip, countryCode: code, allowanceDays: allowanceDays)
            },
            taxYears: settings.taxResidenceDaysEnabled
                ? plan.taxYears(countryCode: code, over: range, thresholdDays: settings.taxResidenceThresholdDays)
                : []
        )
    }

    private func allowanceProjection(for trip: PlannedTrip, countryCode: String, allowanceDays: Int) -> StayAllowanceProjection? {
        guard allowanceDays > 0 else {
            return nil
        }

        let tripDays = trip.dayCount(calendar: calendar)
        let first = trip.firstDay(calendar: calendar)
        return StayAllowanceProjection(
            countryCode: countryCode,
            allowanceDays: allowanceDays,
            tripDays: tripDays,
            remainingDays: max(allowanceDays - tripDays, 0),
            overstayDays: max(tripDays - allowanceDays, 0),
            lastPermittedDay: calendar.date(byAdding: .day, value: allowanceDays - 1, to: first) ?? first
        )
    }
}

/// Recorded presence plus the planned trips, by day. Days are offsets before today, like in
/// `StayCalculator`: 0 is today and a future day is negative.
private struct TripPlan {
    private let calculator: StayCalculator
    /// The country of each planned day from today on.
    private let planned: [Int: String]
    private let schengenMembers = Set(SchengenArea.memberStates)

    init(calculator: StayCalculator, trips: [PlannedTrip]) {
        self.calculator = calculator

        var planned: [Int: String] = [:]
        for trip in trips.sorted(by: PlannedTrip.isOrderedBefore) {
            guard let code = AppSettings.normalizedCountryCode(trip.countryCode) else {
                continue
            }
            let range = Self.offsetRange(of: trip, calculator: calculator)
            for offset in range.lowerBound...range.upperBound where offset <= 0 {
                planned[offset] = code
            }
        }
        self.planned = planned
    }

    /// The offsets of the first and the last day of the trip; the first has the larger offset.
    func offsetRange(of trip: PlannedTrip) -> ClosedRange<Int> {
        Self.offsetRange(of: trip, calculator: calculator)
    }

    private static func offsetRange(of trip: PlannedTrip, calculator: StayCalculator) -> ClosedRange<Int> {
        let calendar = calculator.calendar
        let today = calendar.startOfDay(for: calculator.now)
        let first = PlannedTrip.days(from: trip.firstDay(calendar: calendar), to: today, calendar: calendar)
        let last = PlannedTrip.days(from: trip.lastDay(calendar: calendar), to: today, calendar: calendar)
        return min(last, first)...first
    }

    private func countries(onOffset offset: Int) -> Set<String> {
        var result = calculator.presence[offset] ?? []
        if let code = planned[offset] {
            result.insert(code)
        }
        return result
    }

    // MARK: Schengen

    func schengenProjection(over range: ClosedRange<Int>, citizenships: [String]) -> SchengenProjection? {
        let isExempt = SchengenArea.isExempt(citizenships: citizenships)
        let isInSchengen = schengenLookup()

        let tripDays = (range.lowerBound...range.upperBound).filter(isInSchengen)
        guard tripDays.isEmpty == false else {
            return nil
        }
        if isExempt {
            return .exempt
        }

        let window = SchengenArea.windowDays
        func used(endingAt offset: Int) -> Int {
            (offset..<(offset + window)).count(where: isInSchengen)
        }

        var peak = 0
        var peakOffset: Int?
        var firstExceeded: Int?
        // Chronological order: the earliest day has the largest offset.
        for offset in tripDays.reversed() {
            let count = used(endingAt: offset)
            if count > peak {
                peak = count
                peakOffset = offset
            }
            if firstExceeded == nil, count > SchengenArea.maximumStayDays {
                firstExceeded = offset
            }
        }

        let result = SchengenTripWindow(
            tripSchengenDays: tripDays.count,
            usedDaysBeforeTrip: used(endingAt: range.upperBound + 1),
            peakUsedDays: peak,
            peakDay: peakOffset.map(calculator.date(daysBeforeToday:)),
            firstExceededOn: firstExceeded.map(calculator.date(daysBeforeToday:))
        )
        let hasCitizenship = citizenships.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty == false }
        return hasCitizenship ? .counting(result) : .unknownCitizenship(result)
    }

    /// Whether the traveller is in Schengen on a day, with each answer remembered.
    private func schengenLookup() -> (Int) -> Bool {
        final class Memo: @unchecked Sendable {
            var values: [Int: Bool] = [:]
        }
        let memo = Memo()
        return { offset in
            if let known = memo.values[offset] {
                return known
            }
            let value = countries(onOffset: offset).isDisjoint(with: schengenMembers) == false
            memo.values[offset] = value
            return value
        }
    }

    // MARK: Tax years

    func taxYears(countryCode: String, over range: ClosedRange<Int>, thresholdDays: Int) -> [TaxYearProjection] {
        let calendar = calculator.calendar
        let firstYear = calendar.component(.year, from: calculator.date(daysBeforeToday: range.upperBound))
        let lastYear = calendar.component(.year, from: calculator.date(daysBeforeToday: range.lowerBound))
        let today = calendar.startOfDay(for: calculator.now)

        return (firstYear...lastYear).compactMap { year -> TaxYearProjection? in
            guard let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1, hour: 12)),
                  let yearEnd = calendar.date(from: DateComponents(year: year, month: 12, day: 31, hour: 12))
            else {
                return nil
            }
            // The year as offsets: January 1 is the earliest (largest) and December 31 the latest.
            let earliest = PlannedTrip.days(from: yearStart, to: today, calendar: calendar)
            let latest = PlannedTrip.days(from: yearEnd, to: today, calendar: calendar)

            let recorded = calculator.presence.keys.filter {
                (latest...earliest).contains($0) && calculator.presence[$0]?.contains(countryCode) == true
            }
            let plannedOnly = planned.keys.filter {
                (latest...earliest).contains($0) && planned[$0] == countryCode
                    && calculator.presence[$0]?.contains(countryCode) != true
            }

            let chronological = (recorded + plannedOnly).sorted(by: >)
            let reached = chronological.count >= thresholdDays && thresholdDays > 0
                ? calculator.date(daysBeforeToday: chronological[thresholdDays - 1])
                : nil
            return TaxYearProjection(
                year: year,
                recordedDays: recorded.count,
                plannedDays: plannedOnly.count,
                thresholdDays: thresholdDays,
                thresholdReachedOn: reached
            )
        }
    }
}
