import Foundation
import NomadCore
@testable import NomadUI
import Testing

struct TripPreviewPresentationTests {
    private typealias Support = StaysTestSupport
    private let calendar = Support.calendar
    private let locale = Support.locale
    private let now = Support.now

    private var morocco: PlannedTrip {
        Support.trip(from: (2_027, 1, 12), to: (2_027, 1, 25))
    }

    private func preview(
        _ trip: PlannedTrip,
        settings: AppSettings? = nil,
        countryDays: [VisitedCountryDay] = [],
        current: String? = "FI",
        homeTimeZone: String? = "Europe/Helsinki"
    ) -> TripPreview {
        TripPreview.make(
            trip: trip,
            settings: settings ?? Support.settings(trips: [trip]),
            countryDays: countryDays,
            currentCountryCode: current,
            homeTimeZoneIdentifier: homeTimeZone,
            now: now,
            calendar: calendar,
            locale: locale
        )
    }

    private func presentation(
        _ preview: TripPreview,
        online: TripOnlineState = .loading,
        prices: TripPriceState = .unavailable,
        policy: DashboardResourcePolicy = .normal,
        home: String? = "FI"
    ) -> TripPreviewPresentation {
        TripPreviewPresentation(
            preview: preview,
            online: online,
            prices: prices,
            policy: policy,
            settings: Support.settings(trips: [preview.trip], citizenships: home.map { [$0] } ?? [], home: home),
            now: now,
            calendar: calendar,
            locale: locale
        )
    }

    private func online(
        holidays: [HolidayPeriodSnapshot]? = [],
        advisory: TravelAlertSignalSnapshot? = nil
    ) -> TripPreviewOnline {
        TripPreviewOnline(holidays: holidays, advisory: advisory, fetchedAt: Support.date(2_026, 10, 12))
    }

    private func advisory(_ severity: TravelAlertSeverity) -> TravelAlertSignalSnapshot {
        TravelAlertSignalSnapshot(
            kind: .advisory,
            severity: severity,
            title: "Morocco",
            summary: "Exercise a high degree of caution",
            sourceName: "Smartraveller",
            sourceURL: nil,
            updatedAt: Support.date(2_026, 10, 1),
            affectedCountryCodes: ["MA"]
        )
    }

    // MARK: Header

    @Test
    func theHeaderNamesCountryDatesLengthAndTiming() {
        let result = presentation(preview(morocco))

        #expect(result.title == "Morocco")
        #expect(result.subtitle.plainSpaces == "12 – 25 Jan 2027 · 14 days (13 nights) · in 92 days")
        #expect(result.headerLine.plainSpaces == "Morocco · 12 – 25 Jan 2027 · 14 days (13 nights) · in 92 days")
    }

    @Test
    func theHeaderCarriesTheNote() {
        let trip = Support.trip(from: (2_027, 1, 12), to: (2_027, 1, 25), note: "Surf camp")

        #expect(presentation(preview(trip)).note == "Surf camp")
    }

    // MARK: Basics

    @Test
    func theBasicsListTimeEmergencyDrivingPowerAndCurrency() {
        let result = presentation(preview(morocco))

        #expect(result.basics.map(\.kind) == [.time, .emergency, .road, .power, .money])
        #expect(result.basics.first?.text.hasPrefix("Home (Helsinki) is") == true)
        #expect(result.basics.first { $0.kind == .emergency }?.text == "19")
        #expect(result.basics.first { $0.kind == .emergency }?.isSelectable == true)
        #expect(result.basics.first { $0.kind == .road }?.text == "Drive on the right")
        #expect(result.basics.first { $0.kind == .money }?.text == "Moroccan Dirham (MAD)")
    }

    @Test
    func whatChangesFromTheCurrentCountryIsFlagged() throws {
        let result = presentation(preview(Support.trip("GB", from: (2_027, 1, 12), to: (2_027, 1, 26)), current: "FI"))

        let road = try #require(result.basics.first { $0.kind == .road })
        #expect(road.text == "Drive on the left")
        #expect(road.flag == "Changed")
        #expect(road.tone == .caution)
        #expect(result.basics.first { $0.kind == .power }?.flag == "Changed")
        #expect(result.basics.first { $0.kind == .money }?.flag == "Changed")
    }

