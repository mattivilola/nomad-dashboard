import Foundation

// The one-time "Welcome to Morocco" summary shown when the traveller crosses into a new country.
// `ArrivalDetector` decides whether an arrival just happened; `ArrivalBriefing.make` composes the
// content from data the dashboard already has. Every section is optional: missing data omits the
// section instead of guessing.

/// A crossing into a country the traveller was not in on the most recent previously recorded day.
public struct ArrivalEvent: Equatable, Sendable {
    /// Upper-case ISO 3166-1 alpha-2 code of the country just entered.
    public let countryCode: String
    /// Upper-case ISO 3166-1 alpha-2 code of the country of the most recent previously recorded day.
    public let previousCountryCode: String
    /// The first day of the stay in the new country.
    public let arrivedOn: VisitedCountryDayStamp

    public init(countryCode: String, previousCountryCode: String, arrivedOn: VisitedCountryDayStamp) {
        self.countryCode = countryCode
        self.previousCountryCode = previousCountryCode
        self.arrivedOn = arrivedOn
    }
}

public enum ArrivalDetector {
    /// A previous record older than this (before the stay began) is stale history, not a border
    /// crossing: the app was simply not running (or the traveller was away from the Mac) for too long
    /// to call it an arrival.
    public static let maximumPreviousRecordAgeDays = 30

    /// How many days after the first day in a country the briefing is still offered, so opening the
    /// dashboard a couple of days after crossing the border still shows it until "Got it".
    public static let arrivalWindowDays = 3

    /// The arrival that should be briefed now, or nil.
    ///
    /// An arrival is a stay in the current country (see `StayCalculator.currentStay`) that began at most
    /// `arrivalWindowDays` days ago, whose most recent recorded day before it was in another country.
    /// A day can hold several countries (a border day): the last country recorded that day is the
    /// previous one, and a previous day that also holds the current country is not a crossing. Days
    /// without a usable country code are skipped. `arrivedOn` is the first day of the stay.
    ///
    /// Nil as well when briefings are disabled, when the country was already acknowledged, when there
    /// is no history (first run), or when the previous record is more than
    /// `maximumPreviousRecordAgeDays` before the stay began.
    public static func arrival(
        countryDays: [VisitedCountryDay],
        currentCountryCode: String?,
        settings: AppSettings,
        now: Date,
        calendar: Calendar
    ) -> ArrivalEvent? {
        guard settings.arrivalBriefingEnabled,
              let current = currentCountryCode.flatMap(AppSettings.normalizedCountryCode),
              settings.arrivalBriefingAcknowledgedCountryCode.flatMap(AppSettings.normalizedCountryCode) != current
        else {
            return nil
        }

        let stay = StayCalculator(days: countryDays, now: now, calendar: calendar, liveCountryCode: current)
            .currentStay(in: current)
        guard let stay, stay.dayCount - 1 <= arrivalWindowDays else {
            return nil
        }

        let earlier = countryDays.compactMap { entry -> (day: VisitedCountryDayStamp, code: String)? in
            guard entry.day < stay.startDay, let code = entry.countryCode.flatMap(AppSettings.normalizedCountryCode) else {
                return nil
            }
            return (entry.day, code)
        }
        guard let latestDay = earlier.map(\.day).max() else {
            return nil
        }

        let latestCodes = earlier.filter { $0.day == latestDay }.map(\.code)
        guard latestCodes.contains(current) == false, let previous = latestCodes.last,
              let age = ageInDays(of: latestDay, until: stay.startDay, calendar: calendar),
              age <= maximumPreviousRecordAgeDays
        else {
            return nil
        }

        return ArrivalEvent(countryCode: current, previousCountryCode: previous, arrivedOn: stay.startDay)
    }

    private static func ageInDays(
        of day: VisitedCountryDayStamp,
        until later: VisitedCountryDayStamp,
        calendar: Calendar
    ) -> Int? {
        func noon(_ stamp: VisitedCountryDayStamp) -> Date? {
            calendar.date(from: DateComponents(year: stamp.year, month: stamp.month, day: stamp.day, hour: 12))
        }
        guard let start = noon(day), let end = noon(later) else {
            return nil
        }
        return calendar.dateComponents([.day], from: start, to: end).day
    }
}

