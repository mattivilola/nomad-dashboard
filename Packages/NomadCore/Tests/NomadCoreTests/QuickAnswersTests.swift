import Foundation
import NomadCore
import Testing

struct QuickAnswersEmergencyNumbersTests {
    private let locale = QuickAnswersFixtures.locale

    @Test
    func moroccoNamesTheEmergencyNumberThenTheOthers() {
        let answer = QuickAnswers.emergencyNumbers(snapshot: QuickAnswersFixtures.morocco(), locale: locale)

        #expect(answer.countryCode == "MA")
        #expect(answer.countryName == "Morocco")
        #expect(answer.numbers == EmergencyNumberDirectory.numbers(forCountryCode: "MA"))
        #expect(answer.sentence == "The emergency number in Morocco is 19. Ambulance or fire is 15 and the Gendarmerie is 177.")
    }

    @Test
    func franceListsPoliceAmbulanceAndFire() {
        let snapshot = QuickAnswersFixtures.snapshot(device: QuickAnswersFixtures.location(countryCode: "FR"))
        let answer = QuickAnswers.emergencyNumbers(snapshot: snapshot, locale: locale)

        #expect(answer.sentence == "The emergency number in France is 112. Police is 17, ambulance is 15, and fire is 18.")
    }

    @Test
    func aSingleNumberCountryHasNothingToAdd() {
        let snapshot = QuickAnswersFixtures.snapshot(device: QuickAnswersFixtures.location(countryCode: "US"))

        #expect(QuickAnswers.emergencyNumbers(snapshot: snapshot, locale: locale).sentence == "The emergency number in the United States is 911.")
        let germany = QuickAnswersFixtures.snapshot(device: QuickAnswersFixtures.location(countryCode: "DE"))
        #expect(QuickAnswers.emergencyNumbers(snapshot: germany, locale: locale).sentence == "The emergency number in Germany is 112. Police is 110.")
    }

    @Test
    func theArticleIsOnlyAddedInEnglish() {
        let snapshot = QuickAnswersFixtures.snapshot(device: QuickAnswersFixtures.location(countryCode: "US"))
        let answer = QuickAnswers.emergencyNumbers(snapshot: snapshot, locale: Locale(identifier: "de_DE"))

        #expect(answer.sentence.hasPrefix("The emergency number in Vereinigte Staaten is 911."))
    }

    @Test
    func anUnknownCountryIsSaidClearlyAndInventsNothing() {
        let answer = QuickAnswers.emergencyNumbers(snapshot: QuickAnswersFixtures.snapshot(), locale: locale)

        #expect(answer.countryCode == nil)
        #expect(answer.numbers == nil)
        #expect(answer.sentence.contains("can't tell which country you're in"))
        #expect(answer.sentence.contains("Open Nomad Dashboard"))
    }

    @Test
    func aCountryWithoutVerifiedNumbersIsNotGuessed() {
        let snapshot = QuickAnswersFixtures.snapshot(device: QuickAnswersFixtures.location(countryCode: "LA"))
        let answer = QuickAnswers.emergencyNumbers(snapshot: snapshot, locale: locale)

        #expect(answer.countryCode == "LA")
        #expect(answer.numbers == nil)
        #expect(answer.sentence == "Nomad Dashboard doesn't have verified emergency numbers for Laos yet.")
    }

    @Test
    func theCountryComesFromDeviceThenIPThenLocalInfo() {
        let ipOnly = QuickAnswersFixtures.snapshot(ip: QuickAnswersFixtures.location(countryCode: "ES"))
        #expect(QuickAnswers.emergencyNumbers(snapshot: ipOnly, locale: locale).countryCode == "ES")

        let both = QuickAnswersFixtures.snapshot(
            device: QuickAnswersFixtures.location(countryCode: "FR"),
            ip: QuickAnswersFixtures.location(countryCode: "ES")
        )
        #expect(QuickAnswers.emergencyNumbers(snapshot: both, locale: locale).countryCode == "FR")
    }

    @Test
    func everyBundledCountryAnswersWithItsFirstNumberAndNoPoliceLabelOnIt() {
        for code in Locale.Region.isoRegions.map(\.identifier) {
            guard let numbers = EmergencyNumberDirectory.numbers(forCountryCode: code) else { continue }
            let snapshot = QuickAnswersFixtures.snapshot(device: QuickAnswersFixtures.location(countryCode: code))
            let sentence = QuickAnswers.emergencyNumbers(snapshot: snapshot, locale: locale).sentence

            #expect(sentence.contains(" is \(numbers.general)."), "\(code): \(sentence)")
            for service in numbers.other {
                #expect(sentence.contains("\(service.name) is \(service.number)"), "\(code): \(sentence)")
            }
        }
    }
}

struct QuickAnswersDashboardStatusTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func aHealthyDashboardIsReadyWithNoHeadsUps() {
        let answer = QuickAnswers.dashboardStatus(snapshot: QuickAnswersFixtures.snapshot(), settings: AppSettings(), visitedCountryDays: [], now: now)

        #expect(answer.level == .ready)
        #expect(answer.verdict == "Ready")
        #expect(answer.headsUp == nil)
        #expect(answer.sentence == "Ready. Network and power look good. No heads-ups right now.")
    }

    @Test
    func theVerdictLeadsAndTheTopHeadsUpFollows() {
        let snapshot = QuickAnswersFixtures.snapshot(metered: QuickAnswersFixtures.capReachedMetered())
        let answer = QuickAnswers.dashboardStatus(snapshot: snapshot, settings: AppSettings(), visitedCountryDays: [], now: now)

        #expect(answer.headsUp?.title == "Data cap reached")
        #expect(answer.sentence == "Ready. Network and power look good. Top heads-up: Data cap reached.")
    }

    @Test
    func anOfflineMacIsAttentionWithTheReason() {
        let answer = QuickAnswers.dashboardStatus(
            snapshot: QuickAnswersFixtures.snapshot(offline: true),
            settings: AppSettings(),
            visitedCountryDays: [],
            now: now
        )

        #expect(answer.level == .attention)
        #expect(answer.verdict == "Attention")
        #expect(answer.reason == "Network: No network route")
        #expect(answer.sentence.hasPrefix("Attention. Network: No network route."))
    }

    @Test
    func aRecentTimeZoneShiftIsTheTopHeadsUpWhenItIsGiven() {
        // Helsinki (UTC+3 in June) to Bangkok (UTC+7)... the shift itself is what counts: four hours east, a day ago.
        let helsinki = QuickAnswersFixtures.helsinkiSnapshot()
        let shifts = [
            TimeZoneShiftRecord(date: now.addingTimeInterval(-10 * 86_400), identifier: "Europe/Helsinki", offsetSeconds: 10_800),
            TimeZoneShiftRecord(date: now.addingTimeInterval(-86_400), identifier: "Asia/Bangkok", offsetSeconds: 25_200)
        ]

        let with = QuickAnswers.dashboardStatus(
            snapshot: helsinki, settings: AppSettings(), visitedCountryDays: [], timeZoneShifts: shifts, now: now
        )
        let without = QuickAnswers.dashboardStatus(
            snapshot: helsinki, settings: AppSettings(), visitedCountryDays: [], now: now
        )

        #expect(with.headsUp?.kind == .jetLag)
        #expect(with.sentence.contains("Top heads-up: Jet lag: day 2 of about 4."))
        #expect(without.headsUp == nil)
    }

    @Test
    func timeSeparatorsAreSpokenAsCommas() throws {
        // Road trip profile, 45 minutes before sunset in Helsinki: "Sunset 21:30 · 45 min of daylight".
        let helsinki = QuickAnswersFixtures.helsinkiSnapshot()
        let outlook = try #require(DaylightOutlook(travelContext: helsinki.travelContext, now: QuickAnswersFixtures.helsinkiMidday))
        let sunset = try #require(outlook.sunset)
        let answer = QuickAnswers.dashboardStatus(
            snapshot: helsinki,
            settings: AppSettings(travelProfile: .roadTrip),
            visitedCountryDays: [],
            now: sunset.addingTimeInterval(-45 * 60)
        )

        #expect(answer.headsUp?.kind == .daylight)
        #expect(answer.sentence.contains(" \u{B7} ") == false)
        #expect(answer.sentence.contains(", 45 min of daylight"))
    }

    @Test
    func aStayAllowanceRunningOutIsTheTopHeadsUp() {
        let calendar = QuickAnswersFixtures.calendar
        let snapshot = QuickAnswersFixtures.morocco()
        let answer = QuickAnswers.dashboardStatus(
            snapshot: snapshot,
            settings: AppSettings(stayAllowances: ["MA": 90]),
            visitedCountryDays: QuickAnswersFixtures.consecutiveDays(85, endingOn: now, in: "MA", calendar: calendar),
            now: now,
            calendar: calendar
        )

        #expect(answer.headsUp?.kind == .stayAllowance)
        #expect(answer.sentence == "Ready. Network and power look good. Top heads-up: Morocco: 5 days left.")
    }

    @Test
    func theSchengenLimitIsSpokenForAThirdCountryCitizen() {
        let calendar = QuickAnswersFixtures.calendar
        let snapshot = QuickAnswersFixtures.snapshot(device: QuickAnswersFixtures.location(city: "Lisbon", country: "Portugal", countryCode: "PT"))
        let answer = QuickAnswers.dashboardStatus(
            snapshot: snapshot,
            settings: AppSettings(citizenshipCountryCodes: ["US"]),
            visitedCountryDays: QuickAnswersFixtures.consecutiveDays(80, endingOn: now, in: "PT", calendar: calendar),
            now: now,
            calendar: calendar
        )

        #expect(answer.headsUp?.kind == .schengenLimit)
        #expect(answer.sentence.contains("Top heads-up: Schengen: 10 of 90 days left."))
    }

    @Test
    func withoutRecordedDaysThereAreNoStayHeadsUps() {
        let calendar = QuickAnswersFixtures.calendar
        let answer = QuickAnswers.dashboardStatus(
            snapshot: QuickAnswersFixtures.morocco(),
            settings: AppSettings(stayAllowances: ["MA": 90]),
            visitedCountryDays: [],
            now: now,
            calendar: calendar
        )

        #expect(answer.headsUp == nil)
    }
}

