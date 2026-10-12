import Foundation
import Testing
@testable import NomadCore

struct ArrivalBriefingTests {
    // 2026-10-12 12:00 UTC, a Monday.
    private let now = Date(timeIntervalSince1970: 1_791_806_400)
    // 2026-06-15 12:00 UTC: Madrid is UTC+2, Casablanca UTC+1 and Helsinki UTC+3. Morocco's clock
    // follows the OS tz database (which moves it to UTC+0 in autumn 2026), so the time assertions
    // that name Morocco's offset pin a date on which every tz database agrees.
    private let summer = Date(timeIntervalSince1970: 1_781_524_800)
    private let locale = Locale(identifier: "en_US")

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = locale
        return calendar
    }

    // MARK: - Detection

    @Test
    func firstRunWithoutHistoryIsNotAnArrival() {
        #expect(detect(days: [], current: "ES") == nil)
    }

    @Test
    func todaysOwnRecordIsNotHistory() {
        #expect(detect(days: [day(0, "ES")], current: "ES") == nil)
    }

    @Test
    func stayingInTheSameCountryIsNotAnArrival() {
        #expect(detect(days: [day(3, "ES"), day(1, "ES")], current: "ES") == nil)
    }

    @Test
    func aNewCountryIsAnArrivalFromTheMostRecentPreviousDay() throws {
        let event = try #require(detect(days: [day(5, "FR"), day(1, "ES")], current: "MA"))

        #expect(event.countryCode == "MA")
        #expect(event.previousCountryCode == "ES")
        #expect(event.arrivedOn == VisitedCountryDayStamp(year: 2026, month: 10, day: 12))
    }

    @Test
    func todaysRecordDoesNotHideTheArrival() throws {
        let event = try #require(detect(days: [day(1, "ES"), day(0, "MA")], current: "MA"))
        #expect(event.previousCountryCode == "ES")
    }

    @Test
    func currentCountryCodeIsNormalized() throws {
        let event = try #require(detect(days: [day(1, "ES")], current: " ma "))
        #expect(event.countryCode == "MA")
    }

    @Test
    func missingOrInvalidCurrentCountryIsNotAnArrival() {
        #expect(detect(days: [day(1, "ES")], current: nil) == nil)
        #expect(detect(days: [day(1, "ES")], current: "") == nil)
        #expect(detect(days: [day(1, "ES")], current: "Morocco") == nil)
    }

    @Test
    func theAcknowledgedCountryIsNotBriefedAgain() throws {
        var settings = AppSettings()
        settings.arrivalBriefingAcknowledgedCountryCode = "MA"
        #expect(detect(days: [day(1, "ES")], current: "MA", settings: settings) == nil)

        // Having acknowledged another country does not suppress this one.
        settings.arrivalBriefingAcknowledgedCountryCode = "FR"
        #expect(try #require(detect(days: [day(1, "ES")], current: "MA", settings: settings)).countryCode == "MA")
    }

    @Test
    func disabledBriefingsNeverDetect() {
        var settings = AppSettings()
        settings.arrivalBriefingEnabled = false
        #expect(detect(days: [day(1, "ES")], current: "MA", settings: settings) == nil)
    }

    @Test
    func staleHistoryIsNotAnArrival() throws {
        // Exactly 30 days is still a crossing; 31 is stale history.
        #expect(try #require(detect(days: [day(30, "ES")], current: "MA")).previousCountryCode == "ES")
        #expect(detect(days: [day(31, "ES")], current: "MA") == nil)
        #expect(detect(days: [day(200, "ES")], current: "MA") == nil)
    }

    @Test
    func theMostRecentDayDecidesStalenessNotOlderOnes() throws {
        // Old records are irrelevant once a recent one exists.
        let event = try #require(detect(days: [day(90, "FR"), day(2, "ES")], current: "MA"))
        #expect(event.previousCountryCode == "ES")
    }

    // MARK: - Arrival window

    /// ES until `daysSinceCrossing + 1` days ago, then MA every day through today.
    private func crossing(daysSinceCrossing: Int, previous: String = "ES") -> [VisitedCountryDay] {
        [day(daysSinceCrossing + 1, previous)] + (0...daysSinceCrossing).map { day($0, "MA") }
    }

    @Test
    func theBriefingIsOfferedOnTheCrossingDayAndForThreeDaysAfter() throws {
        #expect(ArrivalDetector.arrivalWindowDays == 3)
        for daysSince in 0...3 {
            let event = try #require(detect(days: crossing(daysSinceCrossing: daysSince), current: "MA"))
            #expect(event.countryCode == "MA")
            #expect(event.previousCountryCode == "ES")
            #expect(event.arrivedOn == stamp(daysSince))
        }
    }

    @Test
    func theBriefingIsGoneFourDaysAfterCrossing() {
        #expect(detect(days: crossing(daysSinceCrossing: 4), current: "MA") == nil)
        #expect(detect(days: crossing(daysSinceCrossing: 20), current: "MA") == nil)
    }

    @Test
    func opening2DaysAfterCrossingStillShowsUntilAcknowledged() throws {
        let days = crossing(daysSinceCrossing: 2)
        #expect(detect(days: days, current: "MA") != nil)

        let acknowledged = ArrivalBriefing.acknowledged(settings: AppSettings(), countryCode: "MA", now: now)
        #expect(detect(days: days, current: "MA", settings: acknowledged) == nil)
    }

    @Test
    func aMissingRecordInsideTheFirstDaysDoesNotHideTheArrival() throws {
        // Crossed 3 days ago; the Mac was off the day after.
        let days = [day(4, "ES"), day(3, "MA"), day(1, "MA"), day(0, "MA")]
        let event = try #require(detect(days: days, current: "MA"))
        #expect(event.arrivedOn == stamp(3))
    }

    @Test
    func theStaleLimitCountsFromTheStartOfTheStayNotFromToday() throws {
        // Previous record 30 days before the crossing, two days ago: still an arrival.
        let ok = [day(32, "ES"), day(2, "MA"), day(1, "MA"), day(0, "MA")]
        #expect(try #require(detect(days: ok, current: "MA")).previousCountryCode == "ES")

        let stale = [day(33, "ES"), day(2, "MA"), day(1, "MA"), day(0, "MA")]
        #expect(detect(days: stale, current: "MA") == nil)
    }

    @Test
    func comingBackToACountryAfterATripElsewhereIsAnArrivalAgain() throws {
        // Morocco, a week in Spain, back in Morocco today.
        let days = (20...30).map { day($0, "MA") } + (1...19).map { day($0, "ES") }
        let event = try #require(detect(days: days, current: "MA"))
        #expect(event.previousCountryCode == "ES")
        #expect(event.arrivedOn == stamp(0))
    }

    @Test
    func aStayThatStartedAfterAGapInTheSameCountryIsNotAnArrival() {
        // Morocco, nothing recorded for a week, Morocco again: no crossing happened.
        #expect(detect(days: [day(9, "MA"), day(8, "MA"), day(0, "MA")], current: "MA") == nil)
    }

    @Test
    func borderDayContainingTheCurrentCountryIsNotAnArrival() {
        // Crossed ES to MA yesterday: the traveller was already in Morocco.
        #expect(detect(days: [day(1, "ES"), day(1, "MA")], current: "MA") == nil)
        #expect(detect(days: [day(1, "MA"), day(1, "ES")], current: "MA") == nil)
    }

    @Test
    func borderDayUsesTheLastRecordedCountryAsPrevious() throws {
        let toMorocco = try #require(detect(days: [day(1, "ES"), day(1, "MA")], current: "PT"))
        #expect(toMorocco.previousCountryCode == "MA")

        let toSpain = try #require(detect(days: [day(1, "MA"), day(1, "ES")], current: "PT"))
        #expect(toSpain.previousCountryCode == "ES")
    }

    @Test
    func daysWithoutACountryCodeAreSkipped() throws {
        let unknown = VisitedCountryDay(day: stamp(1), country: "Somewhere", countryCode: nil, source: .deviceLocation, isInferred: false)
        let event = try #require(detect(days: [day(3, "ES"), unknown], current: "MA"))
        #expect(event.previousCountryCode == "ES")
        #expect(detect(days: [unknown], current: "MA") == nil)
    }

    // MARK: - Acknowledgement

    @Test
    func acknowledgingStoresTheCountryAndTime() {
        let updated = ArrivalBriefing.acknowledged(settings: AppSettings(), countryCode: "ma", now: now)

        #expect(updated.arrivalBriefingAcknowledgedCountryCode == "MA")
        #expect(updated.arrivalBriefingAcknowledgedAt == now)
        #expect(detect(days: [day(1, "ES")], current: "MA", settings: updated) == nil)
    }

    @Test
    func acknowledgingLeavesEverythingElseAndInvalidCodesAlone() {
        var settings = AppSettings()
        settings.citizenshipCountryCodes = ["FI"]
        settings.arrivalBriefingAcknowledgedCountryCode = "ES"

        let updated = ArrivalBriefing.acknowledged(settings: settings, countryCode: "MA", now: now)
        #expect(updated.citizenshipCountryCodes == ["FI"])

        #expect(ArrivalBriefing.acknowledged(settings: settings, countryCode: "Morocco", now: now) == settings)
        #expect(settings.arrivalBriefingAcknowledgedCountryCode == "ES")
    }

    // MARK: - Spain to Morocco

    @Test
    func spainToMoroccoBriefing() throws {
        var settings = AppSettings()
        settings.citizenshipCountryCodes = ["FI"]
        let briefing = makeBriefing(
            snapshot: moroccoSnapshot(),
            settings: settings,
            home: "Europe/Helsinki",
            at: summer
        )

        #expect(briefing.countryCode == "MA")
        #expect(briefing.countryName == "Morocco")
        #expect(briefing.title == "Welcome to Morocco")

        let time = try #require(briefing.time)
        #expect(time.timeZoneIdentifier == "Africa/Casablanca")
        #expect(time.utcOffsetSeconds == 3_600)
        #expect(time.utcOffsetText == "UTC+1")
        #expect(time.home?.cityName == "Helsinki")
        #expect(time.home?.offsetFromLocalSeconds == 7_200)
        #expect(time.home?.differenceText == "Home (Helsinki) is 2 h ahead")

        let emergency = try #require(briefing.emergency)
        #expect(emergency == EmergencyNumberDirectory.numbers(forCountryCode: "MA"))
        #expect(emergency.other == [EmergencyService(name: "Gendarmerie", number: "177")])

        // Spain and Morocco both drive on the right: nothing to switch.
        #expect(briefing.road == ArrivalBriefing.Road(side: .right, changesFromPreviousCountry: false))
        #expect(briefing.road?.text == "Drive on the right")

        // C and F in Spain, C and E in Morocco.
        let power = try #require(briefing.power)
        #expect(power.electricity.plugTypes == ["C", "E"])
        #expect(power.electricity.voltage == 220)
        #expect(power.differsFromPreviousCountry)

        let money = try #require(briefing.money)
        #expect(money.currencyCode == "MAD")
        #expect(money.currencyName == "Moroccan Dirham")
        #expect(money.changesFromPreviousCountry)
        #expect(briefing.rhythm.isEmpty)
    }

    @Test
    func sectionsDescribingChangesAreCalmWhenNothingChanged() throws {
        // Portugal to Spain: same side, same currency, same plugs, same supply.
        let briefing = ArrivalBriefing.make(
            event: ArrivalEvent(countryCode: "ES", previousCountryCode: "PT", arrivedOn: stamp(0)),
            snapshot: makeSnapshot(countryCode: "ES", timeZone: "Europe/Madrid"),
            settings: AppSettings(),
            homeTimeZoneIdentifier: nil,
            now: now,
            calendar: calendar,
            locale: locale
        )

        #expect(briefing.road?.changesFromPreviousCountry == false)
        #expect(briefing.money?.changesFromPreviousCountry == false)
        #expect(briefing.power?.differsFromPreviousCountry == false)
    }

    // MARK: - Time

    @Test
    func timeComparesWithHomeAheadBehindAndSame() throws {
        func home(_ identifier: String?) -> ArrivalBriefing.Time? {
            makeBriefing(snapshot: moroccoSnapshot(), home: identifier, at: summer).time
        }

        #expect(home("Europe/Helsinki")?.home?.differenceText == "Home (Helsinki) is 2 h ahead")
        #expect(home("America/New_York")?.home?.differenceText == "Home (New York) is 5 h behind")
        #expect(home("Asia/Kolkata")?.home?.differenceText == "Home (Kolkata) is 4 h 30 min ahead")
        #expect(home("Africa/Casablanca")?.home?.differenceText == "Home (Casablanca) is on the same time")
        #expect(home(nil)?.home == nil)
        #expect(home("Not/AZone")?.home == nil)
        #expect(home(nil)?.timeZoneIdentifier == "Africa/Casablanca")
    }

    @Test
    func utcOffsetTextCoversFractionalAndNegativeOffsets() {
        func text(_ seconds: Int) -> String {
            ArrivalBriefing.Time(timeZoneIdentifier: "X", utcOffsetSeconds: seconds, home: nil).utcOffsetText
        }
        #expect(text(0) == "UTC+0")
        #expect(text(3_600) == "UTC+1")
        #expect(text(19_800) == "UTC+5:30")
        #expect(text(-18_000) == "UTC-5")
        #expect(text(-12_600) == "UTC-3:30")
    }

    @Test
    func timeZoneFollowsTheDaylightReferenceOrder() throws {
        // The device location's own zone wins over the snapshot's zone, as on the daylight card.
        let device = location("MA", timeZone: "Africa/Casablanca", latitude: 33.57, longitude: -7.59)
        let snapshot = makeSnapshot(countryCode: "MA", timeZone: "Europe/Madrid", deviceLocation: device)
        #expect(makeBriefing(snapshot: snapshot).time?.timeZoneIdentifier == "Africa/Casablanca")

        // Without coordinates it still reads the zones in the same order.
        let noCoordinates = location("MA", timeZone: "Africa/Casablanca", latitude: nil, longitude: nil)
        let bare = makeSnapshot(countryCode: "MA", timeZone: "Europe/Madrid", deviceLocation: noCoordinates)
        #expect(makeBriefing(snapshot: bare).time?.timeZoneIdentifier == "Africa/Casablanca")

        // A location without a zone falls back to the snapshot's.
        let noZone = location("MA", timeZone: nil, latitude: 33.57, longitude: -7.59)
        let fallback = makeSnapshot(countryCode: "MA", timeZone: "Africa/Casablanca", deviceLocation: noZone)
        #expect(makeBriefing(snapshot: fallback).time?.timeZoneIdentifier == "Africa/Casablanca")

        // Nothing usable: no time section.
        let none = makeSnapshot(countryCode: "MA", timeZone: "Invalid/Zone", deviceLocation: nil)
        #expect(makeBriefing(snapshot: none).time == nil)
    }

    // MARK: - Emergency

    @Test
    func emergencyIsOmittedForCountriesWithoutVerifiedNumbers() {
        let briefing = ArrivalBriefing.make(
            event: ArrivalEvent(countryCode: "LA", previousCountryCode: "TH", arrivedOn: stamp(0)),
            snapshot: makeSnapshot(countryCode: "LA", timeZone: "Asia/Vientiane"),
            settings: AppSettings(),
            homeTimeZoneIdentifier: nil,
            now: now,
            calendar: calendar,
            locale: locale
        )
        #expect(briefing.emergency == nil)
    }

    // MARK: - Embassy

    @Test
    func embassyIsTheNearestOwnMissionWithTheHotline() throws {
        var settings = AppSettings()
        settings.citizenshipCountryCodes = ["FI"]
        let embassy = try #require(makeBriefing(snapshot: moroccoSnapshot(), settings: settings).embassy)

        #expect(embassy.citizenshipCode == "FI")
        #expect(embassy.fallbackReason == nil)
        let mission = try #require(embassy.nearestMission)
        #expect(mission.mission.sendingCountry == "FI")
        #expect(mission.mission.hostCountry == "MA")
        #expect(mission.distanceKilometers != nil)
        #expect(embassy.consularContacts == ConsularContactsDirectory.contacts(forCitizenship: "FI"))
        #expect(embassy.consularContacts?.emergencyPhone == "+358 9 1605 5555")
    }

    @Test
    func embassyIsOmittedWithoutCitizenshipOrAtHome() {
        #expect(makeBriefing(snapshot: moroccoSnapshot(), settings: AppSettings()).embassy == nil)

        var moroccan = AppSettings()
        moroccan.citizenshipCountryCodes = ["MA"]
        #expect(makeBriefing(snapshot: moroccoSnapshot(), settings: moroccan).embassy == nil)
    }

    @Test
    func embassyKeepsTheHotlineWhenNoMissionIsKnown() throws {
        // A country with no bundled mission data for Finland but an official Finnish hotline.
        var settings = AppSettings()
        settings.citizenshipCountryCodes = ["FI"]
        let briefing = ArrivalBriefing.make(
            event: ArrivalEvent(countryCode: "ZZ", previousCountryCode: "ES", arrivedOn: stamp(0)),
            snapshot: makeSnapshot(countryCode: "ZZ", timeZone: "UTC"),
            settings: settings,
            homeTimeZoneIdentifier: nil,
            now: now,
            calendar: calendar,
            locale: locale
        )

        let embassy = try #require(briefing.embassy)
        #expect(embassy.nearestMission == nil)
        #expect(embassy.consularContacts != nil)
    }

    @Test
    func aDualCitizenAtHomeForOnePassportStillGetsTheOtherPassportsHelp() throws {
        var settings = AppSettings()
        settings.citizenshipCountryCodes = ["MA", "FI"]
        let embassy = try #require(makeBriefing(snapshot: moroccoSnapshot(), settings: settings).embassy)
        #expect(embassy.citizenshipCode == "FI")
    }

    // MARK: - Road and power

    @Test
    func drivingSideChangeIsFlagged() throws {
        let briefing = ArrivalBriefing.make(
            event: ArrivalEvent(countryCode: "GB", previousCountryCode: "FR", arrivedOn: stamp(0)),
            snapshot: makeSnapshot(countryCode: "GB", timeZone: "Europe/London"),
            settings: AppSettings(),
            homeTimeZoneIdentifier: nil,
            now: now,
            calendar: calendar,
            locale: locale
        )

        #expect(briefing.road == ArrivalBriefing.Road(side: .left, changesFromPreviousCountry: true))
        #expect(briefing.road?.text == "Drive on the left")
        #expect(briefing.power?.electricity.plugTypes == ["G"])
        #expect(briefing.power?.differsFromPreviousCountry == true)
        #expect(briefing.money?.currencyCode == "GBP")
        #expect(briefing.money?.changesFromPreviousCountry == true)
    }

    @Test
    func unknownPreviousCountryDataNeverFlagsAChange() throws {
        let briefing = ArrivalBriefing.make(
            event: ArrivalEvent(countryCode: "GB", previousCountryCode: "ZZ", arrivedOn: stamp(0)),
            snapshot: makeSnapshot(countryCode: "GB", timeZone: "Europe/London"),
            settings: AppSettings(),
            homeTimeZoneIdentifier: nil,
            now: now,
            calendar: calendar,
            locale: locale
        )

        #expect(briefing.road?.changesFromPreviousCountry == false)
        #expect(briefing.power?.differsFromPreviousCountry == false)
        #expect(briefing.money?.changesFromPreviousCountry == false)
    }

    @Test
    func sectionsWithoutReferenceDataAreOmitted() {
        let briefing = ArrivalBriefing.make(
            event: ArrivalEvent(countryCode: "JP", previousCountryCode: "ES", arrivedOn: stamp(0)),
            snapshot: makeSnapshot(countryCode: "JP", timeZone: "Asia/Tokyo"),
            settings: AppSettings(),
            homeTimeZoneIdentifier: nil,
            now: now,
            calendar: calendar,
            locale: locale
        )

        #expect(briefing.road?.side == .left)
        #expect(briefing.power == nil) // 50 Hz east, 60 Hz west: not verifiable as one supply
        #expect(briefing.money?.currencyCode == "JPY")
    }

    // MARK: - Holiday

    @Test
    func holidayTodayOrTomorrowIsIncluded() throws {
        let today = makeBriefing(snapshot: moroccoSnapshot(holiday: holiday(dayOffset: 0, name: "Green March")))
        #expect(today.holiday == ArrivalBriefing.Holiday(name: "Green March", daysFromToday: 0))

        let tomorrow = makeBriefing(snapshot: moroccoSnapshot(holiday: holiday(dayOffset: 1, name: "Independence Day")))
        #expect(tomorrow.holiday == ArrivalBriefing.Holiday(name: "Independence Day", daysFromToday: 1))
    }

    @Test
    func holidaysFurtherOutOrFromAnotherCountryAreOmitted() {
        #expect(makeBriefing(snapshot: moroccoSnapshot(holiday: holiday(dayOffset: 2))).holiday == nil)
        #expect(makeBriefing(snapshot: moroccoSnapshot(holiday: holiday(dayOffset: -1))).holiday == nil)
        #expect(makeBriefing(snapshot: moroccoSnapshot(holiday: nil)).holiday == nil)

        // Local info that still belongs to Spain must not leak into the Morocco briefing.
        let stale = makeSnapshot(
            countryCode: "MA",
            timeZone: "Africa/Casablanca",
            localInfo: localInfo(countryCode: "ES", holiday: holiday(dayOffset: 0, name: "Fiesta"))
        )
        #expect(makeBriefing(snapshot: stale).holiday == nil)
    }

    @Test
    func holidayUsesTheInjectedCalendarDay() {
        // 23:00 UTC on the eve of a holiday that starts at UTC midnight: tomorrow in UTC, but already
        // the holiday itself in Auckland (UTC+13 in October). The injected calendar decides.
        let snapshot = moroccoSnapshot(holiday: holiday(dayOffset: 0, name: "Green March"))
        let evening = now.addingTimeInterval(-13 * 3_600)
        var auckland = calendar
        auckland.timeZone = TimeZone(identifier: "Pacific/Auckland")!

        func daysFromToday(using calendar: Calendar) -> Int? {
            ArrivalBriefing.make(
                event: ArrivalEvent(countryCode: "MA", previousCountryCode: "ES", arrivedOn: stamp(0)),
                snapshot: snapshot,
                settings: AppSettings(),
                homeTimeZoneIdentifier: nil,
                now: evening,
                calendar: calendar,
                locale: locale
            ).holiday?.daysFromToday
        }

        #expect(daysFromToday(using: calendar) == 1)
        #expect(daysFromToday(using: auckland) == 0)
    }

    // MARK: - Local rhythm

    // Reference (2027): Ramadan 8 Feb - 8 Mar, Eid al-Fitr 9-11 Mar, Nyepi 8 Mar.

    @Test
    func rhythmListsThePeriodsOnNowOrStartingWithinFourteenDays() throws {
        let during = try #require(rhythmBriefing(country: "MA", on: 2027, 2, 19).rhythm.first)
        #expect(during.kind == .ramadan)
        #expect(during.countryCode == "MA")

        #expect(rhythmKinds(country: "MA", on: 2027, 1, 25) == [.ramadan]) // starts in 14 days
        #expect(rhythmKinds(country: "MA", on: 2027, 1, 24).isEmpty) // 15 days
        #expect(rhythmKinds(country: "MA", on: 2026, 10, 12).isEmpty)
        #expect(rhythmKinds(country: "ES", on: 2027, 2, 19).isEmpty)
    }

    @Test
    func rhythmIsEarliestFirstAndFollowsTheArrivalCountryNotTheSnapshot() {
        // The snapshot still describes Morocco while the traveller has just arrived in Saudi Arabia.
        let lagging = rhythmBriefing(country: "SA", on: 2027, 3, 7, snapshot: moroccoSnapshot())
        #expect(lagging.rhythm.map(\.kind) == [.ramadan, .eidAlFitr])
        #expect(lagging.rhythm.allSatisfy { $0.countryCode == "SA" })
    }

    @Test
    func nyepiIsOnlyListedForBaliOrAnUnknownRegion() {
        func kinds(_ deviceLocation: IPLocationSnapshot?) -> [LocalRhythmKind] {
            rhythmKinds(country: "ID", on: 2027, 3, 5, snapshot: makeSnapshot(
                countryCode: "ID", timeZone: "Asia/Makassar", deviceLocation: deviceLocation
            ))
        }

        #expect(kinds(location("ID", timeZone: nil, latitude: nil, longitude: nil, region: "Bali"))
            == [.ramadan, .nyepi, .eidAlFitr])
        #expect(kinds(location("ID", timeZone: nil, latitude: nil, longitude: nil, region: "Jakarta"))
            == [.ramadan, .eidAlFitr])
        // Unknown region: kept, as its name already says "Bali".
        #expect(kinds(location("ID", timeZone: nil, latitude: nil, longitude: nil)) == [.ramadan, .nyepi, .eidAlFitr])
        #expect(kinds(nil) == [.ramadan, .nyepi, .eidAlFitr])
        // A region of the previous country (a refresh that lags behind the crossing) says nothing about Indonesia.
        #expect(kinds(location("ES", timeZone: nil, latitude: nil, longitude: nil, region: "Andalusia"))
            == [.ramadan, .nyepi, .eidAlFitr])
    }

    // MARK: - Advisory

    @Test
    func advisoryAtCautionOrWorseIsIncluded() throws {
        let caution = makeBriefing(snapshot: moroccoSnapshot(alerts: alerts(severity: .caution, countryCode: "MA")))
        let advisory = try #require(caution.advisory)
        #expect(advisory.severity == .caution)
        #expect(advisory.summary == "Exercise a high degree of caution.")
        #expect(advisory.sourceName == "Smartraveller")

        let critical = makeBriefing(snapshot: moroccoSnapshot(alerts: alerts(severity: .critical, countryCode: "MA")))
        #expect(critical.advisory?.severity == .critical)
    }

    @Test
    func advisoryBelowCautionNotReadyOrForAnotherCountryIsOmitted() {
        for severity in [TravelAlertSeverity.clear, .info] {
            #expect(makeBriefing(snapshot: moroccoSnapshot(alerts: alerts(severity: severity, countryCode: "MA"))).advisory == nil)
        }
        for status in [TravelAlertSignalStatus.checking, .stale, .unavailable] {
            #expect(makeBriefing(snapshot: moroccoSnapshot(alerts: alerts(severity: .warning, countryCode: "MA", status: status))).advisory == nil)
        }
        // Alerts that are still about Spain.
        #expect(makeBriefing(snapshot: moroccoSnapshot(alerts: alerts(severity: .warning, countryCode: "ES"))).advisory == nil)
        // Advisories switched off.
        #expect(makeBriefing(snapshot: moroccoSnapshot(alerts: alerts(severity: .warning, countryCode: "MA", enabledKinds: [.weather]))).advisory == nil)
    }

    // MARK: - Data Guard

    @Test
    func dataGuardHintOnlyWhenEnabledButNotMonitoring() {
        let hint = "On a local SIM or roaming? Turn on Data Guard monitoring."

        let idle = makeBriefing(snapshot: moroccoSnapshot(metered: metered(isEnabled: true, isActive: false)))
        #expect(idle.dataGuardHint == hint)
        #expect(ArrivalBriefing.dataGuardHintText == hint)

        #expect(makeBriefing(snapshot: moroccoSnapshot(metered: metered(isEnabled: true, isActive: true))).dataGuardHint == nil)
        #expect(makeBriefing(snapshot: moroccoSnapshot(metered: metered(isEnabled: false, isActive: false))).dataGuardHint == nil)
        #expect(makeBriefing(snapshot: moroccoSnapshot()).dataGuardHint == nil)
    }

    // MARK: - Preview fixture

    @Test
    func previewSnapshotComposesWithoutCrashingAndKeepsSectionsOptional() throws {
        let briefing = ArrivalBriefing.make(
            event: ArrivalEvent(countryCode: "ES", previousCountryCode: "FR", arrivedOn: stamp(0)),
            snapshot: .preview,
            settings: AppSettings(),
            homeTimeZoneIdentifier: "Europe/Helsinki",
            now: now,
            calendar: calendar,
            locale: locale
        )

        #expect(briefing.title == "Welcome to Spain")
        #expect(briefing.time?.timeZoneIdentifier == "Europe/Madrid")
        #expect(briefing.embassy == nil)
        #expect(briefing.emergency?.other == [EmergencyService(name: "Guardia Civil", number: "062")])
        // The preview advisory is about nearby France, not Spain itself.
        #expect(briefing.advisory != nil || DashboardSnapshot.preview.travelAlerts?.primaryCountryCode != "ES")
    }

    // MARK: - Helpers

    private func stamp(_ daysAgo: Int) -> VisitedCountryDayStamp {
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        return VisitedCountryDayStamp(date: date, calendar: calendar)
    }

    private func day(_ daysAgo: Int, _ code: String) -> VisitedCountryDay {
        VisitedCountryDay(
            day: stamp(daysAgo),
            country: code,
            countryCode: code,
            source: .deviceLocation,
            isInferred: false
        )
    }

    private func detect(
        days: [VisitedCountryDay],
        current: String?,
        settings: AppSettings = AppSettings()
    ) -> ArrivalEvent? {
        ArrivalDetector.arrival(
            countryDays: days,
            currentCountryCode: current,
            settings: settings,
            now: now,
            calendar: calendar
        )
    }

    private func makeBriefing(
        snapshot: DashboardSnapshot,
        settings: AppSettings = AppSettings(),
        home: String? = nil,
        at date: Date? = nil
    ) -> ArrivalBriefing {
        ArrivalBriefing.make(
            event: ArrivalEvent(countryCode: "MA", previousCountryCode: "ES", arrivedOn: stamp(0)),
            snapshot: snapshot,
            settings: settings,
            homeTimeZoneIdentifier: home,
            now: date ?? now,
            calendar: calendar,
            locale: locale
        )
    }

    private func location(
        _ countryCode: String,
        timeZone: String?,
        latitude: Double?,
        longitude: Double?,
        region: String? = nil
    ) -> IPLocationSnapshot {
        IPLocationSnapshot(
            city: nil,
            region: region,
            country: nil,
            countryCode: countryCode,
            latitude: latitude,
            longitude: longitude,
            timeZone: timeZone,
            provider: "test",
            fetchedAt: now
        )
    }

    private func rhythmBriefing(
        country: String,
        on year: Int, _ month: Int, _ day: Int,
        snapshot: DashboardSnapshot? = nil
    ) -> ArrivalBriefing {
        ArrivalBriefing.make(
            event: ArrivalEvent(countryCode: country, previousCountryCode: "FR", arrivedOn: stamp(0)),
            snapshot: snapshot ?? makeSnapshot(countryCode: country, timeZone: "UTC"),
            settings: AppSettings(),
            homeTimeZoneIdentifier: nil,
            now: calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!,
            calendar: calendar,
            locale: locale
        )
    }

    private func rhythmKinds(
        country: String,
        on year: Int, _ month: Int, _ day: Int,
        snapshot: DashboardSnapshot? = nil
    ) -> [LocalRhythmKind] {
        rhythmBriefing(country: country, on: year, month, day, snapshot: snapshot).rhythm.map(\.kind)
    }

    private func moroccoSnapshot(
        holiday: HolidayPeriodSnapshot? = nil,
        alerts: TravelAlertsSnapshot? = nil,
        metered: MeteredUsageSnapshot = .disabled
    ) -> DashboardSnapshot {
        makeSnapshot(
            countryCode: "MA",
            timeZone: "Africa/Casablanca",
            deviceLocation: location("MA", timeZone: "Africa/Casablanca", latitude: 33.5731, longitude: -7.5898),
            localInfo: holiday.map { localInfo(countryCode: "MA", holiday: $0) },
            alerts: alerts,
            metered: metered
        )
    }

    private func makeSnapshot(
        countryCode: String,
        timeZone: String,
        deviceLocation: IPLocationSnapshot? = nil,
        localInfo: LocalInfoSnapshot? = nil,
        alerts: TravelAlertsSnapshot? = nil,
        metered: MeteredUsageSnapshot = .disabled
    ) -> DashboardSnapshot {
        DashboardSnapshot(
            network: NetworkSectionSnapshot(
                throughput: nil,
                connectivity: .checking,
                latency: nil,
                downloadHistory: [],
                uploadHistory: [],
                latencyHistory: []
            ),
            power: PowerSectionSnapshot(snapshot: nil, chargeHistory: [], dischargeHistory: []),
            travelContext: TravelContextSnapshot(
                wifi: nil,
                vpn: nil,
                timeZoneIdentifier: timeZone,
                deviceLocation: deviceLocation,
                publicIP: nil,
                location: nil
            ),
            travelAlerts: alerts,
            weather: nil,
            localInfo: localInfo,
            appState: AppStatusSnapshot(lastRefresh: nil, updateState: .idle, issues: []),
            meteredData: metered
        )
    }

    private func holiday(dayOffset: Int, name: String = "Holiday") -> HolidayPeriodSnapshot {
        let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: dayOffset, to: now)!)
        return HolidayPeriodSnapshot(name: name, startDate: start, endDate: start)
    }

    private func localInfo(countryCode: String, holiday: HolidayPeriodSnapshot) -> LocalInfoSnapshot {
        let isCurrent = calendar.isDate(holiday.startDate, inSameDayAs: now)
        return LocalInfoSnapshot(
            status: .ready,
            locality: nil,
            administrativeRegion: nil,
            countryCode: countryCode,
            countryName: nil,
            timeZoneIdentifier: nil,
            subdivisionCode: nil,
            publicHolidayStatus: LocalHolidayStatus(
                state: isCurrent ? .current : .upcoming,
                currentPeriod: isCurrent ? holiday : nil,
                nextPeriod: isCurrent ? nil : holiday,
                note: nil
            ),
            schoolHolidayStatus: nil,
            localPriceLevel: nil,
            sources: [],
            fetchedAt: now,
            detail: nil,
            note: nil
        )
    }

    private func alerts(
        severity: TravelAlertSeverity,
        countryCode: String,
        status: TravelAlertSignalStatus = .ready,
        enabledKinds: [TravelAlertKind] = [.advisory]
    ) -> TravelAlertsSnapshot {
        let signal = TravelAlertSignalSnapshot(
            kind: .advisory,
            severity: severity,
            title: "Travel advisory",
            summary: " Exercise a high degree of caution. ",
            sourceName: "Smartraveller",
            sourceURL: nil,
            updatedAt: now,
            affectedCountryCodes: [countryCode]
        )
        return TravelAlertsSnapshot(
            enabledKinds: enabledKinds,
            primaryCountryCode: countryCode,
            primaryCountryName: nil,
            coverageCountryCodes: [countryCode],
            states: [
                TravelAlertSignalState(
                    kind: .advisory,
                    status: status,
                    signal: signal,
                    reason: nil,
                    sourceName: "Smartraveller",
                    sourceURL: nil,
                    lastAttemptedAt: now,
                    lastSuccessAt: now
                )
            ],
            fetchedAt: now
        )
    }

    private func metered(isEnabled: Bool, isActive: Bool) -> MeteredUsageSnapshot {
        MeteredUsageSnapshot(
            isFeatureEnabled: isEnabled,
            isMonitoringActive: isActive,
            networkKey: nil,
            networkDisplayName: nil,
            meteredInterfaceName: nil,
            sessionStartedAt: nil,
            sessionBytesReceived: 0,
            sessionBytesSent: 0,
            periodBytesReceived: 0,
            periodBytesSent: 0,
            capBytes: nil,
            usageFraction: nil,
            isCapReached: false,
            billingPeriod: .session,
            manualSessionEnabled: false,
            isKnownMeteredNetwork: false,
            networkNameSource: .unknown,
            isWiFiConnected: false,
            needsLocationForWiFiNames: false,
            statusMessage: nil,
            capAlertSignal: nil
        )
    }
}