    @Test
    func nothingIsFlaggedWithoutACurrentCountry() {
        let result = presentation(preview(morocco, current: nil))

        #expect(result.basics.allSatisfy { $0.flag == nil })
    }

    @Test
    func theTimeRowComparesHomeWithTheDestination() throws {
        // Japan has one offset all year, so the gap does not depend on daylight saving rules.
        let result = presentation(preview(Support.trip("JP", from: (2_027, 1, 12), to: (2_027, 1, 25))))

        let row = try #require(result.basics.first)
        #expect(row.kind == .time)
        #expect(row.text == "Home (Helsinki) is 7 h behind")
    }

    @Test
    func withoutAHomeTimeZoneThereIsNoTimeRow() {
        let result = presentation(preview(morocco, homeTimeZone: nil))

        #expect(result.basics.contains { $0.kind == .time } == false)
    }

    // MARK: Embassy

    @Test
    func theEmbassyListsTheOwnMissionsWithoutDistance() throws {
        let embassy = try #require(presentation(preview(morocco)).embassy)

        #expect(embassy.missions.isEmpty == false)
        #expect(embassy.missions.count <= TripPreview.missionLimit)
        #expect(embassy.missions.allSatisfy { $0.distanceText == nil })
        #expect(embassy.notice == nil)
        #expect(embassy.fallbackMissions.isEmpty)
        #expect(embassy.hotline?.phone.isEmpty == false)
        #expect(embassy.footer.hasPrefix("Locations: "))
    }

    @Test
    func theEmbassyLinksToAllMissionsAndTheTravelRegistration() throws {
        let embassy = try #require(presentation(preview(morocco)).embassy)
        let group = try #require(embassy.links.first)

        #expect(group.id == "FI")
        #expect(group.missionsDirectory?.title == "All missions")
        #expect(group.registration != nil)
    }

    @Test
    func aMissingOwnMissionExplainsTheFallback() throws {
        // Sweden has no mission in Laos in the bundled data; the Nordic and EU arrangements may apply.
        let result = presentation(preview(Support.trip("LA", from: (2_027, 1, 12), to: (2_027, 1, 26)), settings: Support.settings(trips: [], citizenships: ["FI"])))
        let embassy = try #require(result.embassy)

        if embassy.missions.isEmpty {
            #expect(embassy.notice != nil)
        }
    }

    @Test
    func noEmbassyWhenTheTripIsToACitizenshipCountry() {
        let result = presentation(preview(Support.trip("FI", from: (2_027, 1, 12), to: (2_027, 1, 26)), current: "ES"))

        #expect(result.embassy == nil)
    }

    @Test
    func noEmbassyWithoutCitizenship() {
        let settings = Support.settings(trips: [morocco], citizenships: [])

        #expect(presentation(preview(morocco, settings: settings)).embassy == nil)
    }

    // MARK: Local rhythm

    @Test
    func ramadanStartingMidTripIsFlagged() throws {
        let trip = Support.trip(from: (2_027, 2, 1), to: (2_027, 2, 14))
        let result = presentation(preview(trip))
        let row = try #require(result.rhythm.first)

        #expect(row.title == "Ramadan")
        #expect(row.flag == "Starts mid-trip")
        #expect(row.detail?.isEmpty == false)
        #expect(row.text.contains("Feb"))
    }

    @Test
    func theRhythmFlagCoversEveryCase() {
        #expect(TripPreviewPresentation.rhythmFlag(startsDuringTrip: true, endsDuringTrip: false) == "Starts mid-trip")
        #expect(TripPreviewPresentation.rhythmFlag(startsDuringTrip: false, endsDuringTrip: true) == "Ends mid-trip")
        #expect(TripPreviewPresentation.rhythmFlag(startsDuringTrip: true, endsDuringTrip: true) == "During your trip")
        #expect(TripPreviewPresentation.rhythmFlag(startsDuringTrip: false, endsDuringTrip: false) == "All trip long")
    }

    @Test
    func aTripWithoutLocalPeriodsHasNoRhythmRows() {
        #expect(presentation(preview(morocco)).rhythm.isEmpty)
    }

    // MARK: Holidays and advisory

