import Foundation
import Testing
@testable import NomadCore

struct TripPreviewTests {
    private let now = Date(timeIntervalSince1970: 1_791_806_400) // 2026-10-12 14:00 Paris
    private let locale = Locale(identifier: "en_US")

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.locale = locale
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.startOfDay(for: calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!)
    }

    private func trip(_ code: String, _ from: (Int, Int, Int), _ to: (Int, Int, Int)) -> PlannedTrip {
        PlannedTrip(countryCode: code, startDate: day(from.0, from.1, from.2), endDate: day(to.0, to.1, to.2))
    }

    private func preview(
        _ trip: PlannedTrip,
        citizenships: [String] = ["FI"],
        current: String? = "ES",
        home: String? = "Europe/Helsinki",
        plan: [PlannedTrip]? = nil,
        days: [VisitedCountryDay] = []
    ) -> TripPreview {
        var settings = AppSettings(citizenshipCountryCodes: citizenships)
        settings.plannedTrips = plan ?? [trip]
        return TripPreview.make(
            trip: trip,
            settings: settings,
            countryDays: days,
            currentCountryCode: current,
            homeTimeZoneIdentifier: home,
            now: now,
            calendar: calendar,
            locale: locale
        )
    }

    // MARK: - Composition

    @Test
    func composesEverythingAvailableOfflineForATrip() throws {
        let trip = trip("MA", (2026, 11, 1), (2026, 11, 10))
        let preview = preview(trip)

        #expect(preview.trip == trip)
        #expect(preview.countryCode == "MA")
        #expect(preview.countryName == "Morocco")
        #expect(preview.title == "Morocco")
        #expect(preview.schedule == TripPreview.Schedule(dayCount: 10, nightCount: 9, daysUntilStart: 20, daysSinceEnd: -29))
        #expect(preview.schedule.isUpcoming)
        #expect(preview.emergency == EmergencyNumberDirectory.numbers(forCountryCode: "MA"))
        #expect(preview.emergency != nil)
        #expect(preview.road == ArrivalBriefing.Road(side: .right, changesFromPreviousCountry: false))
        #expect(preview.power?.electricity == TravelReferenceData.electricity(forCountryCode: "MA"))
        #expect(preview.money?.currencyCode == "MAD")
        #expect(preview.money?.currencyName != nil)
        let difference = try #require(preview.timeDifference)
        #expect(difference.homeCityName == "Helsinki")
        #expect(difference.text.hasPrefix("Home (Helsinki) is "))
    }

    @Test
    func theTimeDifferenceIsMeasuredOnTheFirstDayOfTheTrip() throws {
        // Dubai is UTC+4 all year; Helsinki is UTC+3 in July and UTC+2 in January.
        let summer = try #require(preview(trip("AE", (2027, 7, 10), (2027, 7, 20))).timeDifference)
        let winter = try #require(preview(trip("AE", (2027, 1, 10), (2027, 1, 20))).timeDifference)

        #expect(summer.text == "Home (Helsinki) is 1 h behind")
        #expect(winter.text == "Home (Helsinki) is 2 h behind")
    }

    @Test
    func noHomeTimeZoneMeansNoTimeDifference() {
        #expect(preview(trip("MA", (2026, 11, 1), (2026, 11, 10)), home: nil).timeDifference == nil)
    }

    @Test
    func theScheduleFollowsTheCalendarDaysAroundToday() {
        let ongoing = preview(trip("MA", (2026, 10, 10), (2026, 10, 14))).schedule
        #expect(ongoing == TripPreview.Schedule(dayCount: 5, nightCount: 4, daysUntilStart: -2, daysSinceEnd: -2))
        #expect(ongoing.isOngoing && ongoing.isUpcoming == false && ongoing.hasEnded == false)

        let today = preview(trip("MA", (2026, 10, 12), (2026, 10, 12))).schedule
        #expect(today.dayCount == 1 && today.nightCount == 0 && today.daysUntilStart == 0)
        #expect(today.isOngoing)

        let over = preview(trip("MA", (2026, 10, 1), (2026, 10, 5))).schedule
        #expect(over.hasEnded && over.isOngoing == false)
    }

    @Test
    func anUnknownCountryKeepsTheCodeAndOmitsTheSections() {
        let preview = preview(trip("ZZ", (2026, 11, 1), (2026, 11, 10)), citizenships: [])

        #expect(preview.countryName == "ZZ")
        #expect(preview.emergency == nil)
        #expect(preview.embassy == nil)
        #expect(preview.road == nil)
        #expect(preview.power == nil)
        #expect(preview.timeDifference == nil)
        #expect(preview.rhythm.isEmpty)
    }

    // MARK: - Changes compared with the current country

    @Test
    func driveSideVoltagePlugsAndCurrencyChangesAreFlaggedAgainstTheCurrentCountry() throws {
        let britain = preview(trip("GB", (2026, 11, 1), (2026, 11, 10)), current: "FR")

        #expect(britain.road == ArrivalBriefing.Road(side: .left, changesFromPreviousCountry: true))
        #expect(britain.road?.text == "Drive on the left")
        #expect(britain.power?.electricity.plugTypes == ["G"])
        #expect(britain.power?.differsFromPreviousCountry == true)
        #expect(britain.money?.currencyCode == "GBP")
        #expect(britain.money?.changesFromPreviousCountry == true)

        let sameAsHere = preview(trip("GB", (2026, 11, 1), (2026, 11, 10)), current: "GB")
        #expect(sameAsHere.road?.changesFromPreviousCountry == false)
        #expect(sameAsHere.power?.differsFromPreviousCountry == false)
        #expect(sameAsHere.money?.changesFromPreviousCountry == false)

        let unknownHere = preview(trip("GB", (2026, 11, 1), (2026, 11, 10)), current: nil)
        #expect(unknownHere.road?.changesFromPreviousCountry == false)
        #expect(unknownHere.power?.differsFromPreviousCountry == false)
        #expect(unknownHere.money?.changesFromPreviousCountry == false)
        #expect(unknownHere.money?.currencyCode == "GBP")
    }

    @Test
    func theEurozoneKeepsTheCurrency() {
        let portugal = preview(trip("PT", (2026, 11, 1), (2026, 11, 10)), current: "ES")

        #expect(portugal.money?.currencyCode == "EUR")
        #expect(portugal.money?.changesFromPreviousCountry == false)
    }

    // MARK: - Embassy

    @Test
    func yourOwnMissionsAreListedBestKindFirstWithoutDistances() throws {
        let embassy = try #require(preview(trip("MA", (2026, 11, 1), (2026, 11, 10)), citizenships: ["FI"]).embassy)

        #expect(embassy.citizenshipCode == "FI")
        #expect(embassy.ownMissions.isEmpty == false)
        #expect(embassy.ownMissions.count <= TripPreview.missionLimit)
        #expect(embassy.ownMissions.allSatisfy { $0.distanceKilometers == nil })
        #expect(embassy.ownMissions.allSatisfy { $0.mission.sendingCountry == "FI" && $0.mission.hostCountry == "MA" })
        #expect(embassy.fallbackMissions.isEmpty)
        #expect(embassy.fallbackReason == nil)
        #expect(embassy.consularContacts == ConsularContactsDirectory.contacts(forCitizenship: "FI"))
        // Embassy, consulate-general, consulate, ..., honorary last.
        let kinds = embassy.ownMissions.map(\.mission.kind)
        #expect(kinds == kinds.sorted { $0.rank < $1.rank })
        let expected = DiplomaticMissionDirectory.missions(of: "FI", in: "MA")
        #expect(embassy.ownMissions.map(\.mission) == Array(expected.prefix(TripPreview.missionLimit)))
    }

    @Test
    func aCountryWithoutYourMissionOffersTheNordicOrEUFallback() throws {
        // A host that has no Finnish mission in the bundled directory but some other Nordic or EU mission.
        let hosts = Set(DiplomaticMissionIndex.bundled.missions.map(\.hostCountry))
        let host = try #require(hosts.sorted().first { host in
            DiplomaticMissionDirectory.missions(of: "FI", in: host).isEmpty
                && ["SE", "DK", "NO", "IS"].contains { DiplomaticMissionDirectory.missions(of: $0, in: host).isEmpty == false }
        })

        let embassy = try #require(preview(trip(host, (2026, 11, 1), (2026, 11, 10)), citizenships: ["FI"]).embassy)

        #expect(embassy.ownMissions.isEmpty)
        #expect(embassy.fallbackMissions.isEmpty == false)
        #expect(embassy.fallbackMissions.allSatisfy { $0.distanceKilometers == nil && $0.mission.sendingCountry != "FI" })
        #expect(embassy.fallbackReason == .nordicCooperation)
    }

    @Test
    func theHotlineStaysWhenNoMissionIsKnown() throws {
        let embassy = try #require(preview(trip("ZZ", (2026, 11, 1), (2026, 11, 10)), citizenships: ["FI"]).embassy)

        #expect(embassy.ownMissions.isEmpty && embassy.fallbackMissions.isEmpty)
        #expect(embassy.consularContacts != nil)
    }

    @Test
    func noEmbassySectionWithoutCitizenshipOrAtHome() {
        #expect(preview(trip("MA", (2026, 11, 1), (2026, 11, 10)), citizenships: []).embassy == nil)
        #expect(preview(trip("MA", (2026, 11, 1), (2026, 11, 10)), citizenships: ["MA"]).embassy == nil)
        #expect(preview(trip("MA", (2026, 11, 1), (2026, 11, 10)), citizenships: ["MA", "FI"]).embassy?.citizenshipCode == "FI")
    }

    // MARK: - Local rhythm

    @Test
    func rhythmPeriodsOverlappingTheTripCarryWhereTheyFall() throws {
        // Saudi Arabia 1-10 Mar 2027: Ramadan is 8 Feb - 8 Mar and Eid al-Fitr starts on 9 Mar.
        let preview = preview(trip("SA", (2027, 3, 1), (2027, 3, 10)))

        #expect(preview.rhythm.map(\.period.kind) == [.ramadan, .eidAlFitr])
        let ramadan = try #require(preview.rhythm.first)
        #expect(ramadan.startsDuringTrip == false)
        #expect(ramadan.endsDuringTrip)
        #expect(ramadan.id == ramadan.period.id)
        let eid = try #require(preview.rhythm.last)
        #expect(eid.startsDuringTrip)
        #expect(eid.endsDuringTrip == false)
    }

    @Test
    func aPeriodThatStartsMidTripIsFlaggedAsSuch() throws {
        let ramadan = try #require(preview(trip("SA", (2027, 2, 1), (2027, 2, 20))).rhythm.first)

        #expect(ramadan.period.kind == .ramadan)
        #expect(ramadan.startsDuringTrip)
        #expect(ramadan.endsDuringTrip == false)
    }

    @Test
    func aTripToBaliKeepsNyepiBecauseThereIsNoRegion() {
        let preview = preview(trip("ID", (2027, 3, 5), (2027, 3, 12)))

        #expect(preview.rhythm.map(\.period.kind).contains(.nyepi))
    }

    @Test
    func aTripOutsideEveryPeriodHasNoRhythm() {
        #expect(preview(trip("SA", (2026, 11, 1), (2026, 11, 10))).rhythm.isEmpty)
    }

    // MARK: - Visa what-if

    @Test
    func theVisaOutlookAppliesAllPlannedTripsAndTheRecordedDays() throws {
        let november = trip("FR", (2026, 11, 1), (2026, 11, 30))
        let december = trip("IT", (2026, 12, 20), (2027, 1, 20))
        var settings = AppSettings(citizenshipCountryCodes: ["US"], stayAllowances: ["IT": 30])
        settings.plannedTrips = [november, december]

        let preview = TripPreview.make(
            trip: december,
            settings: settings,
            countryDays: [],
            currentCountryCode: "GB",
            homeTimeZoneIdentifier: nil,
            now: now,
            calendar: calendar,
            locale: locale
        )

        let window = try #require(preview.visa.schengen?.window)
        #expect(window.usedDaysBeforeTrip == 30)
        #expect(window.peakUsedDays == 62)
        #expect(preview.visa.allowance?.overstayDays == 2)
        #expect(preview.visa.taxYears.map(\.year) == [2026, 2027])
    }

    @Test
    func anExemptCitizenIsMarkedExempt() {
        #expect(preview(trip("ES", (2026, 11, 1), (2026, 11, 10)), citizenships: ["FI"]).visa.schengen == .exempt)
    }

    @Test
    func theLiveCountryCountsTodayInTheVisaOutlook() throws {
        let today = trip("FR", (2026, 10, 12), (2026, 10, 14))

        let window = try #require(preview(today, citizenships: ["US"], current: "FR").visa.schengen?.window)

        #expect(window.tripSchengenDays == 3)
    }
}