struct QuickAnswersNearestEmbassyTests {
    private let locale = QuickAnswersFixtures.locale
    private let index = QuickAnswersFixtures.missionIndex

    private func answer(
        _ snapshot: DashboardSnapshot,
        citizenships: [String]
    ) -> QuickAnswers.NearestEmbassyAnswer {
        QuickAnswers.nearestEmbassy(
            snapshot: snapshot,
            settings: AppSettings(citizenshipCountryCodes: citizenships),
            index: index,
            locale: locale
        )
    }

    @Test
    func withoutCitizenshipItSaysWhereToSetIt() {
        let result = answer(QuickAnswersFixtures.morocco(), citizenships: [])

        #expect(result.state == .citizenshipNeeded)
        #expect(result.mission == nil)
        #expect(result.hotline == nil)
        #expect(result.sentence == "Set your citizenship in Nomad Dashboard settings to find your embassy.")
    }

    @Test
    func withoutACountryItAsksForLocationButStillGivesTheHotline() throws {
        let result = answer(QuickAnswersFixtures.snapshot(), citizenships: ["FI"])
        let phone = try #require(ConsularContactsDirectory.contacts(forCitizenship: "FI")).emergencyPhone

        #expect(result.state == .locationNeeded)
        #expect(result.hotline?.phone == phone)
        #expect(result.sentence.hasPrefix("I can't tell which country you're in yet, so I can't find your embassy."))
        #expect(result.sentence.contains("consular emergency line is \(phone)"))
    }

    @Test
    func atHomeThereIsNoEmbassyToFind() {
        let result = answer(QuickAnswersFixtures.helsinkiSnapshot(), citizenships: ["FI"])

        #expect(result.state == .atHome)
        #expect(result.mission == nil)
        #expect(result.sentence == "You're home in Finland, so there's no embassy to look up.")
    }

    @Test
    func abroadItNamesTheNearestOwnMissionWithDistanceAndTheHotline() throws {
        let result = answer(QuickAnswersFixtures.morocco(), citizenships: ["FI"])
        let contacts = try #require(ConsularContactsDirectory.contacts(forCitizenship: "FI"))

        #expect(result.state == .mission)
        #expect(result.mission?.name == "Embassy of Finland in Rabat")
        #expect(result.mission?.sendingCountryCode == "FI")
        #expect(result.mission?.distanceText?.hasSuffix("km") == true)
        #expect(result.hotline?.phone == contacts.emergencyPhone)
        #expect(result.sentence.hasPrefix("Your nearest mission is the Embassy of Finland in Rabat, "))
        #expect(result.sentence.contains(" km away. Your foreign ministry's consular emergency line is \(contacts.emergencyPhone)"))
    }

