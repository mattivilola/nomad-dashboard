import Foundation

// What to know about a planned trip before leaving, composed from data that is bundled with the app, so it
// works offline and sends nothing anywhere. The sections that need the network (public holidays during the
// trip, the current travel advisory) come from `TripPreviewService`.
//
// Like `ArrivalBriefing`, every section is optional: missing data omits the section instead of guessing.

public struct TripPreview: Equatable, Sendable {
    public let trip: PlannedTrip
    /// Upper-case ISO 3166-1 alpha-2 code of the destination.
    public let countryCode: String
    /// Localized country name, for example "Morocco".
    public let countryName: String
    public let schedule: Schedule
    /// How the destination's clocks compare with home on the first day. Nil without a home time zone or
    /// when the country's zones are unknown.
    public let timeDifference: TripTimeDifference?
    public let emergency: EmergencyNumbers?
    /// Nil when the traveller is at home for every citizenship, has none, or nothing is known.
    public let embassy: Embassy?
    /// Road, power and money facts for the destination. The `...FromPreviousCountry` flags compare with
    /// the country the traveller is in now (`currentCountryCode`), not a country they came from.
    public let road: ArrivalBriefing.Road?
    public let power: ArrivalBriefing.Power?
    public let money: ArrivalBriefing.Money?
    /// Cultural or religious periods (Ramadan, Lunar New Year, ...) that overlap the trip, earliest first.
    /// A planned trip has no region, so Nyepi (Bali only) is kept for any trip to Indonesia; its name and
    /// guidance say "Bali" themselves.
    public let rhythm: [RhythmPeriod]
    /// What the trip does to the Schengen count, a stay allowance and the days in the destination this year.
    public let visa: TripVisaOutlook

    public init(
        trip: PlannedTrip,
        countryCode: String,
        countryName: String,
        schedule: Schedule,
        timeDifference: TripTimeDifference? = nil,
        emergency: EmergencyNumbers? = nil,
        embassy: Embassy? = nil,
        road: ArrivalBriefing.Road? = nil,
        power: ArrivalBriefing.Power? = nil,
        money: ArrivalBriefing.Money? = nil,
        rhythm: [RhythmPeriod] = [],
        visa: TripVisaOutlook = TripVisaOutlook(schengen: nil, allowance: nil, taxYears: [])
    ) {
        self.trip = trip
        self.countryCode = countryCode
        self.countryName = countryName
        self.schedule = schedule
        self.timeDifference = timeDifference
        self.emergency = emergency
        self.embassy = embassy
        self.road = road
        self.power = power
        self.money = money
        self.rhythm = rhythm
        self.visa = visa
    }

    /// For example "Morocco".
    public var title: String {
        countryName
    }
}

/// The parts of a trip preview that need the network, from `TripPreviewService`. Only the destination country
/// code was sent to get them.
public struct TripPreviewOnline: Equatable, Sendable {
    /// Public holidays that fall on a day of the trip, earliest first; empty when there are none. Nil when
    /// they could not be loaded and none are saved, which is not the same as none.
    public let holidays: [HolidayPeriodSnapshot]?
    /// The current travel advisory for the destination. Nil when it could not be loaded and none is saved,
    /// when the destination is not covered, or when the user turned travel advisories off.
    public let advisory: TravelAlertSignalSnapshot?
    /// When the older of the parts was fetched, so a saved answer can say how old it is.
    public let fetchedAt: Date

    public init(holidays: [HolidayPeriodSnapshot]?, advisory: TravelAlertSignalSnapshot?, fetchedAt: Date) {
        self.holidays = holidays
        self.advisory = advisory
        self.fetchedAt = fetchedAt
    }
}

// MARK: - Sections

public extension TripPreview {
    /// When the trip is, counted in calendar days of the calendar the preview was made with.
    struct Schedule: Equatable, Sendable {
        /// Days of the trip, the first and the last included.
        public let dayCount: Int
        public let nightCount: Int
        /// Days from today to the first day: 0 when it starts today, negative once it has started.
        public let daysUntilStart: Int
        /// Days from the last day to today: 0 on the last day, negative before it.
        public let daysSinceEnd: Int

        public init(dayCount: Int, nightCount: Int, daysUntilStart: Int, daysSinceEnd: Int) {
            self.dayCount = dayCount
            self.nightCount = nightCount
            self.daysUntilStart = daysUntilStart
            self.daysSinceEnd = daysSinceEnd
        }

        public var isUpcoming: Bool {
            daysUntilStart > 0
        }

        public var isOngoing: Bool {
            daysUntilStart <= 0 && daysSinceEnd <= 0
        }

        public var hasEnded: Bool {
            daysSinceEnd > 0
        }
    }

    /// The traveller's own consular help in the destination: their state's missions ranked by kind (embassy,
    /// consulate-general, consulate, ..., honorary last) and, when their own state has none there, the EU or
    /// Nordic missions that can help. There is no coordinate for a planned trip, so no mission carries a
    /// distance.
    struct Embassy: Equatable, Sendable {
        /// Citizenship the missions and hotline belong to.
        public let citizenshipCode: String
        /// Missions of the traveller's own state in the destination, best first.
        public let ownMissions: [DiplomaticMissionMatch]
        /// Missions of other states that can help. Only filled when there is no own mission at all.
        public let fallbackMissions: [DiplomaticMissionMatch]
        /// Set when `fallbackMissions` belong to other states under an EU or Nordic arrangement.
        public let fallbackReason: EmbassyLookup.FallbackReason?
        /// The foreign ministry's emergency line for the citizenship.
        public let consularContacts: ConsularContacts?

