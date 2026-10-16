import Foundation
@testable import NomadCore
import Testing

/// Reference values come from the U.S. Naval Observatory Astronomical Applications API
/// (`https://aa.usno.navy.mil/api/rstt/oneday?date=<date>&coords=<lat>,<lon>&tz=<offset>&dst=false`,
/// "Rise", "Set", "Begin Civil Twilight", "End Civil Twilight"), retrieved 2026-10-12. The Helsinki
/// sunrise and sunset were cross-checked against the MET Norway sunrise API
/// (`https://api.met.no/weatherapi/sunrise/3.0/sun`). timeanddate.com blocks automated requests, so it
/// was not used. All reference times are local clock times, to the minute; tests allow +/- 2 minutes.
struct SolarDayTests {
    // MARK: - Helsinki (60.1699 N, 24.9384 E)

    @Test
    func helsinkiMidsummer() {
        // USNO 2026-06-21, tz +3: Begin Civil 02:02, Rise 03:54, Set 22:50, End Civil 00:42 (the night after).
        let day = solarDay(60.1699, 24.9384, "Europe/Helsinki", 2_026, 6, 21)
        expectTime(day.civilDawn, "02:02", on: (2_026, 6, 21), in: "Europe/Helsinki")
        expectTime(day.sunrise, "03:54", on: (2_026, 6, 21), in: "Europe/Helsinki")
        expectTime(day.sunset, "22:50", on: (2_026, 6, 21), in: "Europe/Helsinki")
        expectTime(day.civilDusk, "00:42", on: (2_026, 6, 22), in: "Europe/Helsinki")
        #expect(day.isPolarDay == false)
        #expect(day.isPolarNight == false)
    }

    @Test
    func helsinkiMidwinter() {
        // USNO 2026-12-21, tz +2: Begin Civil 08:25, Rise 09:24, Set 15:13, End Civil 16:11.
        let day = solarDay(60.1699, 24.9384, "Europe/Helsinki", 2_026, 12, 21)
        expectTime(day.civilDawn, "08:25", on: (2_026, 12, 21), in: "Europe/Helsinki")
        expectTime(day.sunrise, "09:24", on: (2_026, 12, 21), in: "Europe/Helsinki")
        expectTime(day.sunset, "15:13", on: (2_026, 12, 21), in: "Europe/Helsinki")
        expectTime(day.civilDusk, "16:11", on: (2_026, 12, 21), in: "Europe/Helsinki")
    }

    // MARK: - Morocco

    // Morocco returned to GMT (UTC+0, no daylight saving) on 20 Sep 2026 (Decree No. 2.26.530), so
    // Africa/Casablanca is UTC+0 on 15 Jan 2027. The USNO queries below used tz +1 (the zone before the
    // change); the reference times here are those results minus one hour, i.e. the same UTC instants.

    @Test
    func rabatInJanuary() {
        // USNO 2027-01-15, tz +1 (33.9716 N, 6.8498 W): Begin Civil 08:05, Rise 08:33, Set 18:41, End Civil 19:08.
        let day = solarDay(33.9716, -6.8498, "Africa/Casablanca", 2_027, 1, 15)
        expectTime(day.civilDawn, "07:05", on: (2_027, 1, 15), in: "Africa/Casablanca")
        expectTime(day.sunrise, "07:33", on: (2_027, 1, 15), in: "Africa/Casablanca")
        expectTime(day.sunset, "17:41", on: (2_027, 1, 15), in: "Africa/Casablanca")
        expectTime(day.civilDusk, "18:08", on: (2_027, 1, 15), in: "Africa/Casablanca")
    }