/// What to tell the traveller on arrival. Build it with `make`; each section is nil when its data is
/// missing or does not apply.
public struct ArrivalBriefing: Equatable, Sendable {
    public let countryCode: String
    /// Localized country name, for example "Morocco".
    public let countryName: String
    public let time: Time?
    public let emergency: EmergencyNumbers?
    public let embassy: Embassy?
    public let road: Road?
    public let power: Power?
    public let money: Money?
    public let holiday: Holiday?
    /// Cultural or religious periods (Ramadan, Lunar New Year, ...) that are on now or start within
    /// `DashboardInsightEngine.localRhythmLookAheadDays` days, earliest first. Empty when there are none.
    public let rhythm: [LocalRhythmPeriod]
    public let advisory: Advisory?
    /// Set when the arrival comes with a time zone shift of 3 h or more that the body clock is still
    /// catching up with (see `JetLagAdvisor`).
    public let jetLag: JetLagSummary?
    /// Shown when Data Guard is enabled but not monitoring, as the traveller may have switched SIM.
    public let dataGuardHint: String?

    public var title: String {
        "Welcome to \(countryName)"
    }

    public static let dataGuardHintText = "On a local SIM or roaming? Turn on Data Guard monitoring."

    public init(
        countryCode: String,
        countryName: String,
        time: Time? = nil,
        emergency: EmergencyNumbers? = nil,
        embassy: Embassy? = nil,
        road: Road? = nil,
        power: Power? = nil,
        money: Money? = nil,
        holiday: Holiday? = nil,
        rhythm: [LocalRhythmPeriod] = [],
        advisory: Advisory? = nil,
        jetLag: JetLagSummary? = nil,
        dataGuardHint: String? = nil
    ) {
        self.countryCode = countryCode
        self.countryName = countryName
        self.time = time
        self.emergency = emergency
        self.embassy = embassy
        self.road = road
        self.power = power
        self.money = money
        self.holiday = holiday
        self.rhythm = rhythm
        self.advisory = advisory
        self.jetLag = jetLag
        self.dataGuardHint = dataGuardHint
    }
}

// MARK: - Sections

public extension ArrivalBriefing {
    /// The local time zone and how it compares with home.
    struct Time: Equatable, Sendable {
        public struct Home: Equatable, Sendable {
            public let timeZoneIdentifier: String
            /// City part of the identifier, for example "Helsinki" for "Europe/Helsinki".
            public let cityName: String
            /// Home's UTC offset minus the local one, in seconds: positive when home is ahead.
            public let offsetFromLocalSeconds: Int

            public init(timeZoneIdentifier: String, cityName: String, offsetFromLocalSeconds: Int) {
                self.timeZoneIdentifier = timeZoneIdentifier
                self.cityName = cityName
                self.offsetFromLocalSeconds = offsetFromLocalSeconds
            }

            /// For example "Home (Helsinki) is 2 h ahead" or "Home (Helsinki) is on the same time".
            public var differenceText: String {
                let minutes = abs(offsetFromLocalSeconds) / 60
                guard minutes > 0 else {
                    return "Home (\(cityName)) is on the same time"
                }
                let hours = minutes / 60
                let remainder = minutes % 60
                let amount = switch (hours, remainder) {
                case (0, _): "\(remainder) min"
                case (_, 0): "\(hours) h"
                default: "\(hours) h \(remainder) min"
                }
                return "Home (\(cityName)) is \(amount) \(offsetFromLocalSeconds > 0 ? "ahead" : "behind")"
            }
        }

        public let timeZoneIdentifier: String
        /// UTC offset at the time of the briefing, in seconds.
        public let utcOffsetSeconds: Int
        /// Nil when no home time zone is known.
        public let home: Home?

        public init(timeZoneIdentifier: String, utcOffsetSeconds: Int, home: Home?) {
            self.timeZoneIdentifier = timeZoneIdentifier
            self.utcOffsetSeconds = utcOffsetSeconds
            self.home = home
        }