        public init(
            citizenshipCode: String,
            ownMissions: [DiplomaticMissionMatch],
            fallbackMissions: [DiplomaticMissionMatch],
            fallbackReason: EmbassyLookup.FallbackReason?,
            consularContacts: ConsularContacts?
        ) {
            self.citizenshipCode = citizenshipCode
            self.ownMissions = ownMissions
            self.fallbackMissions = fallbackMissions
            self.fallbackReason = fallbackReason
            self.consularContacts = consularContacts
        }
    }

    /// A local period together with where it falls in the trip.
    struct RhythmPeriod: Equatable, Sendable, Identifiable {
        public let period: LocalRhythmPeriod
        /// True when the period begins after the first day of the trip; false when it is already on at arrival.
        public let startsDuringTrip: Bool
        /// True when the period is over by the end of the last day of the trip; false when it runs past it.
        public let endsDuringTrip: Bool

        public var id: String {
            period.id
        }

        public init(period: LocalRhythmPeriod, startsDuringTrip: Bool, endsDuringTrip: Bool) {
            self.period = period
            self.startsDuringTrip = startsDuringTrip
            self.endsDuringTrip = endsDuringTrip
        }
    }
}

// MARK: - Composition

public extension TripPreview {
    /// The most own or fallback missions listed in the embassy section.
    static let missionLimit = 5

    /// Composes the offline part of the preview for `trip`.
    ///
    /// - Parameters:
    ///   - settings: Citizenships for the embassy section, and the plan, allowances and thresholds for the
    ///     visa outlook (`settings.plannedTrips` are all applied, `trip` included).
    ///   - countryDays: The recorded country days, the base for the visa outlook.
    ///   - currentCountryCode: The country the traveller is in now, to flag what changes there (driving side,
    ///     plugs and voltage, currency). Without it nothing is flagged.
    ///   - homeTimeZoneIdentifier: The traveller's home time zone, for the time difference.
    ///   - calendar: Decides which calendar days the trip covers and what "today" is.
    ///   - locale: Used for the country and currency names.
    static func make(
        trip: PlannedTrip,
        settings: AppSettings,
        countryDays: [VisitedCountryDay],
        currentCountryCode: String? = nil,
        homeTimeZoneIdentifier: String?,
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> TripPreview {
        let code = trip.countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let current = currentCountryCode.flatMap(AppSettings.normalizedCountryCode)
        let firstDay = trip.firstDay(calendar: calendar)
        let lastDay = trip.lastDay(calendar: calendar)
        let calculator = StayCalculator(days: countryDays, now: now, calendar: calendar, liveCountryCode: current)

        return TripPreview(
            trip: trip,
            countryCode: code,
            countryName: CountryNames.displayName(forCode: code, locale: locale),
            schedule: Schedule(
                dayCount: trip.dayCount(calendar: calendar),
                nightCount: trip.nightCount(calendar: calendar),
                daysUntilStart: trip.daysUntilStart(now: now, calendar: calendar),
                daysSinceEnd: trip.daysSinceEnd(now: now, calendar: calendar)
            ),
            timeDifference: homeTimeZoneIdentifier.flatMap {
                CountryTimeZones.timeDifference(forCountryCode: code, homeTimeZoneIdentifier: $0, on: firstDay)
            },
            emergency: EmergencyNumberDirectory.numbers(forCountryCode: code),
            embassy: embassySection(countryCode: code, citizenships: settings.citizenshipCountryCodes),
            road: ArrivalBriefing.road(countryCode: code, comparedWith: current),
            power: ArrivalBriefing.power(countryCode: code, comparedWith: current),
            money: ArrivalBriefing.money(countryCode: code, comparedWith: current, locale: locale),
            rhythm: rhythmSection(countryCode: code, firstDay: firstDay, lastDay: lastDay, calendar: calendar),
            visa: calculator.outlook(for: trip, among: settings.plannedTrips, settings: settings)
        )
    }

    private static func embassySection(countryCode: String, citizenships: [String]) -> Embassy? {
        let lookup = EmbassyLookup(
            citizenships: citizenships,
            hostCountry: countryCode,
            coordinate: nil,
            limit: missionLimit
        )
        guard let (citizenship, contacts) = ArrivalBriefing.consularContext(for: lookup),
              lookup.isEmpty == false || contacts != nil
        else {
            return nil
        }

        return Embassy(
            citizenshipCode: citizenship,
            ownMissions: lookup.ownMatches,
            fallbackMissions: lookup.fallbackMatches,
            fallbackReason: lookup.ownMatches.isEmpty ? lookup.fallbackReason : nil,
            consularContacts: contacts
        )
    }

    private static func rhythmSection(
        countryCode: String,
        firstDay: Date,
        lastDay: Date,
        calendar: Calendar
    ) -> [RhythmPeriod] {
        let endOfLastDay = calendar.date(byAdding: .day, value: 1, to: lastDay)?.addingTimeInterval(-1) ?? lastDay
        return LocalRhythmCalendar.periods(forCountryCode: countryCode, from: firstDay, to: lastDay, calendar: calendar)
            .map { period in
                RhythmPeriod(
                    period: period,
                    startsDuringTrip: period.start > firstDay,
                    endsDuringTrip: period.end <= endOfLastDay
                )
            }
    }
}