    @Test
    func marrakechInJanuary() {
        // USNO 2027-01-15, tz +1 (31.6295 N, 7.9811 W): Begin Civil 08:06, Rise 08:32, Set 18:51, End Civil 19:17.
        let day = solarDay(31.6295, -7.9811, "Africa/Casablanca", 2_027, 1, 15)
        expectTime(day.civilDawn, "07:06", on: (2_027, 1, 15), in: "Africa/Casablanca")
        expectTime(day.sunrise, "07:32", on: (2_027, 1, 15), in: "Africa/Casablanca")
        expectTime(day.sunset, "17:51", on: (2_027, 1, 15), in: "Africa/Casablanca")
        expectTime(day.civilDusk, "18:17", on: (2_027, 1, 15), in: "Africa/Casablanca")
    }

    // MARK: - Madrid (40.4168 N, 3.7038 W), DST transition 2026-03-29

    @Test
    func madridDayBeforeSpringForward() {
        // USNO 2026-03-28, tz +1: Begin Civil 06:38, Rise 07:05, Set 19:35, End Civil 20:02.
        let day = solarDay(40.4168, -3.7038, "Europe/Madrid", 2_026, 3, 28)
        expectTime(day.civilDawn, "06:38", on: (2_026, 3, 28), in: "Europe/Madrid")
        expectTime(day.sunrise, "07:05", on: (2_026, 3, 28), in: "Europe/Madrid")
        expectTime(day.sunset, "19:35", on: (2_026, 3, 28), in: "Europe/Madrid")
        expectTime(day.civilDusk, "20:02", on: (2_026, 3, 28), in: "Europe/Madrid")
    }

    @Test
    func madridOnSpringForwardDay() {
        // USNO 2026-03-29, tz +2 (clocks jump from 02:00 to 03:00): Begin Civil 07:36, Rise 08:04,
        // Set 20:36, End Civil 21:04.
        let day = solarDay(40.4168, -3.7038, "Europe/Madrid", 2_026, 3, 29)
        expectTime(day.civilDawn, "07:36", on: (2_026, 3, 29), in: "Europe/Madrid")
        expectTime(day.sunrise, "08:04", on: (2_026, 3, 29), in: "Europe/Madrid")
        expectTime(day.sunset, "20:36", on: (2_026, 3, 29), in: "Europe/Madrid")
        expectTime(day.civilDusk, "21:04", on: (2_026, 3, 29), in: "Europe/Madrid")
    }

    // MARK: - Southern hemisphere

    @Test
    func sydneyInWinter() {
        // USNO 2026-07-15, tz +10 (33.8688 S, 151.2093 E): Begin Civil 06:31, Rise 06:58, Set 17:04, End Civil 17:31.
        let day = solarDay(-33.8688, 151.2093, "Australia/Sydney", 2_026, 7, 15)
        expectTime(day.civilDawn, "06:31", on: (2_026, 7, 15), in: "Australia/Sydney")
        expectTime(day.sunrise, "06:58", on: (2_026, 7, 15), in: "Australia/Sydney")
        expectTime(day.sunset, "17:04", on: (2_026, 7, 15), in: "Australia/Sydney")
        expectTime(day.civilDusk, "17:31", on: (2_026, 7, 15), in: "Australia/Sydney")
    }

    @Test
    func aucklandSummerCrossesTheUTCDayBoundary() {
        // USNO 2027-01-15, tz +13 (36.8485 S, 174.7633 E): Begin Civil 05:48, Rise 06:17, Set 20:42, End Civil 21:12.
        // Sunrise is the previous day in UTC, which the local-day anchoring must handle.
        let day = solarDay(-36.8485, 174.7633, "Pacific/Auckland", 2_027, 1, 15)
        expectTime(day.civilDawn, "05:48", on: (2_027, 1, 15), in: "Pacific/Auckland")
        expectTime(day.sunrise, "06:17", on: (2_027, 1, 15), in: "Pacific/Auckland")
        expectTime(day.sunset, "20:42", on: (2_027, 1, 15), in: "Pacific/Auckland")
        expectTime(day.civilDusk, "21:12", on: (2_027, 1, 15), in: "Pacific/Auckland")
    }

    // MARK: - Polar