    @Test
    func aCityCentreCoordinateIsCalledAboutAndTheCityIsAddedWhenTheNameLacksIt() {
        let snapshot = QuickAnswersFixtures.snapshot(
            device: QuickAnswersFixtures.location(countryCode: "MA", latitude: 34.0, longitude: -6.9)
        )
        let result = answer(snapshot, citizenships: ["SE"])

        #expect(result.mission?.name == "Embassy of Sweden")
        #expect(result.mission?.distanceText?.hasPrefix("about ") == true)
        #expect(result.sentence.hasPrefix("Your nearest mission is the Embassy of Sweden in Rabat, about "))
    }

    @Test
    func withoutAnOwnMissionAFellowEUOrNordicMissionHelps() {
        let snapshot = QuickAnswersFixtures.snapshot(device: QuickAnswersFixtures.location(countryCode: "ES"))
        let result = answer(snapshot, citizenships: ["FI"])

        #expect(result.state == .fallbackMission)
        #expect(result.mission?.sendingCountryCode == "SE")
        #expect(result.sentence.hasPrefix(
            "Finland has no mission listed in Spain. Under Nordic consular cooperation, the nearest mission that can help is the Embassy of Sweden in Madrid."
        ))
    }

    @Test
    func withNothingListedItSaysSoAndKeepsTheHotline() throws {
        let snapshot = QuickAnswersFixtures.snapshot(device: QuickAnswersFixtures.location(countryCode: "ES"))
        let result = answer(snapshot, citizenships: ["AU"])
        let phone = try #require(ConsularContactsDirectory.contacts(forCitizenship: "AU")).emergencyPhone

        #expect(result.state == .noMission)
        #expect(result.mission == nil)
        #expect(result.sentence.hasPrefix(
            "Australia has no mission listed in Spain, and no EU or Nordic alternative is known. Check your government's official list of missions."
        ))
        #expect(result.sentence.contains(phone))
    }

    @Test
    func severalCitizenshipsNameTheCountryOfTheHotline() {
        // Standing at the Finnish embassy: it is the nearest one even though Sweden is listed first.
        let atFinnishEmbassy = QuickAnswersFixtures.snapshot(
            device: QuickAnswersFixtures.location(countryCode: "MA", latitude: 34.05, longitude: -6.84)
        )
        let result = answer(atFinnishEmbassy, citizenships: ["SE", "FI"])

        #expect(result.state == .mission)
        #expect(result.mission?.sendingCountryCode == "FI")
        #expect(result.hotline?.citizenship == "FI")
        #expect(result.sentence.contains("Finland's foreign ministry's consular emergency line is "))
    }

    @Test
    func theMinistrysNoteIsSpokenWithCommas() throws {
        let result = answer(QuickAnswersFixtures.morocco(), citizenships: ["AT"])
        let note = try #require(ConsularContactsDirectory.contacts(forCitizenship: "AT")).emergencyPhoneNote

        #expect(note?.contains("\u{B7}") == true)
        #expect(result.sentence.contains("\u{B7}") == false)
        #expect(result.sentence.contains("(24/7, emergencies abroad)"))
    }
}

struct QuickAnswersDaylightTests {
    private let locale = QuickAnswersFixtures.locale
    private let helsinki = QuickAnswersFixtures.helsinkiSnapshot()

    private func outlook(at now: Date) throws -> DaylightOutlook {
        try #require(DaylightOutlook(travelContext: helsinki.travelContext, now: now))
    }

    @Test
    func inTheDaySunsetAndTheDaylightLeftAreGiven() throws {
        let now = QuickAnswersFixtures.helsinkiMidday
        let outlook = try outlook(at: now)
        let sunset = try #require(outlook.sunset)
        let answer = QuickAnswers.daylight(snapshot: helsinki, now: sunset.addingTimeInterval(-(2 * 3_600 + 10 * 60)), locale: locale)

        #expect(answer.phase == .daylight(sunset: sunset))
        #expect(abs((answer.remaining ?? 0) - (2 * 3_600 + 10 * 60)) < 0.001)
        #expect(answer.sentence == "Sunset is at \(outlook.clockTime(sunset, locale: locale)). You have 2 h 10 min of daylight left.")
    }

    @Test
    func lessThanAMinuteLeftIsRoundedUpToOneMinute() throws {
        let sunset = try #require(try outlook(at: QuickAnswersFixtures.helsinkiMidday).sunset)
        let answer = QuickAnswers.daylight(snapshot: helsinki, now: sunset.addingTimeInterval(-10), locale: locale)

        #expect(answer.sentence.hasSuffix("You have 1 min of daylight left."))
    }