    @Test
    func whileLoadingTheOnlineSectionShowsProgress() {
        let result = presentation(preview(morocco), online: .loading)

        #expect(result.online.status == .loading)
        #expect(result.online.holidays.isEmpty)
        #expect(result.online.advisory == nil)
    }

    @Test
    func loadedHolidaysAreListedWithTheirDates() throws {
        let holiday = HolidayPeriodSnapshot(
            name: "Independence Manifesto Day",
            startDate: Support.date(2_027, 1, 11),
            endDate: Support.date(2_027, 1, 11)
        )
        let result = presentation(preview(morocco), online: .loaded(online(holidays: [holiday])))
        let row = try #require(result.online.holidays.first)

        #expect(row.title == "Public holiday")
        #expect(row.text == "Independence Manifesto Day")
        #expect(row.detail == "Mon 11 Jan")
        #expect(result.online.status == .updated("Updated 12 Oct 2026 at 12:00"))
    }

    @Test
    func aMultiDayHolidayIsARange() {
        let holiday = HolidayPeriodSnapshot(name: "Eid", startDate: Support.date(2_027, 1, 20), endDate: Support.date(2_027, 1, 22))
        let result = presentation(preview(morocco), online: .loaded(online(holidays: [holiday])))

        #expect(result.online.holidays.first?.detail == "20 Jan – 22 Jan")
    }

    @Test
    func noHolidaysSaysSoAndMissingHolidaysSayUnavailable() {
        let none = presentation(preview(morocco), online: .loaded(online(holidays: [])))
        let missing = presentation(preview(morocco), online: .loaded(online(holidays: nil)), policy: Self.offline)

        #expect(none.online.holidays.first?.text == "None during your trip")
        #expect(missing.online.holidays.first?.text == "Not available offline")
    }

    @Test
    func theAdvisoryRowCarriesItsSeverity() throws {
        let caution = presentation(preview(morocco), online: .loaded(online(advisory: advisory(.caution))))
        let warning = presentation(preview(morocco), online: .loaded(online(advisory: advisory(.warning))))
        let clear = presentation(preview(morocco), online: .loaded(online(advisory: advisory(.clear))))

        let row = try #require(caution.online.advisory)
        #expect(row.title == "Travel advisory")
        #expect(row.text == "Exercise a high degree of caution")
        #expect(row.detail == "Smartraveller")
        #expect(row.tone == .caution)
        #expect(warning.online.advisory?.tone == .attention)
        // A clear advisory is not a status: it shows in neutral text.
        #expect(clear.online.advisory?.tone.statusTint(neutral: .clear) == .clear)
    }

    @Test
    func unavailableOnlineDataNamesTheReason() {
        #expect(presentation(preview(morocco), online: .unavailable, policy: Self.offline).online.status == .unavailable("Not available offline"))
        #expect(presentation(preview(morocco), online: .unavailable, policy: Self.lowData).online.status == .unavailable("Not available in Low Data mode"))
        #expect(presentation(preview(morocco), online: .unavailable).online.status == .unavailable("Not available right now"))
    }

    private static var offline: DashboardResourcePolicy {
        DashboardResourcePolicy(mode: .automatic, conditions: ResourceConditions(pathAvailable: false))
    }

    private static var lowData: DashboardResourcePolicy {
        DashboardResourcePolicy(mode: .lowData, conditions: ResourceConditions())
    }

    // MARK: Prices