        /// For example "UTC+1" or "UTC+5:30".
        public var utcOffsetText: String {
            let minutes = abs(utcOffsetSeconds) / 60
            let sign = utcOffsetSeconds < 0 ? "-" : "+"
            let hours = minutes / 60
            let remainder = minutes % 60
            return remainder == 0
                ? "UTC\(sign)\(hours)"
                : "UTC\(sign)\(hours):\(String(format: "%02d", remainder))"
        }
    }

    /// The nearest mission of the traveller's own state and the hotline of its foreign ministry.
    struct Embassy: Equatable, Sendable {
        /// Citizenship the mission and hotline belong to.
        public let citizenshipCode: String
        /// The nearest mission of the traveller's own state, or of a state that can help when their
        /// own has none here (see `fallbackReason`).
        public let nearestMission: DiplomaticMissionMatch?
        /// Set when `nearestMission` belongs to another state under an EU or Nordic arrangement.
        public let fallbackReason: EmbassyLookup.FallbackReason?
        public let consularContacts: ConsularContacts?

        public init(
            citizenshipCode: String,
            nearestMission: DiplomaticMissionMatch?,
            fallbackReason: EmbassyLookup.FallbackReason?,
            consularContacts: ConsularContacts?
        ) {
            self.citizenshipCode = citizenshipCode
            self.nearestMission = nearestMission
            self.fallbackReason = fallbackReason
            self.consularContacts = consularContacts
        }
    }

    struct Road: Equatable, Sendable {
        public let side: DrivingSide
        /// True when the previous country drove on the other side, so the traveller must switch.
        public let changesFromPreviousCountry: Bool

        public init(side: DrivingSide, changesFromPreviousCountry: Bool) {
            self.side = side
            self.changesFromPreviousCountry = changesFromPreviousCountry
        }

        /// For example "Drive on the left".
        public var text: String {
            switch side {
            case .left: "Drive on the left"
            case .right: "Drive on the right"
            }
        }
    }

    struct Power: Equatable, Sendable {
        public let electricity: CountryElectricity
        /// True when plugs, voltage or frequency differ from the previous country.
        public let differsFromPreviousCountry: Bool

        public init(electricity: CountryElectricity, differsFromPreviousCountry: Bool) {
            self.electricity = electricity
            self.differsFromPreviousCountry = differsFromPreviousCountry
        }
    }

    struct Money: Equatable, Sendable {
        /// ISO 4217 code, for example "MAD".
        public let currencyCode: String
        /// Localized currency name, for example "Moroccan Dirham".
        public let currencyName: String?
        /// True when the previous country used another currency.
        public let changesFromPreviousCountry: Bool

        public init(currencyCode: String, currencyName: String?, changesFromPreviousCountry: Bool) {
            self.currencyCode = currencyCode
            self.currencyName = currencyName
            self.changesFromPreviousCountry = changesFromPreviousCountry
        }
    }

    /// A public holiday today or tomorrow, when shops and offices may be closed.
    struct Holiday: Equatable, Sendable {
        public let name: String
        /// 0 for today, 1 for tomorrow.
        public let daysFromToday: Int

        public init(name: String, daysFromToday: Int) {
            self.name = name
            self.daysFromToday = daysFromToday
        }
    }

    struct Advisory: Equatable, Sendable {
        /// Caution or worse.
        public let severity: TravelAlertSeverity
        public let summary: String
        public let sourceName: String

        public init(severity: TravelAlertSeverity, summary: String, sourceName: String) {
            self.severity = severity
            self.summary = summary
            self.sourceName = sourceName
        }
    }
}

// MARK: - Composition

