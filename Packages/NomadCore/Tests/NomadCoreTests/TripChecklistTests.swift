import Foundation
import Testing
@testable import NomadCore

struct TripChecklistTests {
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

    private func settings(
        citizenships: [String] = ["FI"],
        home: String? = nil,
        trips: [PlannedTrip] = [],
        allowances: [String: Int] = [:]
    ) -> AppSettings {
        var settings = AppSettings(citizenshipCountryCodes: citizenships, stayAllowances: allowances, homeCountryCode: home)
        settings.plannedTrips = trips
        return settings
    }

    private func items(
        _ trip: PlannedTrip,
        current: String? = "ES",
        online: TripPreviewOnline? = nil,
        settings: AppSettings? = nil,
        days: [VisitedCountryDay] = []
    ) -> [TripChecklistItem] {
        let settings = settings ?? self.settings(trips: [trip])
        let preview = TripPreview.make(
            trip: trip,
            settings: settings,
            countryDays: days,
            currentCountryCode: current,
            homeTimeZoneIdentifier: nil,
            now: now,
            calendar: calendar,
            locale: locale
        )
        return TripChecklist.items(for: preview, online: online, settings: settings, calendar: calendar, locale: locale)
    }

    private func item(_ id: String, in items: [TripChecklistItem]) -> TripChecklistItem? {
        items.first { $0.id == id }
    }

    // MARK: - Items

    @Test
    func aTripToMoroccoGetsTheExpectedItemsWithStableIDs() throws {
        let list = items(trip("MA", (2026, 11, 1), (2026, 11, 10)))

        #expect(try #require(item("adapter.C-E", in: list)).title == "Pack a plug adapter for type C/E (220 V)")
        #expect(try #require(item("cash.MAD", in: list)).title == "Get some Moroccan Dirham (MAD)")
        let register = try #require(item("register.FI", in: list))
        #expect(register.title == "Register your trip (Travel notification)")
        #expect(register.link == URL(string: "https://matkustusilmoitus.fi/"))
        #expect(try #require(item("consular-line.FI", in: list)).title == "Save +358 9 1605 5555 in your phone")
        #expect(try #require(item("emergency-numbers", in: list)).title == "Emergency 19 · Ambulance/fire 15 · Gendarmerie 177")
        #expect(try #require(item("roaming", in: list)).title == "Check roaming or a local SIM")
        #expect(item("roaming", in: list)?.detail == "Data Guard can track a capped plan")
        // Same side of the road, no advisory or holidays without the online part, no allowance or breach.
        #expect(list.allSatisfy { $0.kind != .driving && $0.kind != .advisory && $0.kind != .holiday })
        #expect(list.allSatisfy { $0.kind != .visaSchengen && $0.kind != .visaAllowance })
        #expect(Set(list.map(\.id)).count == list.count)
    }

    @Test
    func theIDsAreTheSameWhenTheListIsMadeAgain() {
        let trip = trip("MA", (2026, 11, 1), (2026, 11, 10))
        #expect(items(trip).map(\.id) == items(trip).map(\.id))
    }

    @Test
    func itemsAreOrderedByGroupThenByKind() {
        let list = items(trip("MA", (2026, 11, 1), (2026, 11, 10)))
        let groups = TripChecklistGroup.allCases
        let positions = list.map { groups.firstIndex(of: $0.group)! }

        #expect(positions == positions.sorted())
        #expect(list.first { $0.id == "adapter.C-E" }?.group == .moneyAndPower)
        #expect(list.first { $0.id == "register.FI" }?.group == .documents)
        #expect(list.first { $0.id == "emergency-numbers" }?.group == .beforeYouGo)
    }

    @Test
    func theAdapterAndCashFollowTheCountryYouAreInOrHome() {
        // Spain to Portugal: same plugs and currency as the current country, and as Finland at home.
        let list = items(trip("PT", (2026, 11, 1), (2026, 11, 10)))
        #expect(list.contains { $0.kind == .adapter } == false)
        #expect(list.contains { $0.kind == .cash } == false)

        // Home is Britain: Spain's plugs are not the same as home's even though the current country matches.
        let british = settings(citizenships: ["GB"], trips: [])
        let fromHome = items(trip("ES", (2026, 11, 1), (2026, 11, 10)), current: "ES", settings: british)
        #expect(fromHome.contains { $0.id == "adapter.C-F" })
        #expect(fromHome.contains { $0.id == "cash.EUR" })

        // Nothing known about where you are or home: nothing to compare with.
        let unknown = items(trip("ES", (2026, 11, 1), (2026, 11, 10)), current: nil, settings: settings(citizenships: []))
        #expect(unknown.contains { $0.kind == .adapter || $0.kind == .cash } == false)
    }

