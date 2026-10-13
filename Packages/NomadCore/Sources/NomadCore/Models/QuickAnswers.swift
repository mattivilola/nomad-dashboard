import Foundation

// Short, natural sentences for Siri and Shortcuts, plus the structured values behind them.
//
// Everything here is a pure function of a dashboard snapshot, the settings and a clock: no network,
// no storage. The same lookups feed the home screen widgets, so a widget and a spoken answer can
// never disagree about the emergency number or the nearest embassy.
//
// Safety-critical wording: the answer never states more than the bundled data does. The directory's
// `general` number is "the number to call first", which for some countries is the police number
// rather than an all-purpose line, so the sentences call it "the emergency number" and never label
// it as police or as covering every service.

public enum QuickAnswers {
    // MARK: - Emergency numbers

    public struct EmergencyNumbersAnswer: Equatable, Sendable {
        /// Upper-case ISO code of the country the user is in, nil when it is not known yet.
        public let countryCode: String?
        public let countryName: String?
        /// Nil when the country is unknown or its numbers could not be verified.
        public let numbers: EmergencyNumbers?
        public let sentence: String
    }

    /// The emergency numbers for the country the user is in.
    public static func emergencyNumbers(snapshot: DashboardSnapshot, locale: Locale = .current) -> EmergencyNumbersAnswer {
        let code = snapshot.currentCountryCode
        guard let code else {
            return EmergencyNumbersAnswer(
                countryCode: nil,
                countryName: nil,
                numbers: nil,
                sentence: "I can't tell which country you're in yet, so I don't have emergency numbers for you. "
                    + "Open Nomad Dashboard to update your location."
            )
        }

        let name = countryName(forCode: code, snapshot: snapshot, locale: locale)
        let spokenName = spokenCountryName(name, code: code, locale: locale)
        guard let numbers = EmergencyNumberDirectory.numbers(forCountryCode: code) else {
            return EmergencyNumbersAnswer(
                countryCode: code,
                countryName: name,
                numbers: nil,
                sentence: "Nomad Dashboard doesn't have verified emergency numbers for \(spokenName) yet."
            )
        }

        var sentence = "The emergency number in \(spokenName) is \(numbers.general)."
        if let others = otherNumbersSentence(numbers, locale: locale) {
            sentence += " " + others
        }

        return EmergencyNumbersAnswer(countryCode: code, countryName: name, numbers: numbers, sentence: sentence)
    }

    /// "Police is 17, ambulance is 15, and fire is 18." / "Ambulance or fire is 15, and the Gendarmerie is 177."
    private static func otherNumbersSentence(_ numbers: EmergencyNumbers, locale: Locale) -> String? {
        var parts: [String] = []
        if let police = numbers.police {
            parts.append("police is \(police)")
        }

        switch (numbers.ambulance, numbers.fire) {
        case let (ambulance?, fire?) where ambulance == fire:
            parts.append("ambulance or fire is \(ambulance)")
        default:
            if let ambulance = numbers.ambulance {
                parts.append("ambulance is \(ambulance)")
            }
            if let fire = numbers.fire {
                parts.append("fire is \(fire)")
            }
        }

        parts.append(contentsOf: numbers.other.map { "the \($0.name) is \($0.number)" })

        guard parts.isEmpty == false else {
            return nil
        }

        return capitalizingFirstLetter(joined(parts, locale: locale)) + "."
    }

    // MARK: - Dashboard status

    public struct DashboardStatusAnswer: Equatable, Sendable {
        public let level: HealthLevel
        /// "Ready", "Caution", "Attention" or "Waiting".
        public let verdict: String
        /// "Network and power look good", "Network: Latency 85 ms".
        public let reason: String
        /// The most important heads-up for the selected travel profile, nil when there is none.
        public let headsUp: DashboardInsight?
        public let sentence: String
    }

