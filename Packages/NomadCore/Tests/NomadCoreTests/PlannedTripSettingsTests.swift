import Foundation
@testable import NomadCore
import Testing

struct PlannedTripSettingsTests {
    private static let legacyPayload = """
    {
      "appearanceMode": "system",
      "refreshIntervalSeconds": 15,
      "slowRefreshIntervalSeconds": 300,
      "historyRetentionHours": 24,
      "publicIPGeolocationEnabled": true,
      "automaticUpdateChecksEnabled": true,
      "launchAtLoginEnabled": false,
      "useCurrentLocationForWeather": true,
      "latencyHosts": ["1.1.1.1:443"]
    }
    """

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Helsinki")!
        return calendar
    }

    private var today: Date {
        calendar.startOfDay(for: Date())
    }

    /// A trip that starts `offset` days from today and lasts `days` days.
    private func trip(
        _ code: String = "MA",
        startingIn offset: Int,
        days: Int = 5,
        id: UUID = UUID(),
        note: String? = nil
    ) -> PlannedTrip {
        let start = calendar.date(byAdding: .day, value: offset, to: today)!
        let end = calendar.date(byAdding: .day, value: days - 1, to: start)!
        return PlannedTrip(id: id, countryCode: code, startDate: start, endDate: end, note: note)
    }

    // MARK: - Defaults and legacy decoding

    @Test
    func defaults() {
        let settings = AppSettings()

        #expect(settings.plannedTrips.isEmpty)
        #expect(settings.homeCountryCode == nil)
        #expect(settings.effectiveHomeCountryCode == nil)
    }

    @Test
    func legacySettingsWithoutTripKeysStillDecodeToTheDefaults() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(Self.legacyPayload.utf8))

        #expect(decoded.plannedTrips.isEmpty)
        #expect(decoded.homeCountryCode == nil)
    }

    @Test
    func plannedTripsAndHomeCountryRoundTripThroughCoding() throws {
        let settings = AppSettings(
            citizenshipCountryCodes: ["FI"],
            homeCountryCode: "se",
            plannedTrips: [trip("PT", startingIn: 40, note: "Surf camp"), trip("MA", startingIn: 3)]
        )
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))

        #expect(decoded == settings)
        #expect(decoded.homeCountryCode == "SE")
        #expect(decoded.plannedTrips.map(\.countryCode) == ["MA", "PT"])
        #expect(decoded.plannedTrips.last?.note == "Surf camp")
    }

    @Test
    func oneMalformedTripIsDroppedWithoutLosingTheOthers() throws {
        let good = trip("ES", startingIn: 10)
        var json = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings(plannedTrips: [good]))) as? [String: Any]
        )
        json["plannedTrips"] = try #require(json["plannedTrips"] as? [Any]) + [["countryCode": "PT"], "not a trip"]

        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: json))

        #expect(decoded.plannedTrips == [good])
    }

    @Test
    func aPlannedTripsValueOfTheWrongTypeDecodesToNoTrips() throws {
        var json = try #require(
            JSONSerialization.jsonObject(with: Data(Self.legacyPayload.utf8)) as? [String: Any]
        )
        json["plannedTrips"] = "oops"
        json["homeCountryCode"] = 7

        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: json))

        #expect(decoded.plannedTrips.isEmpty)
        #expect(decoded.homeCountryCode == nil)
    }

    // MARK: - Home country

    @Test
    func homeCountryDefaultsToTheFirstCitizenship() {
        #expect(AppSettings(citizenshipCountryCodes: ["FI", "SE"]).effectiveHomeCountryCode == "FI")
        #expect(AppSettings(citizenshipCountryCodes: ["FI", "SE"], homeCountryCode: "se").effectiveHomeCountryCode == "SE")
        #expect(AppSettings(homeCountryCode: " pt ").homeCountryCode == "PT")
        #expect(AppSettings(homeCountryCode: "Portugal").homeCountryCode == nil)
        #expect(AppSettings(citizenshipCountryCodes: ["FI"], homeCountryCode: "1").effectiveHomeCountryCode == "FI")
    }

    @Test
    func anInvalidStoredHomeCountryFallsBackToTheCitizenship() throws {
        var json = try #require(
            JSONSerialization.jsonObject(with: Data(Self.legacyPayload.utf8)) as? [String: Any]
        )
        json["homeCountryCode"] = "nope"
        json["citizenshipCountryCodes"] = ["NO"]

        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: json))

        #expect(decoded.homeCountryCode == nil)
        #expect(decoded.effectiveHomeCountryCode == "NO")
    }

    // MARK: - Sanitizing

    @Test
    func tripsAreSortedByStart() {
        let later = trip("PT", startingIn: 30)
        let sooner = trip("ES", startingIn: 4)
        let soonest = trip("MA", startingIn: 1)

        #expect(AppSettings(plannedTrips: [later, soonest, sooner]).plannedTrips == [soonest, sooner, later])
    }

    @Test
    func countryCodesAreUpperCaseLetterPairs() {
        let trips = AppSettings(plannedTrips: [
            trip(" ma ", startingIn: 1),
            trip("Spain", startingIn: 2),
            trip("1A", startingIn: 3),
            trip("", startingIn: 4),
            trip("pt", startingIn: 5)
        ]).plannedTrips

        #expect(trips.map(\.countryCode) == ["MA", "PT"])
    }

    @Test
    func theEndIsNeverBeforeTheStart() throws {
        let start = try #require(calendar.date(byAdding: .day, value: 5, to: today))
        let backwards = PlannedTrip(countryCode: "MA", startDate: start, endDate: start.addingTimeInterval(-10 * 86_400))

        let sanitized = AppSettings(plannedTrips: [backwards]).plannedTrips

        #expect(sanitized.count == 1)
        #expect(sanitized[0].endDate == start)
        #expect(sanitized[0].dayCount(calendar: calendar) == 1)
    }

    @Test
    func aTripCannotBeLongerThanTheMaximum() throws {
        let start = try #require(calendar.date(byAdding: .day, value: 5, to: today))
        let endless = try PlannedTrip(
            countryCode: "TH",
            startDate: start,
            endDate: #require(calendar.date(byAdding: .year, value: 20, to: start))
        )

        let sanitized = AppSettings.sanitizedPlannedTrips([endless], now: today, calendar: calendar)

        #expect(sanitized[0].dayCount(calendar: calendar) == PlannedTrip.maximumDurationDays)
        #expect(AppSettings(plannedTrips: [endless]).plannedTrips[0].endDate < endless.endDate)
    }

    @Test
    func atMostTwentyTripsRemainAndTheEarliestAreKept() {
        let trips = (0..<25).map { trip("MA", startingIn: 100 - $0 * 3, days: 2) }

        let sanitized = AppSettings(plannedTrips: trips).plannedTrips

        #expect(sanitized.count == AppSettings.maximumPlannedTrips)
        #expect(sanitized.count == 20)
        #expect(sanitized == trips.sorted(by: PlannedTrip.isOrderedBefore).prefix(20).map(\.self))
    }

    @Test
    func tripsThatEndedMoreThanThirtyDaysAgoAreDropped() throws {
        // A fixed clock and one calendar for building and checking, so the boundary does not depend on the
        // time of day or the machine's time zone.
        let now = try #require(calendar.date(from: DateComponents(year: 2_026, month: 10, day: 12, hour: 12)))
        func trip(_ code: String, startingIn offset: Int) -> PlannedTrip {
            let start = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
            return PlannedTrip(countryCode: code, startDate: start, endDate: calendar.date(byAdding: .day, value: 4, to: start)!)
        }
        // A five-day trip that started 35 days ago ended 31 days ago; one that started 34 days ago ended 30 days ago.
        let tooOld = trip("ES", startingIn: -35)
        let justKept = trip("PT", startingIn: -34)
        let ongoing = trip("MA", startingIn: -2)

        let sanitized = AppSettings.sanitizedPlannedTrips([tooOld, justKept, ongoing], now: now, calendar: calendar)

        #expect(sanitized == [justKept, ongoing])
    }

    @Test
    func initializingSettingsDropsOldTripsAwayFromTheBoundary() {
        // Far enough from the 30-day boundary that no time zone can change the outcome.
        let tooOld = trip("ES", startingIn: -60)
        let kept = trip("PT", startingIn: -10)

        #expect(AppSettings(plannedTrips: [tooOld, kept]).plannedTrips == [kept])
    }

    @Test
    func retentionFollowsTheGivenNowAndCalendar() throws {
        let old = trip("ES", startingIn: -200)
        let now = try #require(calendar.date(byAdding: .day, value: -190, to: today))

        #expect(AppSettings.sanitizedPlannedTrips([old], now: now, calendar: calendar) == [old])
        #expect(AppSettings.sanitizedPlannedTrips([old], now: today, calendar: calendar).isEmpty)
    }

    @Test
    func duplicateIdsKeepTheFirstTrip() {
        let id = UUID()
        let first = trip("ES", startingIn: 10, id: id)
        let second = trip("PT", startingIn: 3, id: id)

        #expect(AppSettings(plannedTrips: [first, second]).plannedTrips == [first])
    }

    @Test
    func notesAreTrimmedAndEmptyNotesBecomeNil() {
        let trips = AppSettings(plannedTrips: [
            trip("ES", startingIn: 1, note: "  Wedding  "),
            trip("PT", startingIn: 2, note: "   "),
            trip("FR", startingIn: 3, note: String(repeating: "x", count: 500))
        ]).plannedTrips

        #expect(trips.map(\.note) == ["Wedding", nil, String(repeating: "x", count: PlannedTrip.maximumNoteLength)])
    }

    // MARK: - Calendar days

    @Test
    func daysAreInclusiveAndFollowTheCalendar() throws {
        let start = try #require(calendar.date(from: DateComponents(year: 2_026, month: 12, day: 28, hour: 23, minute: 30)))
        let end = try #require(calendar.date(from: DateComponents(year: 2_027, month: 1, day: 3, hour: 1)))
        let trip = PlannedTrip(countryCode: "MA", startDate: start, endDate: end)

        #expect(trip.dayCount(calendar: calendar) == 7)
        #expect(trip.nightCount(calendar: calendar) == 6)

        let before = try #require(calendar.date(from: DateComponents(year: 2_026, month: 12, day: 20, hour: 9)))
        #expect(trip.daysUntilStart(now: before, calendar: calendar) == 8)
        #expect(trip.isOngoing(now: before, calendar: calendar) == false)
        let during = try #require(calendar.date(from: DateComponents(year: 2_027, month: 1, day: 1, hour: 9)))
        #expect(trip.daysUntilStart(now: during, calendar: calendar) == -4)
        #expect(trip.isOngoing(now: during, calendar: calendar))
        let after = try #require(calendar.date(from: DateComponents(year: 2_027, month: 1, day: 4, hour: 9)))
        #expect(trip.daysSinceEnd(now: after, calendar: calendar) == 1)
        #expect(trip.isOngoing(now: after, calendar: calendar) == false)
    }
}
