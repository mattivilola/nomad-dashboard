import Foundation
@testable import NomadCore
@testable import NomadUI
import Testing

struct DaylightLinePresentationTests {
    private let locale = Locale(identifier: "en_GB")

    @Test
    func showsSunriseAndSunsetInTheLocationsTimeZone() throws {
        let presentation = try #require(DaylightLinePresentation(
            travelContext: context(device: location(48.8566, 2.3522, "Europe/Paris")),
            now: noon,
            locale: locale
        ))
        let zone = try #require(TimeZone(identifier: "Europe/Paris"))
        let day = SolarDay.compute(latitude: 48.8566, longitude: 2.3522, date: noon, timeZone: zone)
        let sunrise = try #require(day.sunrise)
        let sunset = try #require(day.sunset)

        #expect(presentation.segments.map(\.symbolName) == ["sunrise", "sunset"])
        #expect(presentation.segments.map(\.text) == ["Sunrise \(clock(sunrise, zone))", "Sunset \(clock(sunset, zone))"])
        #expect(presentation.summary == "Sunrise \(clock(sunrise, zone)) \u{B7} Sunset \(clock(sunset, zone))")
    }

    @Test
    func fallsBackToTheIPLocationAndItsTimeZone() throws {
        let presentation = try #require(DaylightLinePresentation(
            travelContext: context(ip: location(-33.8688, 151.2093, "Australia/Sydney"), timeZoneIdentifier: "Europe/Paris"),
            now: noon,
            locale: locale
        ))
        let zone = try #require(TimeZone(identifier: "Australia/Sydney"))
        let day = SolarDay.compute(latitude: -33.8688, longitude: 151.2093, date: noon, timeZone: zone)

        #expect(try presentation.segments.first?.text == "Sunrise \(clock(#require(day.sunrise), zone))")
    }

    @Test
    func isHiddenWithoutCoordinates() {
        #expect(DaylightLinePresentation(travelContext: context(), now: noon, locale: locale) == nil)
        #expect(DaylightLinePresentation(travelContext: context(device: location(nil, nil, "Europe/Paris")), now: noon, locale: locale) == nil)
    }

    @Test
    func saysMidnightSunAndPolarNight() throws {
        let tromso = context(device: location(69.6492, 18.9553, "Europe/Oslo"))
        let june = Date(timeIntervalSince1970: 1_782_043_200) // 2026-06-21 12:00 UTC
        let december = Date(timeIntervalSince1970: 1_797_854_400) // 2026-12-21 12:00 UTC

        let midnightSun = try #require(DaylightLinePresentation(travelContext: tromso, now: june, locale: locale))
        #expect(midnightSun.segments == [.init(symbolName: "sun.max", text: "Midnight sun")])

        let polarNight = try #require(DaylightLinePresentation(travelContext: tromso, now: december, locale: locale))
        #expect(polarNight.segments == [.init(symbolName: "moon.stars", text: "Polar night")])
        #expect(polarNight.summary == "Polar night")
    }

    // MARK: - Fixtures

    private let noon = Date(timeIntervalSince1970: 1_791_806_400) // 2026-10-12 12:00 UTC

    private func clock(_ date: Date, _ zone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: zone))
    }

    private func location(_ latitude: Double?, _ longitude: Double?, _ timeZone: String?) -> IPLocationSnapshot {
        IPLocationSnapshot(
            city: nil,
            region: nil,
            country: nil,
            countryCode: nil,
            latitude: latitude,
            longitude: longitude,
            timeZone: timeZone,
            provider: "test",
            fetchedAt: noon
        )
    }

    private func context(
        device: IPLocationSnapshot? = nil,
        ip: IPLocationSnapshot? = nil,
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