    @Test
    func tromsoPolarNightHasCivilTwilightOnly() {
        // USNO 2026-12-21, tz +1 (69.6492 N, 18.9553 E): sun continuously below the horizon,
        // Begin Civil 09:31, End Civil 13:53.
        let day = solarDay(69.6492, 18.9553, "Europe/Oslo", 2_026, 12, 21)
        #expect(day.isPolarNight)
        #expect(day.isPolarDay == false)
        #expect(day.sunrise == nil)
        #expect(day.sunset == nil)
        expectTime(day.civilDawn, "09:31", on: (2_026, 12, 21), in: "Europe/Oslo")
        expectTime(day.civilDusk, "13:53", on: (2_026, 12, 21), in: "Europe/Oslo")
    }

    @Test
    func tromsoMidnightSun() {
        // USNO 2026-06-21, tz +2: sun continuously above the horizon and the twilight limit.
        let day = solarDay(69.6492, 18.9553, "Europe/Oslo", 2_026, 6, 21)
        #expect(day.isPolarDay)
        #expect(day.isPolarNight == false)
        #expect(day.sunrise == nil)
        #expect(day.sunset == nil)
        #expect(day.civilDawn == nil)
        #expect(day.civilDusk == nil)
    }

    @Test
    func tromsoShoulderSeasonStillHasAnOrdinaryDay() {
        // USNO 2026-11-20, tz +1: Begin Civil 08:11, Rise 09:59, Set 13:00, End Civil 14:48.
        let day = solarDay(69.6492, 18.9553, "Europe/Oslo", 2_026, 11, 20)
        expectTime(day.civilDawn, "08:11", on: (2_026, 11, 20), in: "Europe/Oslo")
        expectTime(day.sunrise, "09:59", on: (2_026, 11, 20), in: "Europe/Oslo")
        expectTime(day.sunset, "13:00", on: (2_026, 11, 20), in: "Europe/Oslo")
        expectTime(day.civilDusk, "14:48", on: (2_026, 11, 20), in: "Europe/Oslo")
        #expect(day.isPolarDay == false)
        #expect(day.isPolarNight == false)
    }

    // MARK: - Behavior