    @Test
    func drivingOnTheOtherSideAddsAnItem() throws {
        let list = items(trip("GB", (2026, 11, 1), (2026, 11, 10)))
        let driving = try #require(item("driving.left", in: list))

        #expect(driving.title == "Drive on the left — check rental and insurance")
        #expect(items(trip("PT", (2026, 11, 1), (2026, 11, 10))).contains { $0.kind == .driving } == false)
        // Compared with home when the current country drives on the same side.
        let britishHome = items(
            trip("ES", (2026, 11, 1), (2026, 11, 10)), current: "FR",
            settings: settings(citizenships: ["GB"])
        )
        #expect(britishHome.contains { $0.id == "driving.right" })
    }

    @Test
    func noRoamingItemInTheHomeCountry() {
        let list = items(trip("FI", (2026, 11, 1), (2026, 11, 10)), current: "FI")
        #expect(list.contains { $0.kind == .roaming } == false)
    }

    @Test
    func registrationAndConsularLineNeedTheCitizenshipsData() {
        // No citizenship, no consular help; the destination being the home country is the same.
        let none = items(trip("MA", (2026, 11, 1), (2026, 11, 10)), settings: settings(citizenships: []))
        #expect(none.contains { $0.kind == .registerTrip || $0.kind == .consularLine } == false)

        // Iceland publishes a hotline but has no registration service.
        let iceland = items(trip("MA", (2026, 11, 1), (2026, 11, 10)), settings: settings(citizenships: ["IS"]))
        #expect(iceland.contains { $0.id == "consular-line.IS" })
        #expect(iceland.contains { $0.kind == .registerTrip } == false)
    }

    @Test
    func aSchengenBreachNamesTheDayAndAnAllowanceIsChecked() throws {
        // 80 recorded days in France, then Spain from 20 Oct for 11 days: the 91st day is 30 Oct.
        let days = (0..<80).map { offset -> VisitedCountryDay in
            let date = calendar.date(byAdding: .day, value: -offset, to: now)!
            return VisitedCountryDay(
                day: VisitedCountryDayStamp(date: date, calendar: calendar),
                country: "FR", countryCode: "FR", source: .deviceLocation, isInferred: false
            )
        }
        let spain = trip("ES", (2026, 10, 20), (2026, 10, 30))
        let list = items(
            spain,
            current: "FR",
            settings: settings(citizenships: ["US"], trips: [spain], allowances: ["ES": 8]),
            days: days
        )

        let breach = try #require(item("visa.schengen", in: list))
        #expect(breach.title == "Your plan exceeds Schengen 90/180 on Oct 30 — adjust dates")
        let allowance = try #require(item("visa.allowance.ES", in: list))
        #expect(allowance.title == "Check your entry allowance covers 11 days")
        #expect(allowance.detail == "Your allowance is 8 days, 3 days short of the trip")
        #expect(breach.group == .documents)

        let within = items(trip("ES", (2026, 10, 20), (2026, 10, 25)), current: "FR", settings: settings(citizenships: ["US"], allowances: ["ES": 30]), days: days)
        #expect(within.contains { $0.kind == .visaSchengen } == false)
        #expect(item("visa.allowance.ES", in: within)?.detail == "Your allowance is 30 days")
    }

    @Test
    func aLocalPeriodDuringTheTripSaysWhichDayItStarts() throws {
        // Ramadan 2027 begins on 8 Feb: the fifth day of a trip from 4 Feb.
        let list = items(trip("MA", (2027, 2, 4), (2027, 2, 14)))
        let ramadan = try #require(list.first { $0.kind == .rhythm })

        #expect(ramadan.id == "rhythm.ramadan")
        #expect(ramadan.title == "Ramadan starts on day 5")
        #expect(ramadan.detail?.isEmpty == false)
        #expect(ramadan.group == .onArrival)

        let alreadyOn = try #require(items(trip("MA", (2027, 2, 12), (2027, 2, 14))).first { $0.kind == .rhythm })
        #expect(alreadyOn.title == "Ramadan is on during your trip")
    }