    /// The overall verdict plus the top heads-up item, including stay, Schengen and tax-residence items
    /// when `visitedCountryDays` has the recorded days.
    public static func dashboardStatus(
        snapshot: DashboardSnapshot,
        settings: AppSettings,
        visitedCountryDays: [VisitedCountryDay],
        timeZoneShifts: [TimeZoneShiftRecord] = [],
        now: Date,
        calendar: Calendar = .current
    ) -> DashboardStatusAnswer {
        let overall = snapshot.healthSummary.overall
        let headsUp = DashboardInsightEngine.insights(
            for: snapshot,
            now: now,
            calendar: calendar,
            limit: 1,
            profile: settings.travelProfile,
            stays: StayInsightInput(
                countryDays: visitedCountryDays,
                settings: settings,
                currentCountryCode: snapshot.currentCountryCode
            ),
            timeZoneShifts: timeZoneShifts
        ).first

        var sentence = "\(overall.label). \(spoken(overall.reason))."
        if let headsUp {
            sentence += " Top heads-up: \(spoken(headsUp.title))."
        } else {
            sentence += " No heads-ups right now."
        }

        return DashboardStatusAnswer(
            level: overall.level,
            verdict: overall.label,
            reason: overall.reason,
            headsUp: headsUp,
            sentence: sentence
        )
    }

    // MARK: - Nearest embassy

    public struct NearestEmbassyAnswer: Equatable, Sendable {
        public enum State: Equatable, Sendable {
            /// No citizenship chosen in settings.
            case citizenshipNeeded
            /// The country the user is in is not known yet.
            case locationNeeded
            /// The user is in the country they hold citizenship of.
            case atHome
            /// One of the user's own missions is listed.
            case mission
            /// No own mission is listed; another state's mission can help (EU or Nordic arrangement).
            case fallbackMission
            /// Neither an own mission nor a fallback is listed.
            case noMission
        }

        public struct Mission: Equatable, Sendable {
            public let name: String
            public let city: String?
            /// Upper-case code of the state that runs the mission.
            public let sendingCountryCode: String
            /// "about 4 km" for a city-centre coordinate, "4.2 km" for a precise one; nil without a device position.
            public let distanceText: String?
        }

        public struct Hotline: Equatable, Sendable {
            /// Upper-case citizenship code the line belongs to.
            public let citizenship: String
            /// International format, ready to dial.
            public let phone: String
            /// The ministry's own caveat, for example "24/7 · emergencies abroad".
            public let note: String?
        }

        public let state: State
        public let mission: Mission?
        public let hotline: Hotline?
        public let sentence: String
    }

