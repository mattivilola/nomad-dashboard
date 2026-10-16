import Foundation
@testable import NomadCore
import Testing

struct UpcomingTripInsightTests {
    private let today = Date(timeIntervalSince1970: 1_791_806_400) // 2026-10-12 14:00 Paris

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 14) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// A trip that starts `offset` days after `now` and lasts `days` days.
    private func trip(_ code: String, startingIn offset: Int, days: Int = 5, now: Date? = nil) -> PlannedTrip {
        let start = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now ?? today))!
        return PlannedTrip(
            countryCode: code,
            startDate: start,
            endDate: calendar.date(byAdding: .day, value: days - 1, to: start)!
        )
    }

    /// One record per day, `count` days ending on `end`.
    private func recorded(_ code: String, count: Int, endingOn end: Date) -> [VisitedCountryDay] {
        (0..<count).map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: end)!
            return VisitedCountryDay(
                day: VisitedCountryDayStamp(date: day, calendar: calendar),
                country: code,
                countryCode: code,
                source: .deviceLocation,
                isInferred: false
            )
        }
    }

    private func insight(
        trips: [PlannedTrip],
        days: [VisitedCountryDay] = [],
        citizenships: [String] = ["FI"],
        current: String? = "FR",
        now: Date? = nil,
        visitedPlacesEnabled: Bool = true
    ) -> DashboardInsight? {
        var settings = AppSettings(citizenshipCountryCodes: citizenships)
        settings.plannedTrips = trips
        settings.visitedPlacesEnabled = visitedPlacesEnabled
        return DashboardInsightEngine.insights(
            for: .placeholder,
            now: now ?? today,
            calendar: calendar,
            limit: 20,
            stays: StayInsightInput(countryDays: days, settings: settings, currentCountryCode: current)
        ).first { $0.kind == .upcomingTrip }
    }

    // MARK: - Shape

    @Test
    func aTripStartingSoonIsAnInfoHeadsUpWithTheCurrencyAsTheLastResort() throws {
        // France to Morocco: same side of the road, nothing in the calendar, so the currency is what changes.
        let insight = try #require(insight(trips: [trip("MA", startingIn: 12)]))

        #expect(insight.kind == .upcomingTrip)
        #expect(insight.severity == .info)
        #expect(insight.title == "Morocco in 12 days")
        #expect(insight.menuBarText == "Trip in 12 d")
        #expect(insight.detail == "Currency: Moroccan Dirham (MAD)")
        #expect(insight.symbolName == "airplane.departure")
        #expect(insight.relatedCard == .stays)
    }

    @Test
    func theCurrencyIsStillNamedWhenItDoesNotChange() throws {
        let insight = try #require(insight(trips: [trip("ES", startingIn: 5)], current: "PT"))

        #expect(insight.detail == "Same currency (EUR)")
    }

    @Test
    func theHeadsUpAppearsFourteenDaysAheadAndNoEarlier() {
        #expect(insight(trips: [trip("MA", startingIn: 15)]) == nil)
        #expect(insight(trips: [trip("MA", startingIn: 14)])?.title == "Morocco in 14 days")
    }

    @Test
    func todayAndTomorrowReadNaturally() throws {
        let startsToday = try #require(insight(trips: [trip("MA", startingIn: 0)]))
        #expect(startsToday.title == "Morocco today")
        #expect(startsToday.menuBarText == "Trip today")

        let tomorrow = try #require(insight(trips: [trip("MA", startingIn: 1)]))
        #expect(tomorrow.title == "Morocco tomorrow")
        #expect(tomorrow.menuBarText == "Trip in 1 d")
    }

    @Test
    func aTripThatHasStartedOrEndedIsNoHeadsUp() {
        #expect(insight(trips: [trip("MA", startingIn: -1)]) == nil)
        #expect(insight(trips: [trip("MA", startingIn: -20)]) == nil)
        #expect(insight(trips: []) == nil)
    }

    @Test
    func theEarliestUpcomingTripWins() throws {
        let insight = try #require(insight(trips: [trip("PT", startingIn: 9), trip("MA", startingIn: 4), trip("ES", startingIn: 30)]))

        #expect(insight.title == "Morocco in 4 days")
    }

    @Test
    func menuBarTextAndTitlesStayCompactForEveryDistance() throws {
        for offset in 0...14 {
            let insight = try #require(insight(trips: [trip("DO", startingIn: offset)]))
            #expect(insight.menuBarText.count <= 12)
            #expect((insight.detail?.count ?? 0) <= 44)
        }
    }

    @Test
    func noStayInputMeansNoTripHeadsUp() {
        let insights = DashboardInsightEngine.insights(for: .placeholder, now: today, calendar: calendar, limit: 20)

        #expect(insights.isEmpty)
    }

    @Test
    func theHeadsUpDoesNotDependOnTheVisitedPlacesSwitch() {
        #expect(insight(trips: [trip("MA", startingIn: 3)], visitedPlacesEnabled: false) != nil)
    }

    // MARK: - Most important fact

    @Test
    func aSchengenBreachIsACautionNamingTheFirstDayOverTheLimit() throws {
        // 80 recorded days in France, then Spain from 20 Oct: the 91st day is 30 Oct.
        let insight = try #require(insight(
            trips: [trip("ES", startingIn: 8, days: 11)],
            days: recorded("FR", count: 80, endingOn: today),
            citizenships: ["US"]
        ))

        #expect(insight.severity == .caution)
        #expect(insight.title == "Spain in 8 days")
        #expect(insight.detail == "Plan exceeds Schengen 90/180 on 30 Oct")
        #expect(insight.menuBarText == "Trip in 8 d")
    }

    @Test
    func aTripThatStaysWithinTheLimitIsNoBreach() throws {
        let insight = try #require(insight(
            trips: [trip("ES", startingIn: 8, days: 10)],
            days: recorded("FR", count: 80, endingOn: today),
            citizenships: ["US"]
        ))

        #expect(insight.severity == .info)
        #expect(insight.detail?.contains("Schengen") == false)
    }

    @Test
    func citizensWithFreeMovementAndUnknownCitizenshipsGetNoBreachClaim() throws {
        let longStay = [trip("ES", startingIn: 8, days: 120)]
        let history = recorded("FR", count: 80, endingOn: today)

        #expect(try #require(insight(trips: longStay, days: history, citizenships: ["FI"])).severity == .info)
        #expect(try #require(insight(trips: longStay, days: history, citizenships: [])).severity == .info)
    }

    @Test
    func aBreachOutranksALocalPeriodDuringTheTrip() throws {
        // Spring 2027: Holy Week (Palm Sunday 21 Mar) falls in a trip to Spain that also breaks the limit.
        let now = date(2_027, 3, 10)
        let insight = try #require(insight(
            trips: [trip("ES", startingIn: 10, days: 11, now: now)],
            days: recorded("FR", count: 80, endingOn: now),
            citizenships: ["US"],
            now: now
        ))

        #expect(insight.severity == .caution)
        #expect(insight.detail?.hasPrefix("Plan exceeds Schengen 90/180 on") == true)
    }

    @Test
    func aLocalPeriodThatStartsMidTripBeatsTheRoadAndTheCurrency() throws {
        // Saudi Arabia: Ramadan starts on 8 Feb 2027.
        let now = date(2_027, 1, 25)
        let insight = try #require(insight(trips: [trip("SA", startingIn: 7, days: 20, now: now)], now: now))

        #expect(insight.severity == .info)
        #expect(insight.title == "Saudi Arabia in 7 days")
        #expect(insight.detail == "Ramadan starts mid-trip")
    }

    @Test
    func aLocalPeriodAlreadyOnAtArrivalSaysSo() throws {
        let now = date(2_027, 2, 20)
        let insight = try #require(insight(trips: [trip("SA", startingIn: 5, days: 4, now: now)], now: now))

        #expect(insight.detail == "Ramadan is on during your trip")
    }

    @Test
    func aFullShutdownBeatsAnEarlierPeriodOfTheSameTrip() throws {
        // Indonesia 1-15 Mar 2027: Ramadan is already on, Nyepi (8 Mar) shuts Bali down for a day.
        let now = date(2_027, 2, 25)
        let insight = try #require(insight(trips: [trip("ID", startingIn: 4, days: 15, now: now)], now: now))

        #expect(insight.detail == "Nyepi starts mid-trip")
    }

    @Test
    func aChangeOfDrivingSideBeatsTheCurrency() throws {
        let insight = try #require(insight(trips: [trip("GB", startingIn: 5)], current: "FR"))

        #expect(insight.detail == "Drive on the left")
    }

    @Test
    func theLiveCountryCountsInThePlan() throws {
        // 89 recorded days in France plus today in Spain make 90; the trip then starts on the 91st day, 14 Oct.
        let history = try recorded("FR", count: 89, endingOn: #require(calendar.date(byAdding: .day, value: -1, to: today)))
        let insight = try #require(insight(
            trips: [trip("ES", startingIn: 2, days: 2)],
            days: history,
            citizenships: ["US"],
            current: "ES"
        ))

        #expect(insight.detail == "Plan exceeds Schengen 90/180 on 14 Oct")
    }

    // MARK: - Ranking

    @Test
    func theTripHeadsUpRanksRightAfterTheLocalRhythmInBothProfiles() {
        for profile in TravelProfile.allCases {
            let order = DashboardInsightKind.tieBreakOrder(for: profile)
            #expect(order.firstIndex(of: .upcomingTrip) == order.firstIndex(of: .localRhythm).map { $0 + 1 })
        }
    }

    @Test
    func aBreachRanksAfterTheStayCautionsAndAheadOfInfoHeadsUps() throws {
        let history = recorded("FR", count: 80, endingOn: today)
        var settings = AppSettings(citizenshipCountryCodes: ["US"])
        settings.plannedTrips = [trip("ES", startingIn: 8, days: 11)]

        let kinds = DashboardInsightEngine.insights(
            for: .placeholder,
            now: today,
            calendar: calendar,
            limit: 20,
            stays: StayInsightInput(countryDays: history, settings: settings, currentCountryCode: "FR")
        ).map(\.kind)

        // Schengen has 10 days left (caution), the trip adds a caution of its own and the tax count is info.
        #expect(kinds.first == .schengenLimit)
        #expect(kinds.contains(.upcomingTrip))
        #expect(try #require(kinds.firstIndex(of: .upcomingTrip)) < kinds.firstIndex(of: .taxResidenceDays) ?? .max)
    }

    // MARK: - Checklist

    /// Offline suggestions for a trip from France to Morocco with a Finnish passport: the emergency numbers,
    /// roaming, the consular line, the trip registration, a plug adapter and the dirham.
    private let moroccoChecklistItemCount = 6

    @Test
    func openChecklistItemsBecomeTheDetailInTheLastThreeDays() throws {
        for offset in 0...DashboardInsightEngine.upcomingTripChecklistLeadDays {
            let insight = try #require(insight(trips: [trip("MA", startingIn: offset)]))

            #expect(insight.detail == "\(moroccoChecklistItemCount) checklist items left")
            #expect(insight.severity == .info)
        }
        #expect(try #require(insight(trips: [trip("MA", startingIn: 4)])).detail == "Currency: Moroccan Dirham (MAD)")
    }

    @Test
    func checkedItemsAndTheTravellersOwnItemsAreCounted() throws {
        var checklist = TripChecklistState(checkedItemIDs: ["cash.MAD", "roaming", "gone.since"])
        checklist.addCustomItem(title: "Print the booking")
        checklist.addCustomItem(title: "Buy sunscreen")
        checklist.customItems[1].isChecked = true
        var planned = trip("MA", startingIn: 2)
        planned.checklist = checklist

        // 6 suggestions - 2 checked + 2 own - 1 own checked; the unknown id counts for nothing.
        #expect(try #require(insight(trips: [planned])).detail == "\(moroccoChecklistItemCount - 2 + 1) checklist items left")
    }

    @Test
    func oneOpenItemReadsInTheSingular() throws {
        var planned = trip("MA", startingIn: 1)
        planned.checklist = TripChecklistState(checkedItemIDs: [
            "roaming", "emergency-numbers", "consular-line.FI", "register.FI", "adapter.C-E"
        ])

        #expect(try #require(insight(trips: [planned])).detail == "1 checklist item left")
    }

    @Test
    func aFinishedChecklistFallsBackToTheNextFact() throws {
        var planned = trip("MA", startingIn: 2)
        planned.checklist = TripChecklistState(checkedItemIDs: [
            "roaming", "emergency-numbers", "consular-line.FI", "register.FI", "adapter.C-E", "cash.MAD"
        ])

        #expect(try #require(insight(trips: [planned])).detail == "Currency: Moroccan Dirham (MAD)")
    }

    @Test
    func aBreachOutranksTheChecklistInTheLastDays() throws {
        let insight = try #require(insight(
            trips: [trip("ES", startingIn: 2, days: 11)],
            days: recorded("FR", count: 80, endingOn: today),
            citizenships: ["US"]
        ))

        #expect(insight.severity == .caution)
        #expect(insight.detail?.hasPrefix("Plan exceeds Schengen 90/180 on") == true)
    }

    @Test
    func theChecklistOutranksALocalPeriodAndTheRoadInTheLastDays() throws {
        // Saudi Arabia: Ramadan starts on 8 Feb 2027.
        let now = date(2_027, 2, 5)
        let ramadan = try #require(insight(trips: [trip("SA", startingIn: 2, days: 20, now: now)], now: now))
        #expect(ramadan.detail?.hasSuffix("checklist items left") == true)

        let driving = try #require(insight(trips: [trip("GB", startingIn: 2)], current: "FR"))
        #expect(driving.detail?.hasSuffix("checklist items left") == true)
    }

    @Test
    func theChecklistDetailFitsTheHeadsUpWidth() throws {
        let insight = try #require(insight(trips: [trip("MA", startingIn: 1)]))
        #expect((insight.detail?.count ?? 0) <= 44)
    }
}