    @Test
    func onlinePartsAddHolidaysAndTheAdvisory() throws {
        let holidays = [
            HolidayPeriodSnapshot(name: "Amazigh New Year", startDate: day(2027, 1, 14), endDate: day(2027, 1, 14)),
            HolidayPeriodSnapshot(name: "Eid break", startDate: day(2027, 1, 20), endDate: day(2027, 1, 22))
        ]
        let advisory = TravelAlertSignalSnapshot(
            kind: .advisory, severity: .caution, title: "Morocco", summary: "Exercise a high degree of caution.",
            sourceName: "Smartraveller", sourceURL: URL(string: "https://www.smartraveller.gov.au/destinations/africa/morocco"),
            updatedAt: now, affectedCountryCodes: ["MA"]
        )
        let online = TripPreviewOnline(holidays: holidays.reversed(), advisory: advisory, fetchedAt: now)
        let list = items(trip("MA", (2027, 1, 10), (2027, 1, 25)), online: online)

        let first = try #require(item("holiday.2027-01-14", in: list))
        #expect(first.title == "Public holiday Jan 14 (Amazigh New Year) — shops may close")
        #expect(try #require(item("holiday.2027-01-20", in: list)).title == "Public holiday Jan 20–Jan 22 (Eid break) — shops may close")
        let read = try #require(item("advisory", in: list))
        #expect(read.title == "Read the travel advisory")
        #expect(read.link == advisory.sourceURL)
        #expect(read.group == .beforeYouGo)
    }

    @Test
    func anAdvisoryBelowCautionAndMissingOnlineDataAddNothing() {
        let calm = TravelAlertSignalSnapshot(
            kind: .advisory, severity: .info, title: "Spain", summary: "Normal precautions.",
            sourceName: "Smartraveller", sourceURL: nil, updatedAt: now, affectedCountryCodes: ["ES"]
        )
        let offline = items(trip("MA", (2027, 1, 10), (2027, 1, 25)), online: nil)
        let calmList = items(trip("MA", (2027, 1, 10), (2027, 1, 25)), online: TripPreviewOnline(holidays: nil, advisory: calm, fetchedAt: now))

        #expect(offline.contains { $0.kind == .advisory || $0.kind == .holiday } == false)
        #expect(calmList.contains { $0.kind == .advisory || $0.kind == .holiday } == false)
    }

    @Test
    func holidaysAreCappedSoALongTripDoesNotBuryTheList() {
        let holidays = (1...9).map { HolidayPeriodSnapshot(name: "Day \($0)", startDate: day(2027, $0, 5), endDate: day(2027, $0, 5)) }
        let list = items(
            trip("MA", (2027, 1, 1), (2027, 12, 31)),
            online: TripPreviewOnline(holidays: holidays, advisory: nil, fetchedAt: now)
        )

        #expect(list.filter { $0.kind == .holiday }.count == TripChecklist.maximumHolidayItems)
        #expect(list.filter { $0.kind == .holiday }.first?.id == "holiday.2027-01-05")
    }

    // MARK: - Progress

    @Test
    func progressCountsSuggestedAndCustomItems() {
        let list = items(trip("MA", (2026, 11, 1), (2026, 11, 10)))
        var state = TripChecklistState()
        #expect(TripChecklist.progress(items: list, state: state) == (0, list.count))

        state.setChecked(true, itemID: "cash.MAD")
        state.setChecked(true, itemID: "no.longer.exists")
        state.addCustomItem(title: "Print the booking")
        state.addCustomItem(title: "Buy sunscreen")
        state.customItems[1].isChecked = true

        let progress = TripChecklist.progress(items: list, state: state)
        #expect(progress.done == 2)
        #expect(progress.total == list.count + 2)

        state.setChecked(false, itemID: "cash.MAD")
        #expect(TripChecklist.progress(items: list, state: state).done == 1)
    }

    // MARK: - Persistence

    @Test
    func theChecklistRoundTripsWithTheTrip() throws {
        var state = TripChecklistState(checkedItemIDs: ["cash.MAD", "roaming"])
        state.addCustomItem(title: "Print the booking")
        let trip = PlannedTrip(countryCode: "MA", startDate: day(2026, 11, 1), endDate: day(2026, 11, 10), checklist: state)

        let decoded = try JSONDecoder().decode(PlannedTrip.self, from: JSONEncoder().encode(trip))

        #expect(decoded == trip)
        #expect(decoded.checklist.checkedItemIDs == ["cash.MAD", "roaming"])
        #expect(decoded.checklist.customItems.map(\.title) == ["Print the booking"])
    }