    /// The user's nearest own mission and consular hotline, the EU or Nordic fallback, or what to do next.
    public static func nearestEmbassy(
        snapshot: DashboardSnapshot,
        settings: AppSettings,
        index: DiplomaticMissionIndex = .bundled,
        locale: Locale = .current
    ) -> NearestEmbassyAnswer {
        let codes = settings.citizenshipCountryCodes
        guard codes.isEmpty == false else {
            return NearestEmbassyAnswer(
                state: .citizenshipNeeded,
                mission: nil,
                hotline: nil,
                sentence: "Set your citizenship in Nomad Dashboard settings to find your embassy."
            )
        }

        guard let host = snapshot.currentCountryCode else {
            let hotline = consularHotline(for: codes, preferring: nil)
            return NearestEmbassyAnswer(
                state: .locationNeeded,
                mission: nil,
                hotline: hotline,
                sentence: appendingHotline(
                    to: "I can't tell which country you're in yet, so I can't find your embassy.",
                    hotline: hotline,
                    citizenshipCount: codes.count,
                    locale: locale
                )
            )
        }

        let hostName = countryName(forCode: host, snapshot: snapshot, locale: locale)
        let spokenHost = spokenCountryName(hostName, code: host, locale: locale)
        if codes.allSatisfy({ $0 == host }) {
            return NearestEmbassyAnswer(
                state: .atHome,
                mission: nil,
                hotline: consularHotline(for: codes, preferring: nil),
                sentence: "You're home in \(hostName), so there's no embassy to look up."
            )
        }

        let device = snapshot.travelContext.deviceLocation
        let coordinate: (latitude: Double, longitude: Double)? = if let latitude = device?.latitude, let longitude = device?.longitude {
            (latitude, longitude)
        } else {
            nil
        }
        let lookup = EmbassyLookup(citizenships: codes, hostCountry: host, coordinate: coordinate, index: index)

        if let match = lookup.ownMatches.first {
            let mission = makeMission(match)
            let hotline = consularHotline(for: codes, preferring: match.mission.sendingCountry)
            let sentence = "Your nearest mission is the \(missionDescription(mission))."
            return NearestEmbassyAnswer(
                state: .mission,
                mission: mission,
                hotline: hotline,
                sentence: appendingHotline(to: sentence, hotline: hotline, citizenshipCount: codes.count, locale: locale)
            )
        }

        let abroad = codes.filter { $0 != host }
        let abroadNames = capitalizingFirstLetter(joined(
            abroad.map { spokenCountryName(countryName(forCode: $0, snapshot: nil, locale: locale), code: $0, locale: locale) },
            locale: locale
        ))
        let verb = abroad.count == 1 ? "has" : "have"
        let lead = "\(abroadNames) \(verb) no mission listed in \(spokenHost)"

        if let match = lookup.fallbackMatches.first, let reason = lookup.fallbackReason {
            let mission = makeMission(match)
            let hotline = consularHotline(for: codes, preferring: nil)
            let arrangement = switch reason {
            case .euConsularProtection: "Under EU consular protection"
            case .nordicCooperation: "Under Nordic consular cooperation"
            }
            let sentence = "\(lead). \(arrangement), the nearest mission that can help is the \(missionDescription(mission))."
            return NearestEmbassyAnswer(
                state: .fallbackMission,
                mission: mission,
                hotline: hotline,
                sentence: appendingHotline(to: sentence, hotline: hotline, citizenshipCount: codes.count, locale: locale)
            )
        }

        let hotline = consularHotline(for: codes, preferring: nil)
        let sentence = "\(lead), and no EU or Nordic alternative is known. Check your government's official list of missions."
        return NearestEmbassyAnswer(
            state: .noMission,
            mission: nil,
            hotline: hotline,
            sentence: appendingHotline(to: sentence, hotline: hotline, citizenshipCount: codes.count, locale: locale)
        )
    }

    private static func makeMission(_ match: DiplomaticMissionMatch) -> NearestEmbassyAnswer.Mission {
        NearestEmbassyAnswer.Mission(
            name: match.mission.name,
            city: match.mission.city?.trimmedNonEmpty,
            sendingCountryCode: match.mission.sendingCountry.uppercased(),
            distanceText: distanceText(kilometers: match.distanceKilometers, isApproximate: match.mission.isApproximateLocation)
        )
    }

    private static func distanceText(kilometers: Double?, isApproximate: Bool) -> String? {
        guard let kilometers, kilometers.isFinite, kilometers >= 0 else {
            return nil
        }

        return isApproximate
            ? "about \(max(1, Int(kilometers.rounded()))) km"
            : TravelUnitFormatting.kilometers(kilometers)
    }

    /// "Embassy of Finland in Rabat, about 4 km away": the city is only added when the name lacks it.
    private static func missionDescription(_ mission: NearestEmbassyAnswer.Mission) -> String {
        var text = mission.name
        if let city = mission.city, mission.name.range(of: city, options: [.caseInsensitive, .diacriticInsensitive]) == nil {
            text += " in \(city)"
        }
        if let distance = mission.distanceText {
            text += ", \(distance) away"
        }
        return text
    }

    /// The consular line of the citizenship that runs the nearest mission, else the first one with a bundled line.
    private static func consularHotline(for codes: [String], preferring sendingCountry: String?) -> NearestEmbassyAnswer.Hotline? {
        let preferred = sendingCountry.map { $0.uppercased() }.flatMap { code in codes.contains(code) ? code : nil }
        let candidates = (preferred.map { [$0] } ?? []) + codes
        for code in candidates {
            if let contacts = ConsularContactsDirectory.contacts(forCitizenship: code) {
                return NearestEmbassyAnswer.Hotline(
                    citizenship: code,
                    phone: contacts.emergencyPhone,
                    note: contacts.emergencyPhoneNote?.trimmedNonEmpty
                )
            }
        }
        return nil
    }

