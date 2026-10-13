import Foundation
import NomadCore
import Testing

struct QuickAnswersUpcomingTripTests {
    private let locale = QuickAnswersFixtures.locale

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Helsinki")!
        return calendar
    }

    /// A moment of the current day, so trips built from `startingIn` are relative to it.
    private var now: Date {
        calendar.date(byAdding: .hour, value: 12, to: calendar.startOfDay(for: Date()))!
    }

    private func trip(_ code: String = "MA", startingIn offset: Int, days: Int = 14) -> PlannedTrip {
        let start = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
        let end = calendar.date(byAdding: .day, value: days - 1, to: start)!
        return PlannedTrip(countryCode: code, startDate: start, endDate: end)
    }

    private func answer(_ trips: [PlannedTrip]) -> QuickAnswers.UpcomingTripAnswer {
        QuickAnswers.upcomingTrip(
            settings: AppSettings(plannedTrips: trips),
            now: now,
            calendar: calendar,
            locale: locale
        )
    }

    private func dayText(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).day().month(.wide))
    }

    @Test
    func theNextTripIsNamedWithDaysAndDates() {
        let trip = trip(startingIn: 12)
        let result = answer([trip])

        #expect(result.state == .upcoming)
        #expect(result.countryName == "Morocco")
        #expect(result.daysUntilStart == 12)
        #expect(result.sentence == "Your next trip, to Morocco, is in 12 days. "
            + "It runs from \(dayText(trip.startDate)) to \(dayText(trip.endDate)), 14 days.")
    }

    @Test
    func theEarliestTripThatHasNotStartedWins() {
        let later = trip("PT", startingIn: 40)
        let sooner = trip("ES", startingIn: 5)
        let past = trip("FR", startingIn: -20, days: 3)

        let result = answer([later, past, sooner])

        #expect(result.trip?.countryCode == "ES")
        #expect(result.daysUntilStart == 5)
    }

    @Test
    func aTripStartingTodayOrTomorrowSaysSo() {
        #expect(answer([trip(startingIn: 0)]).sentence.hasPrefix("Your next trip, to Morocco, starts today."))
        #expect(answer([trip(startingIn: 1)]).sentence.hasPrefix("Your next trip, to Morocco, starts tomorrow."))
    }

    @Test
    func aOneDayTripHasNoRange() {
        let trip = trip(startingIn: 3, days: 1)

        #expect(answer([trip]).sentence == "Your next trip, to Morocco, is in 3 days. It's on \(dayText(trip.startDate)), 1 day.")
    }

    @Test
    func aTripThatIsOnNowIsReportedWithItsLastDay() {
        let trip = trip(startingIn: -3, days: 10)
        let result = answer([trip])

        #expect(result.state == .ongoing)
        #expect(result.daysUntilStart == nil)
        #expect(result.sentence == "You're on your trip to Morocco right now. It ends on \(dayText(trip.endDate)).")
    }

    @Test
    func aTripEndingTodayIsOnItsLastDay() {
        let result = answer([trip(startingIn: -4, days: 5)])

        #expect(result.sentence == "You're on your trip to Morocco right now. It ends today.")
    }

    @Test
    func aTripThatEndedDoesNotCount() {
        let result = answer([trip(startingIn: -10, days: 3)])

        #expect(result.state == .noTrip)
        #expect(result.trip == nil)
        #expect(result.sentence == "You have no trips planned. You can plan one in the Nomad Dashboard Trip Planner.")
    }

    @Test
    func noTripsSaysSo() {
        #expect(answer([]).state == .noTrip)
    }

    @Test
    func theEnglishArticleIsAddedForCountriesThatNeedIt() {
        #expect(answer([trip("US", startingIn: 20)]).sentence.hasPrefix("Your next trip, to the United States, is in 20 days."))
    }
}