    @Test
    func anyInstantOfTheLocalDayGivesTheSameDay() throws {
        let timeZone = try #require(TimeZone(identifier: "Europe/Madrid"))
        let morning = date(2_026, 3, 29, 0, 5, "Europe/Madrid")
        let night = date(2_026, 3, 29, 23, 55, "Europe/Madrid")
        #expect(
            SolarDay.compute(latitude: 40.4168, longitude: -3.7038, date: morning, timeZone: timeZone)
                == SolarDay.compute(latitude: 40.4168, longitude: -3.7038, date: night, timeZone: timeZone)
        )
    }

    @Test
    func orderedEventsOnAnOrdinaryDay() throws {
        let day = solarDay(48.8566, 2.3522, "Europe/Paris", 2_026, 10, 12)
        let dawn = try #require(day.civilDawn)
        let sunrise = try #require(day.sunrise)
        let sunset = try #require(day.sunset)
        let dusk = try #require(day.civilDusk)
        #expect(dawn < sunrise)
        #expect(sunrise < sunset)
        #expect(sunset < dusk)
    }

    @Test
    func invalidCoordinatesProduceNoTimes() throws {
        let timeZone = try #require(TimeZone(identifier: "UTC"))
        for (latitude, longitude) in [(91.0, 0.0), (0.0, 181.0), (.nan, 0.0), (0.0, .infinity)] {
            let day = SolarDay.compute(latitude: latitude, longitude: longitude, date: Date(timeIntervalSince1970: 0), timeZone: timeZone)
            #expect(day.sunrise == nil && day.sunset == nil && day.civilDawn == nil && day.civilDusk == nil)
            #expect(day.isPolarDay == false && day.isPolarNight == false)
        }
    }

    // MARK: - Daylight reference

    @Test
    func referencePrefersDeviceLocationOverIPLocation() throws {
        let reference = try #require(DaylightReference(travelContext: context(
            device: location(latitude: 40.0, longitude: -3.0, timeZone: "Europe/Madrid"),
            ip: location(latitude: 48.0, longitude: 2.0, timeZone: "Europe/Paris")
        )))
        #expect(reference.latitude == 40.0)
        #expect(reference.longitude == -3.0)
        #expect(reference.timeZone.identifier == "Europe/Madrid")
    }

    @Test
    func referenceFallsBackToIPLocationAndItsOwnTimeZone() throws {
        let reference = try #require(DaylightReference(travelContext: context(
            device: location(latitude: nil, longitude: nil, timeZone: nil),
            ip: location(latitude: 48.0, longitude: 2.0, timeZone: "Europe/Paris"),
            timeZoneIdentifier: "America/New_York"
        )))
        #expect(reference.latitude == 48.0)
        #expect(reference.timeZone.identifier == "Europe/Paris")
    }

    @Test
    func referenceFallsBackToSnapshotTimeZoneThenCurrent() throws {
        let withSnapshotZone = try #require(DaylightReference(travelContext: context(
            device: location(latitude: 40.0, longitude: -3.0, timeZone: nil),
            ip: nil,
            timeZoneIdentifier: "Europe/Lisbon"
        )))
        #expect(withSnapshotZone.timeZone.identifier == "Europe/Lisbon")

        let withNothing = try #require(DaylightReference(travelContext: context(
            device: location(latitude: 40.0, longitude: -3.0, timeZone: "Not/AZone"),
            ip: nil,
            timeZoneIdentifier: "Also/Invalid"
        )))
        #expect(withNothing.timeZone == .current)
    }

    @Test
    func referenceIsNilWithoutCoordinates() {
        #expect(DaylightReference(travelContext: context(device: nil, ip: nil)) == nil)
        #expect(DaylightReference(travelContext: context(
            device: location(latitude: 40.0, longitude: nil, timeZone: nil),
            ip: location(latitude: nil, longitude: 2.0, timeZone: nil)
        )) == nil)
        #expect(DaylightReference(travelContext: context(
            device: location(latitude: 123.0, longitude: 2.0, timeZone: nil),
            ip: nil
        )) == nil)
    }

    // MARK: - Helpers

    private let toleranceSeconds: TimeInterval = 120

    private func solarDay(_ latitude: Double, _ longitude: Double, _ zone: String, _ year: Int, _ month: Int, _ day: Int) -> SolarDay {
        SolarDay.compute(
            latitude: latitude,
            longitude: longitude,
            date: date(year, month, day, 12, 0, zone),
            timeZone: TimeZone(identifier: zone)!
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ zone: String) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func expectTime(
        _ actual: Date?,
        _ clock: String,
        on day: (Int, Int, Int),
        in zone: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        let expected = date(day.0, day.1, day.2, parts[0], parts[1], zone)
        guard let actual else {
            Issue.record("Expected \(clock) on \(day) in \(zone), got nil", sourceLocation: sourceLocation)
            return
        }
        let delta = actual.timeIntervalSince(expected)
        #expect(
            abs(delta) <= toleranceSeconds,
            "Expected \(clock) on \(day) in \(zone), off by \(delta / 60) min",
            sourceLocation: sourceLocation
        )
    }

    private func location(latitude: Double?, longitude: Double?, timeZone: String?) -> IPLocationSnapshot {
        IPLocationSnapshot(
            city: nil,
            region: nil,
            country: nil,
            countryCode: nil,
            latitude: latitude,
            longitude: longitude,
            timeZone: timeZone,
            provider: "test",
            fetchedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func context(
        device: IPLocationSnapshot?,
        ip: IPLocationSnapshot?,
        timeZoneIdentifier: String = "UTC"
    ) -> TravelContextSnapshot {
        TravelContextSnapshot(
            wifi: nil,
            vpn: nil,
            timeZoneIdentifier: timeZoneIdentifier,
            deviceLocation: device,
            publicIP: nil,
            location: ip
        )
    }
}