    /// "Your foreign ministry's consular emergency line is +358 295 16 0281 (24/7, emergencies abroad)." With several
    /// citizenships the line is named after its country.
    private static func appendingHotline(
        to sentence: String,
        hotline: NearestEmbassyAnswer.Hotline?,
        citizenshipCount: Int,
        locale: Locale
    ) -> String {
        guard let hotline else {
            return sentence
        }

        let owner = if citizenshipCount > 1 {
            "\(countryName(forCode: hotline.citizenship, snapshot: nil, locale: locale))'s foreign ministry's"
        } else {
            "Your foreign ministry's"
        }
        let note = hotline.note.map { " (\(spoken($0)))" } ?? ""
        return "\(sentence) \(owner) consular emergency line is \(hotline.phone)\(note)."
    }

    // MARK: - Daylight

    public struct DaylightAnswer: Equatable, Sendable {
        /// Nil when there is no location with coordinates yet.
        public let outlook: DaylightOutlook?
        public let phase: DaylightOutlook.Phase?
        /// Daylight left until sunset, nil outside daylight.
        public let remaining: TimeInterval?
        public let sentence: String
    }

    /// Sunset and the daylight left, or when it gets light again.
    public static func daylight(snapshot: DashboardSnapshot, now: Date, locale: Locale = .autoupdatingCurrent) -> DaylightAnswer {
        guard let outlook = DaylightOutlook(travelContext: snapshot.travelContext, now: now) else {
            return DaylightAnswer(
                outlook: nil,
                phase: nil,
                remaining: nil,
                sentence: "I can't tell when the sun sets because I don't have a location yet."
            )
        }

        let phase = outlook.phase(at: now)
        var remaining: TimeInterval?
        let sentence: String

        switch phase {
        case let .daylight(sunset):
            let left = max(sunset.timeIntervalSince(now), 0)
            remaining = left
            sentence = "Sunset is at \(outlook.clockTime(sunset, locale: locale)). "
                + "You have \(DurationText.hoursAndMinutes(left)) of daylight left."
        case let .dark(sunrise?):
            let time = outlook.clockTime(sunrise, locale: locale)
            if outlook.isSameDay(sunrise, as: now) {
                sentence = "It's dark until \(time)."
            } else {
                sentence = "The sun has set. It's dark until \(time) tomorrow."
            }
        case .dark(nil):
            sentence = "The sun has set."
        case .midnightSun:
            sentence = "The sun doesn't set today. It's midnight sun."
        case .polarNight:
            sentence = "The sun doesn't rise today. It's polar night."
        case nil:
            sentence = "I can't work out the sunset for your location today."
        }

        return DaylightAnswer(outlook: outlook, phase: phase, remaining: remaining, sentence: sentence)
    }

    // MARK: - Upcoming trip

    public struct UpcomingTripAnswer: Equatable, Sendable {
        public enum State: Equatable, Sendable {
            /// No planned trip is ahead and none is on.
            case noTrip
            /// A trip starts today or later.
            case upcoming
            /// A trip is on now and no later one is planned.
            case ongoing
        }

        public let state: State
        /// The trip the answer is about; nil when there is none.
        public let trip: PlannedTrip?
        public let countryName: String?
        /// Days until the trip starts (0 on the day); nil unless the trip is upcoming.
        public let daysUntilStart: Int?
        public let sentence: String
    }