    @Test
    func afterSunsetItIsDarkUntilTomorrowsSunrise() throws {
        let now = QuickAnswersFixtures.helsinkiMidday
        let outlook = try outlook(at: now)
        let sunset = try #require(outlook.sunset)
        let nextSunrise = try #require(outlook.nextSunrise)
        let answer = QuickAnswers.daylight(snapshot: helsinki, now: sunset.addingTimeInterval(60), locale: locale)

        #expect(answer.phase == .dark(sunrise: nextSunrise))
        #expect(answer.remaining == nil)
        #expect(answer.sentence == "The sun has set. It's dark until \(outlook.clockTime(nextSunrise, locale: locale)) tomorrow.")
    }

    @Test
    func beforeSunriseItIsDarkUntilTodaysSunrise() throws {
        let outlook = try outlook(at: QuickAnswersFixtures.helsinkiMidday)
        let sunrise = try #require(outlook.sunrise)
        let answer = QuickAnswers.daylight(snapshot: helsinki, now: sunrise.addingTimeInterval(-3_600), locale: locale)

        #expect(answer.phase == .dark(sunrise: sunrise))
        #expect(answer.sentence == "It's dark until \(outlook.clockTime(sunrise, locale: locale)).")
    }

    @Test
    func theSunNeverSetsInTheMidnightSun() {
        let tromso = QuickAnswersFixtures.snapshot(device: QuickAnswersFixtures.location(
            latitude: 69.65, longitude: 18.96, timeZone: "Europe/Oslo"
        ))
        let answer = QuickAnswers.daylight(
            snapshot: tromso,
            now: QuickAnswersFixtures.date(2_026, 6, 21, 23, 0, timeZone: "Europe/Oslo"),
            locale: locale
        )

        #expect(answer.phase == .midnightSun)
        #expect(answer.sentence == "The sun doesn't set today. It's midnight sun.")
    }

    @Test
    func theSunNeverRisesInThePolarNight() {
        let tromso = QuickAnswersFixtures.snapshot(device: QuickAnswersFixtures.location(
            latitude: 69.65, longitude: 18.96, timeZone: "Europe/Oslo"
        ))
        let answer = QuickAnswers.daylight(
            snapshot: tromso,
            now: QuickAnswersFixtures.date(2_026, 12, 21, 12, 0, timeZone: "Europe/Oslo"),
            locale: locale
        )

        #expect(answer.phase == .polarNight)
        #expect(answer.sentence == "The sun doesn't rise today. It's polar night.")
    }

    @Test
    func withoutALocationItSaysSo() {
        let answer = QuickAnswers.daylight(snapshot: QuickAnswersFixtures.snapshot(), now: QuickAnswersFixtures.helsinkiMidday, locale: locale)

        #expect(answer.outlook == nil)
        #expect(answer.phase == nil)
        #expect(answer.sentence == "I can't tell when the sun sets because I don't have a location yet.")
    }
}

struct QuickAnswersPlaceTests {
    private let locale = QuickAnswersFixtures.locale

    @Test
    func theCityAndCountryAreJoined() {
        #expect(QuickAnswers.placeName(snapshot: QuickAnswersFixtures.morocco(), locale: locale) == "Rabat, Morocco")
    }

    @Test
    func theCountryAloneIsEnough() {
        let snapshot = QuickAnswersFixtures.snapshot(ip: QuickAnswersFixtures.location(countryCode: "ES"))

        #expect(QuickAnswers.placeName(snapshot: snapshot, locale: locale) == "Spain")
    }

    @Test
    func anUnknownPlaceIsNil() {
        #expect(QuickAnswers.placeName(snapshot: QuickAnswersFixtures.snapshot(), locale: locale) == nil)
    }

    @Test
    func aCodeTheSystemCannotNameFallsBackToTheProviderNameThenTheCode() {
        let named = QuickAnswersFixtures.snapshot(device: QuickAnswersFixtures.location(country: "Xandria", countryCode: "ZZ"))
        let unnamed = QuickAnswersFixtures.snapshot(device: QuickAnswersFixtures.location(countryCode: "ZZ"))

        #expect(QuickAnswers.countryName(forCode: "ZZ", snapshot: named, locale: locale) == "Xandria")
        #expect(QuickAnswers.countryName(forCode: "ZZ", snapshot: unnamed, locale: locale) == "ZZ")
    }
}