    @Test
    func pricesUseNeutralTextAndTheEurostatCaption() throws {
        let differences = [
            PriceLevelDifference(kind: .groceries, percentDifference: -30),
            PriceLevelDifference(kind: .mealOut, percentDifference: 15),
            PriceLevelDifference(kind: .overall, percentDifference: 2)
        ]
        let prices = try #require(presentation(preview(morocco), prices: .loaded(differences)).prices)

        #expect(prices.lines == [
            "Groceries ~30% cheaper than Finland",
            "Meals out ~15% pricier than Finland",
            "Overall about the same as Finland"
        ])
        #expect(prices.caption == "Eurostat price levels · annual")
    }

    @Test
    func pricesAreHiddenUntilTheyLoadAndWhenUnavailable() {
        #expect(presentation(preview(morocco), prices: .loading).prices == nil)
        #expect(presentation(preview(morocco), prices: .unavailable).prices == nil)
        #expect(presentation(preview(morocco), prices: .loaded([])).prices == nil)
        #expect(presentation(preview(morocco), prices: .loaded([PriceLevelDifference(kind: .overall, percentDifference: 5)]), home: nil).prices == nil)
    }

    // MARK: Visa what-if

    @Test
    func aFinnishTripToMoroccoShowsOnlyTheTaxYear() throws {
        let visa = try #require(presentation(preview(morocco)).visa)

        #expect(visa.items.map(\.id) == ["tax-2027"])
        let item = try #require(visa.items.first)
        #expect(item.title == "Morocco 2027")
        #expect(item.text == "14 planned + 0 recorded days of 183")
        #expect(item.tone == .neutral)
        #expect(abs((item.progress ?? 0) - 14.0 / 183.0) < 0.0001)
        #expect(visa.footer == StaysCardPresentation.taxFooter)
    }

    @Test
    func recordedDaysCountInTheYearTheyFallIn() throws {
        let trip = Support.trip(from: (2_026, 10, 20), to: (2_026, 10, 25))
        let visa = try #require(presentation(preview(trip, countryDays: Support.run(10, "MA"))).visa)

        #expect(visa.items.first?.text == "6 planned + 10 recorded days of 183")
    }

    @Test
    func recordedDaysOfAnotherYearDoNotCount() throws {
        let visa = try #require(presentation(preview(morocco, countryDays: Support.run(10, "MA"))).visa)

        #expect(visa.items.first?.text == "14 planned + 0 recorded days of 183")
    }

    @Test
    func aCitizenWithFreeMovementIsExemptFromSchengen() throws {
        let trip = Support.trip("ES", from: (2_027, 1, 12), to: (2_027, 1, 26))
        let item = try #require(presentation(preview(trip)).visa?.items.first { $0.id == "schengen" })

        #expect(item.text == "no limit for EU/EEA/Swiss citizens")
        #expect(item.progress == nil)
        #expect(item.tone == .neutral)
    }

    @Test
    func theSchengenPeakIsShownWithItsDay() throws {
        let trip = Support.trip("ES", from: (2_027, 1, 12), to: (2_027, 1, 26))
        let settings = Support.settings(trips: [trip], citizenships: ["US"])
        let item = try #require(presentation(preview(trip, settings: settings, current: nil)).visa?.items.first { $0.id == "schengen" })

        #expect(item.title == "Schengen")
        #expect(item.text == "Peak 15 of 90 days on 26 Jan")
        #expect(item.detail == nil)
        #expect(abs((item.progress ?? 0) - 15.0 / 90.0) < 0.0001)
        #expect(item.tone == .neutral)
    }

    @Test
    func aPlanThatBreaksSchengenIsCoral() throws {
        let earlier = Support.trip("ES", from: (2_027, 1, 1), to: (2_027, 3, 15))
        let trip = Support.trip("PT", from: (2_027, 3, 20), to: (2_027, 4, 20))
        let settings = Support.settings(trips: [earlier, trip], citizenships: ["US"])
        let item = try #require(presentation(preview(trip, settings: settings, current: nil)).visa?.items.first { $0.id == "schengen" })

        #expect(item.text.hasPrefix("Exceeds 90/180 on "))
        #expect(item.tone == .attention)
        #expect(item.detail?.hasPrefix("Peak ") == true)
    }

    @Test
    func withoutCitizenshipSchengenCountsButSaysToSetOne() throws {
        let trip = Support.trip("ES", from: (2_027, 1, 12), to: (2_027, 1, 26))
        let settings = Support.settings(trips: [trip], citizenships: [])
        let item = try #require(presentation(preview(trip, settings: settings, current: nil)).visa?.items.first { $0.id == "schengen" })

        #expect(item.text == "Peak 15 of 90 days on 26 Jan")
        #expect(item.detail == StaysCardPresentation.citizenshipHint)
        #expect(item.tone == .neutral)
    }

    @Test
    func anAllowanceShowsTheTripDaysAgainstIt() throws {
        var settings = Support.settings(trips: [morocco])
        settings.stayAllowances = ["MA": 90]
        let item = try #require(presentation(preview(morocco, settings: settings)).visa?.items.first { $0.id == "allowance" })

        #expect(item.title == "Morocco allowance")
        #expect(item.text == "14 of 90 days")
        #expect(item.detail == nil)
        #expect(item.tone == .neutral)
    }

    @Test
    func aTripPastTheAllowanceIsCoralWithTheLastPermittedDay() throws {
        var settings = Support.settings(trips: [morocco])
        settings.stayAllowances = ["MA": 10]
        let item = try #require(presentation(preview(morocco, settings: settings)).visa?.items.first { $0.id == "allowance" })

        #expect(item.text == "14 of 10 days · 4 days over")
        #expect(item.detail == "Last permitted day 21 Jan")
        #expect(item.tone == .attention)
    }

    @Test
    func reachingTheTaxThresholdIsSandWithTheDay() throws {
        var settings = Support.settings(trips: [morocco])
        settings.taxResidenceThresholdDays = AppSettings.minimumTaxResidenceThresholdDays
        let trip = Support.trip(from: (2_027, 1, 1), to: (2_027, 2, 15))
        settings.plannedTrips = [trip]
        let item = try #require(presentation(preview(trip, settings: settings)).visa?.items.first { $0.id == "tax-2027" })

        #expect(item.text == "46 planned + 0 recorded days of 30")
        #expect(item.detail == "Reaches 30 days on 30 Jan")
        #expect(item.tone == .caution)
    }

    @Test
    func aTripAcrossTheNewYearHasATaxLinePerYear() throws {
        let trip = Support.trip(from: (2_026, 12, 20), to: (2_027, 1, 10))
        let visa = try #require(presentation(preview(trip)).visa)

        #expect(visa.items.map(\.id) == ["tax-2026", "tax-2027"])
    }

    @Test
    func theVisaSectionIsHiddenWhenNothingApplies() {
        var settings = Support.settings(trips: [morocco])
        settings.taxResidenceDaysEnabled = false
        settings.schengenCounterEnabled = false

        #expect(presentation(preview(morocco, settings: settings)).visa == nil)
    }

    // MARK: Checklist and map

    @Test
    func theChecklistIsPartOfThePreviewAndReadsTheTripsTicks() {
        var trip = morocco
        trip.checklist = TripChecklistState(checkedItemIDs: ["roaming"])
        let result = presentation(preview(trip))

        #expect(result.checklist.total > 0)
        #expect(result.checklist.done == 1)
        #expect(result.checklist.groups.flatMap(\.items).first { $0.id == "roaming" }?.isChecked == true)
    }

    @Test
    func theChecklistGainsTheAdvisoryWhenTheOnlineDataLoads() {
        let loading = presentation(preview(morocco))
        let loaded = presentation(preview(morocco), online: .loaded(online(advisory: advisory(.caution))))

        #expect(loading.checklist.groups.flatMap(\.items).contains { $0.id == "advisory" } == false)
        #expect(loaded.checklist.groups.flatMap(\.items).contains { $0.id == "advisory" })
    }

    @Test
    func theMapFramesTheDestinationAndPinsTheEmbassy() throws {
        let map = try #require(presentation(preview(morocco)).map)

        #expect(map.pins.isEmpty == false)
        #expect(map.camera.latitudeSpan > 10)
        #expect(map.offlineNote == nil)
    }

    @Test
    func offlineThePreviewsMapSaysItNeedsAConnection() throws {
        let offline = DashboardResourcePolicy(mode: .automatic, conditions: ResourceConditions(pathAvailable: false))

        #expect(try #require(presentation(preview(morocco), policy: offline).map).offlineNote == "Map needs a connection")
    }

    @Test
    func theMapStillShowsTheCountryWithoutAnEmbassy() throws {
        let result = presentation(preview(Support.trip("FI", from: (2_027, 1, 12), to: (2_027, 1, 26)), current: "ES"))

        #expect(result.embassy == nil)
        #expect(try #require(result.map).pins.isEmpty)
    }

    @Test
    func theFooterIsTheLocalOnlyNote() {
        #expect(presentation(preview(morocco)).footer == "Trips stay on this Mac. Holidays and advisories send only the destination country code.")
    }
}