    /// When the next planned trip starts, or the one that is on now. Planned trips are local to the Mac and
    /// only read from the settings here, so nothing is looked up.
    public static func upcomingTrip(
        settings: AppSettings,
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> UpcomingTripAnswer {
        let trips = settings.plannedTrips.sorted(by: PlannedTrip.isOrderedBefore)
        let upcoming = trips.first { $0.daysUntilStart(now: now, calendar: calendar) >= 0 }
        let ongoing = trips.first { $0.isOngoing(now: now, calendar: calendar) }
        let dayStyle = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .day().month(.wide)
        let name = { (trip: PlannedTrip) in
            spokenCountryName(
                CountryNames.displayName(forCode: trip.countryCode, locale: locale),
                code: trip.countryCode,
                locale: locale
            )
        }

        if let trip = upcoming {
            let startsIn = trip.daysUntilStart(now: now, calendar: calendar)
            let days = trip.dayCount(calendar: calendar)
            let length = days == 1 ? "1 day" : "\(days) days"
            let first = trip.firstDay(calendar: calendar).formatted(dayStyle)
            let last = trip.lastDay(calendar: calendar).formatted(dayStyle)
            let when = switch startsIn {
            case 0: "starts today"
            case 1: "starts tomorrow"
            default: "is in \(startsIn) days"
            }
            let span = days == 1 ? "It's on \(first), 1 day." : "It runs from \(first) to \(last), \(length)."
            return UpcomingTripAnswer(
                state: .upcoming,
                trip: trip,
                countryName: CountryNames.displayName(forCode: trip.countryCode, locale: locale),
                daysUntilStart: startsIn,
                sentence: "Your next trip, to \(name(trip)), \(when). \(span)"
            )
        }

        if let trip = ongoing {
            let endsToday = trip.daysSinceEnd(now: now, calendar: calendar) == 0
            let end = endsToday ? "It ends today." : "It ends on \(trip.lastDay(calendar: calendar).formatted(dayStyle))."
            return UpcomingTripAnswer(
                state: .ongoing,
                trip: trip,
                countryName: CountryNames.displayName(forCode: trip.countryCode, locale: locale),
                daysUntilStart: nil,
                sentence: "You're on your trip to \(name(trip)) right now. \(end)"
            )
        }

        return UpcomingTripAnswer(
            state: .noTrip,
            trip: nil,
            countryName: nil,
            daysUntilStart: nil,
            sentence: "You have no trips planned. You can plan one in the Nomad Dashboard Trip Planner."
        )
    }

    // MARK: - Shared wording

    /// "Rabat, Morocco", "Morocco" or nil when the place is not known.
    public static func placeName(snapshot: DashboardSnapshot, locale: Locale = .current) -> String? {
        let city = [
            snapshot.travelContext.deviceLocation?.city,
            snapshot.travelContext.location?.city,
            snapshot.localInfo?.locality
        ]
        .lazy
        .compactMap { $0?.trimmedNonEmpty }
        .first

        let country = snapshot.currentCountryCode.map { countryName(forCode: $0, snapshot: snapshot, locale: locale) }
        let parts = [city, country].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// The system's name for a region in the user's language, else the name the snapshot's providers
    /// gave, else the code itself.
    public static func countryName(forCode code: String, snapshot: DashboardSnapshot?, locale: Locale = .current) -> String {
        if let name = CountryNames.localizedName(forCode: code, locale: locale) {
            return name
        }

        let reported = [
            snapshot?.travelContext.deviceLocation?.country,
            snapshot?.travelContext.location?.country,
            snapshot?.localInfo?.countryName
        ]
        return reported.lazy.compactMap { $0?.trimmedNonEmpty }.first ?? CountryNames.displayName(forCode: code, locale: locale)
    }

    /// English country names that read naturally only with an article: "in the United States".
    private static let countriesNeedingArticle: Set<String> = [
        "US", "GB", "NL", "AE", "PH", "BS", "GM", "MV", "SC", "KM", "MH", "SB", "CD", "CG", "CF"
    ]

    private static func spokenCountryName(_ name: String, code: String, locale: Locale) -> String {
        guard locale.language.languageCode?.identifier == "en",
              countriesNeedingArticle.contains(code.uppercased())
        else {
            return name
        }
        return "the \(name)"
    }

    /// Siri reads "·" as a pause only sometimes, so a comma says it reliably.
    private static func spoken(_ text: String) -> String {
        text.replacingOccurrences(of: " \u{B7} ", with: ", ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespacesAndNewlines))
    }

    private static func joined(_ items: [String], locale: Locale) -> String {
        let formatter = ListFormatter()
        formatter.locale = locale
        return formatter.string(from: items) ?? items.joined(separator: ", ")
    }

    private static func capitalizingFirstLetter(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