public extension ArrivalBriefing {
    /// Composes the briefing for `event` from data the dashboard already has.
    ///
    /// Sections about the country (local holiday, travel advisory) are only included when the snapshot
    /// is already about the arrival country, so a lagging refresh never shows the previous country's data.
    ///
    /// - Parameters:
    ///   - homeTimeZoneIdentifier: The traveller's home time zone, for the "home is 2 h ahead" line.
    ///   - timeZoneShifts: The recent changes of the local time zone (`TimeZoneShiftStore`), for the jet-lag
    ///     section. Without them there is none.
    ///   - calendar: Decides what "today" and "tomorrow" mean for the holiday and local-rhythm sections.
    ///   - locale: Used for the country and currency names.
    static func make(
        event: ArrivalEvent,
        snapshot: DashboardSnapshot,
        settings: AppSettings,
        homeTimeZoneIdentifier: String?,
        timeZoneShifts: [TimeZoneShiftRecord] = [],
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> ArrivalBriefing {
        let code = event.countryCode
        let previous = event.previousCountryCode
        let travelContext = snapshot.travelContext

        return ArrivalBriefing(
            countryCode: code,
            countryName: CountryNames.displayName(forCode: code, locale: locale),
            time: timeSection(travelContext: travelContext, homeTimeZoneIdentifier: homeTimeZoneIdentifier, now: now),
            emergency: EmergencyNumberDirectory.numbers(forCountryCode: code),
            embassy: embassySection(
                countryCode: code,
                citizenships: settings.citizenshipCountryCodes,
                deviceLocation: travelContext.deviceLocation
            ),
            road: road(countryCode: code, comparedWith: previous),
            power: power(countryCode: code, comparedWith: previous),
            money: money(countryCode: code, comparedWith: previous, locale: locale),
            holiday: holidaySection(countryCode: code, localInfo: snapshot.localInfo, now: now, calendar: calendar),
            rhythm: LocalRhythmCalendar.periods(
                forCountryCode: code,
                travelContext: travelContext,
                around: now,
                lookaheadDays: DashboardInsightEngine.localRhythmLookAheadDays,
                calendar: calendar
            ),
            advisory: advisorySection(countryCode: code, alerts: snapshot.travelAlerts),
            jetLag: JetLagAdvisor.summary(
                history: timeZoneShifts,
                travelContext: travelContext,
                now: now,
                calendar: calendar,
                locale: locale
            ),
            dataGuardHint: snapshot.meteredData.isFeatureEnabled && snapshot.meteredData.isMonitoringActive == false
                ? dataGuardHintText
                : nil
        )
    }

    /// Road, power and money facts for a country, each flagged when it differs from `otherCountryCode`
    /// (the country the traveller comes from). Shared with `TripPreview`, where the other country is the
    /// one the traveller is in now. Nil when the reference data does not cover the country.
    internal static func road(countryCode: String, comparedWith otherCountryCode: String?) -> Road? {
        TravelReferenceData.drivingSide(forCountryCode: countryCode).map { side in
            Road(
                side: side,
                changesFromPreviousCountry: TravelReferenceData.drivingSide(forCountryCode: otherCountryCode).map { $0 != side } ?? false
            )
        }
    }

    internal static func power(countryCode: String, comparedWith otherCountryCode: String?) -> Power? {
        TravelReferenceData.electricity(forCountryCode: countryCode).map { electricity in
            Power(
                electricity: electricity,
                differsFromPreviousCountry: TravelReferenceData.electricity(forCountryCode: otherCountryCode)
                    .map(electricity.differs(from:)) ?? false
            )
        }
    }

    internal static func money(countryCode: String, comparedWith otherCountryCode: String?, locale: Locale) -> Money? {
        TravelReferenceData.currencyCode(forCountryCode: countryCode).map { currency in
            Money(
                currencyCode: currency,
                currencyName: locale.localizedString(forCurrencyCode: currency),
                changesFromPreviousCountry: TravelReferenceData.currencyCode(forCountryCode: otherCountryCode)
                    .map { $0 != currency } ?? false
            )
        }
    }

    /// `settings` with the briefing for `countryCode` marked as seen, so it is not shown again until
    /// the traveller arrives somewhere else. Unchanged when `countryCode` is not a two-letter code.
    static func acknowledged(settings: AppSettings, countryCode: String, now: Date) -> AppSettings {
        guard let code = AppSettings.normalizedCountryCode(countryCode) else {
            return settings
        }
        var updated = settings
        updated.arrivalBriefingAcknowledgedCountryCode = code
        updated.arrivalBriefingAcknowledgedAt = now
        return updated
    }

    // MARK: Sections

    private static func timeSection(
        travelContext: TravelContextSnapshot,
        homeTimeZoneIdentifier: String?,
        now: Date
    ) -> Time? {
        guard let timeZone = localTimeZone(for: travelContext) else {
            return nil
        }

        let localOffset = timeZone.secondsFromGMT(for: now)
        let home = homeTimeZoneIdentifier.flatMap { identifier -> Time.Home? in
            guard let homeZone = TimeZone(identifier: identifier) else {
                return nil
            }
            return Time.Home(
                timeZoneIdentifier: identifier,
                cityName: CountryTimeZones.cityName(fromTimeZoneIdentifier: identifier),
                offsetFromLocalSeconds: homeZone.secondsFromGMT(for: now) - localOffset
            )
        }
        return Time(timeZoneIdentifier: timeZone.identifier, utcOffsetSeconds: localOffset, home: home)
    }

    /// The same order the daylight card uses (`DaylightReference`): the device or IP location's own
    /// zone, then the snapshot's. Without coordinates that reference does not exist, so the zones are
    /// read in that order directly.
    private static func localTimeZone(for travelContext: TravelContextSnapshot) -> TimeZone? {
        if let reference = DaylightReference(travelContext: travelContext) {
            return reference.timeZone
        }
        return [travelContext.deviceLocation?.timeZone, travelContext.location?.timeZone, travelContext.timeZoneIdentifier]
            .lazy
            .compactMap { $0.flatMap(TimeZone.init(identifier:)) }
            .first
    }

    /// Nothing when the traveller is home (every citizenship is this country) or has no citizenship set.
    private static func embassySection(
        countryCode: String,
        citizenships: [String],
        deviceLocation: IPLocationSnapshot?
    ) -> Embassy? {
        let coordinate = deviceLocation.flatMap { location in
            location.latitude.flatMap { latitude in location.longitude.map { (latitude: latitude, longitude: $0) } }
        }
        let lookup = EmbassyLookup(citizenships: citizenships, hostCountry: countryCode, coordinate: coordinate)
        let nearest = lookup.ownMatches.first ?? lookup.fallbackMatches.first
        guard let (citizenship, contacts) = consularContext(for: lookup), nearest != nil || contacts != nil else {
            return nil
        }

        return Embassy(
            citizenshipCode: citizenship,
            nearestMission: nearest,
            fallbackReason: lookup.ownMatches.isEmpty ? lookup.fallbackReason : nil,
            consularContacts: contacts
        )
    }

    /// The citizenship whose consular help applies in the lookup's host country, with its foreign-ministry
    /// hotline: the passport of the nearest own mission, else the first passport that has a hotline in the
    /// directory, else the first passport used abroad. Nil when every citizenship is the host country (the
    /// traveller is at home for each passport) or there is none.
    internal static func consularContext(for lookup: EmbassyLookup) -> (citizenship: String, contacts: ConsularContacts?)? {
        let abroad = lookup.citizenships.filter { $0 != lookup.hostCountry }
        guard abroad.isEmpty == false else {
            return nil
        }

        let citizenship = lookup.ownMatches.first?.mission.sendingCountry
            ?? abroad.first { ConsularContactsDirectory.contacts(forCitizenship: $0) != nil }
            ?? abroad[0]
        return (citizenship, ConsularContactsDirectory.contacts(forCitizenship: citizenship))
    }

    private static func holidaySection(
        countryCode: String,
        localInfo: LocalInfoSnapshot?,
        now: Date,
        calendar: Calendar
    ) -> Holiday? {
        guard let localInfo, localInfo.countryCode?.uppercased() == countryCode,
              let next = DashboardInsightEngine.nextPublicHoliday(in: localInfo, now: now, calendar: calendar),
              next.offset <= 1
        else {
            return nil
        }
        return Holiday(name: next.period.name, daysFromToday: next.offset)
    }

    private static func advisorySection(countryCode: String, alerts: TravelAlertsSnapshot?) -> Advisory? {
        guard let alerts, alerts.enabledKinds.contains(.advisory),
              alerts.primaryCountryCode?.uppercased() == countryCode,
              let state = alerts.state(for: .advisory), state.status == .ready,
              let signal = state.signal, signal.severity >= .caution
        else {
            return nil
        }
        return Advisory(
            severity: signal.severity,
            summary: signal.summary.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceName: signal.sourceName
        )
    }
}
