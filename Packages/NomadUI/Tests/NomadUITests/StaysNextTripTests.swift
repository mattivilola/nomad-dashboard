import Foundation
import NomadCore
@testable import NomadUI
import Testing

struct StaysNextTripTests {
    private typealias Support = StaysTestSupport

    private func card(
        trips: [PlannedTrip],
        citizenships: [String] = ["FI"],
        current: String? = nil,
        configure: (inout AppSettings) -> Void = { _ in }
    ) -> StaysCardPresentation {
        var settings = Support.settings(trips: trips, citizenships: citizenships)
        configure(&settings)
        return StaysCardPresentation(
            settings: settings,
            countryDays: [],
            currentCountryCode: current,
            now: Support.now,
            calendar: Support.calendar,
            locale: Support.locale
        )
    }

    @Test
    func theNextTripIsOneLineWithTimingAndLength() throws {
        let next = try #require(card(trips: [Support.trip(from: (2_027, 1, 12), to: (2_027, 1, 25))]).nextTrip)

        #expect(next.text == "Next trip: Morocco in 92 days · 14 days")
        #expect(next.warning == nil)
    }

    @Test
    func aTripStartingTomorrowOrTodaySaysSo() throws {
        let tomorrow = try #require(card(trips: [Support.trip(from: (2_026, 10, 13), to: (2_026, 10, 19))]).nextTrip)
        let today = try #require(card(trips: [Support.trip(from: (2_026, 10, 12), to: (2_026, 10, 12))]).nextTrip)

        #expect(tomorrow.text == "Next trip: Morocco tomorrow · 7 days")
        #expect(today.text == "Next trip: Morocco today · 1 day")
    }

    @Test
    func theEarliestTripThatHasNotStartedIsTheNextOne() throws {
        let ended = Support.trip("FR", from: (2_026, 9, 1), to: (2_026, 9, 5))
        let ongoing = Support.trip("DE", from: (2_026, 10, 10), to: (2_026, 10, 20))
        let sooner = Support.trip("PT", from: (2_026, 11, 1), to: (2_026, 11, 8))
        let later = Support.trip(from: (2_027, 1, 12), to: (2_027, 1, 25))

        let next = try #require(card(trips: [ended, ongoing, sooner, later]).nextTrip)

        #expect(next.text == "Next trip: Portugal in 20 days · 8 days")
    }

    @Test
    func noUpcomingTripMeansNoLine() {
        #expect(card(trips: []).nextTrip == nil)
        #expect(card(trips: [Support.trip(from: (2_026, 9, 1), to: (2_026, 9, 5))]).nextTrip == nil)
        #expect(card(trips: [Support.trip("DE", from: (2_026, 10, 10), to: (2_026, 10, 20))]).nextTrip == nil)
    }

    @Test
    func aPlanThatBreaksSchengenIsWarnedAboutWithTheDay() throws {
        // 100 Schengen days from tomorrow: the 91st is 11 Jan.
        let trip = Support.trip("ES", from: (2_026, 10, 13), to: (2_027, 1, 20))
        let next = try #require(card(trips: [trip], citizenships: ["US"]).nextTrip)

        #expect(next.warning == "Plan exceeds Schengen 90/180 on 11 Jan")
    }

    @Test
    func aPlanWithinSchengenOrForAFreeMovementCitizenHasNoWarning() throws {
        let trip = Support.trip("ES", from: (2_026, 10, 13), to: (2_027, 1, 20))

        #expect(try #require(card(trips: [trip], citizenships: ["FI"]).nextTrip).warning == nil)
        #expect(try #require(card(trips: [Support.trip("ES", from: (2_026, 10, 13), to: (2_026, 11, 20))], citizenships: ["US"]).nextTrip).warning == nil)
    }

    @Test
    func theWarningFollowsTheSchengenSwitch() throws {
        let trip = Support.trip("ES", from: (2_026, 10, 13), to: (2_027, 1, 20))
        let next = try #require(card(trips: [trip], citizenships: ["US"]) { $0.schengenCounterEnabled = false }.nextTrip)

        #expect(next.warning == nil)
    }

    @Test
    func theLineIsAbsentWhileTheCardIsOff() {
        let presentation = card(trips: [Support.trip(from: (2_027, 1, 12), to: (2_027, 1, 25))]) { $0.visitedPlacesEnabled = false }

        #expect(presentation.isEnabled == false)
        #expect(presentation.nextTrip == nil)
    }

    @Test
    func theButtonIsCalledTripPlanner() {
        #expect(StaysCardPresentation.tripPlannerTitle == "Trip Planner")
    }
}