    @Test
    func aTripSavedBeforeTheChecklistExistedDecodesWithAnEmptyOne() throws {
        let json = """
        {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","countryCode":"MA","startDate":812000000,"endDate":812500000,"note":"Surf"}
        """
        let decoded = try JSONDecoder().decode(PlannedTrip.self, from: Data(json.utf8))

        #expect(decoded.checklist == TripChecklistState())
        #expect(decoded.note == "Surf")
    }

    @Test
    func aMalformedChecklistDoesNotLoseTheTrip() throws {
        let json = """
        {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","countryCode":"MA","startDate":812000000,"endDate":812500000,
         "checklist":{"checkedItemIDs":"oops","customItems":[{"title":"no id"},{"id":"1E9619FF-8B86-D011-B42D-00C04FC964FF","title":"Keep","isChecked":true}]}}
        """
        let decoded = try JSONDecoder().decode(PlannedTrip.self, from: Data(json.utf8))

        #expect(decoded.checklist.checkedItemIDs.isEmpty)
        #expect(decoded.checklist.customItems.map(\.title) == ["Keep"])
        #expect(decoded.checklist.customItems.first?.isChecked == true)
    }

    @Test
    func sanitizingDropsEmptyCustomItemsAndCapsTheLists() throws {
        let custom = [
            TripChecklistCustomItem(title: "  Keep me  "),
            TripChecklistCustomItem(title: "   "),
            TripChecklistCustomItem(title: String(repeating: "x", count: 300))
        ] + (0..<40).map { TripChecklistCustomItem(title: "Item \($0)") }
        let ids = Set((0..<150).map { "id.\($0)" } + [""])
        let trip = PlannedTrip(
            countryCode: "ma", startDate: day(2026, 11, 1), endDate: day(2026, 11, 10),
            checklist: TripChecklistState(checkedItemIDs: ids, customItems: custom)
        )

        let stored = try #require(AppSettings.sanitizedPlannedTrips([trip], now: now, calendar: calendar).first)

        #expect(stored.checklist.customItems.count == TripChecklistState.maximumCustomItems)
        #expect(stored.checklist.customItems.first?.title == "Keep me")
        #expect(stored.checklist.customItems[1].title.count == TripChecklistCustomItem.maximumTitleLength)
        #expect(stored.checklist.customItems.allSatisfy { $0.title.isEmpty == false })
        #expect(stored.checklist.checkedItemIDs.count == TripChecklistState.maximumCheckedItemIDs)
        #expect(stored.checklist.checkedItemIDs.contains("") == false)
        // Which ids stay does not depend on set order.
        #expect(stored.checklist.checkedItemIDs == Set(ids.filter { $0.isEmpty == false }.sorted().prefix(100)))
    }

    @Test
    func addingACustomItemRejectsEmptyTitlesAndAFullList() {
        var state = TripChecklistState()
        #expect(state.addCustomItem(title: "  \n ") == nil)
        for index in 0..<TripChecklistState.maximumCustomItems {
            #expect(state.addCustomItem(title: "Item \(index)") != nil)
        }
        #expect(state.addCustomItem(title: "One too many") == nil)
        #expect(state.customItems.count == TripChecklistState.maximumCustomItems)
    }

    @Test
    func ownItemsCanBeTickedAndRemovedByID() throws {
        var state = TripChecklistState()
        let addedFirst = state.addCustomItem(title: "Print the booking")
        let addedSecond = state.addCustomItem(title: "Buy sunscreen")
        let first = try #require(addedFirst)
        let second = try #require(addedSecond)

        state.setCustomItemChecked(true, id: second.id)
        #expect(state.customItems.map(\.isChecked) == [false, true])
        state.setCustomItemChecked(false, id: second.id)
        #expect(state.customItems.map(\.isChecked) == [false, false])

        state.removeCustomItem(id: first.id)
        #expect(state.customItems.map(\.title) == ["Buy sunscreen"])

        // An unknown id changes nothing.
        let before = state
        state.setCustomItemChecked(true, id: UUID())
        state.removeCustomItem(id: UUID())
        #expect(state == before)
    }

    @Test
    func settingsKeepTheChecklistThroughCoding() throws {
        var state = TripChecklistState(checkedItemIDs: ["roaming"])
        state.addCustomItem(title: "Print the booking")
        let trip = PlannedTrip(countryCode: "MA", startDate: day(2026, 11, 1), endDate: day(2026, 11, 10), checklist: state)
        let settings = AppSettings(plannedTrips: [trip])

        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))

        #expect(decoded.plannedTrips.first?.checklist == state)
    }
}
