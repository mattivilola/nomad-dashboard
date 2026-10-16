import Foundation
@testable import NomadCore
import Testing

struct CountryTimeZonesTests {
    private let winter = Date(timeIntervalSince1970: 1_768_478_400) // 2026-01-15 12:00 UTC
    private let summer = Date(timeIntervalSince1970: 1_784_116_800) // 2026-07-15 12:00 UTC

    private let index = CountryTimeZoneIndex(zonesByCountry: [
        "AE": ["Asia/Dubai"],
        "IN": ["Asia/Kolkata"],
        "UA": ["Europe/Kyiv"],
        "JP": ["Asia/Tokyo"],
        "XA": ["Asia/Dubai", "Asia/Tokyo"],
        "XB": ["Asia/Dubai", "America/New_York"],
        "XC": ["Europe/Helsinki", "Asia/Dubai"],
        "XD": ["Asia/Kolkata", "Asia/Dubai"],
        "XE": ["Nowhere/Land"],
        "XF": ["Nowhere/Land", "Asia/Dubai"],
        "US": ["America/New_York", "America/Chicago", "America/Denver", "America/Los_Angeles"]
    ])

    private func difference(_ country: String, home: String = "Europe/Helsinki", on date: Date) -> TripTimeDifference? {
        CountryTimeZones.timeDifference(forCountryCode: country, homeTimeZoneIdentifier: home, on: date, index: index)
    }

    // MARK: - Bundled table

    @Test
    func theBundledTableCoversEveryCountryWithItsZones() {
        #expect(CountryTimeZones.zones(forCountryCode: "FI") == ["Europe/Helsinki"])
        #expect(CountryTimeZones.zones(forCountryCode: " fi ") == ["Europe/Helsinki"])
        #expect(CountryTimeZones.zones(forCountryCode: "MA") == ["Africa/Casablanca"])
        #expect(CountryTimeZones.zones(forCountryCode: "US").contains("America/New_York"))
        #expect(CountryTimeZones.zones(forCountryCode: "US").contains("Pacific/Honolulu"))
        #expect(CountryTimeZones.zones(forCountryCode: "RU").count >= 10)
        #expect(CountryTimeZones.zones(forCountryCode: "AU").count >= 6)
        #expect(CountryTimeZones.zones(forCountryCode: "ZZ").isEmpty)
        #expect(CountryTimeZones.zones(forCountryCode: "").isEmpty)
    }

    @Test
    func everyBundledZoneIsKnownToTheSystemAndEveryCommonDestinationHasOne() {
        let regions = Locale.Region.isoRegions.map(\.identifier).filter { $0.count == 2 }
        let covered = regions.filter { CountryTimeZones.zones(forCountryCode: $0).isEmpty == false }

        // zone.tab lists every inhabited ISO country; only a few uninhabited territories have no zone.
        #expect(covered.count > 235)
        for code in ["US", "GB", "DE", "FR", "ES", "IT", "PT", "MA", "TH", "ID", "JP", "MX", "BR", "AU", "NZ", "ZA", "TR", "AE", "IN", "VN"] {
            #expect(covered.contains(code), "\(code) has no time zone")
        }
        for code in covered {
            #expect(CountryTimeZones.zones(forCountryCode: code).allSatisfy { TimeZone(identifier: $0) != nil })
        }
    }

    @Test
    func theBundledTableGivesAHomeComparisonForARealCountry() throws {
        let difference = try #require(CountryTimeZones.timeDifference(
            forCountryCode: "JP", homeTimeZoneIdentifier: "Europe/Helsinki", on: winter
        ))

        #expect(difference.text == "Home (Helsinki) is 7 h behind")
    }

    // MARK: - One offset

    @Test
    func homeAheadOrBehindIsWrittenFromHomesPointOfView() throws {
        // Helsinki is UTC+2 in winter and UTC+3 in summer; Dubai is UTC+4 all year.
        #expect(try #require(difference("AE", on: winter)).text == "Home (Helsinki) is 2 h behind")
        #expect(try #require(difference("AE", on: summer)).text == "Home (Helsinki) is 1 h behind")
        #expect(try #require(difference("JP", home: "Asia/Dubai", on: winter)).text == "Home (Dubai) is 5 h behind")
        #expect(try #require(difference("AE", home: "Asia/Tokyo", on: winter)).text == "Home (Tokyo) is 5 h ahead")
        #expect(try #require(difference("IN", on: winter)).text == "Home (Helsinki) is 3 h 30 min behind")
    }

    @Test
    func sameClockIsSaid() throws {
        let same = try #require(difference("UA", on: winter))

        #expect(same.isRange == false)
        #expect(same.text == "Home (Helsinki) is on the same time")
        #expect(same.minimumOffsetFromDestinationSeconds == 0)
    }

    @Test
    func theCityNameComesFromTheIdentifier() throws {
        #expect(try #require(difference("AE", home: "America/Argentina/Buenos_Aires", on: winter)).homeCityName == "Buenos Aires")
        #expect(try #require(difference("AE", home: "UTC", on: winter)).homeCityName == "UTC")
    }

    @Test
    func offsetsAreSecondsFromHomeMinusDestination() throws {
        let tokyo = try #require(difference("JP", on: winter))

        #expect(tokyo.minimumOffsetFromDestinationSeconds == -7 * 3_600)
        #expect(tokyo.maximumOffsetFromDestinationSeconds == -7 * 3_600)
        #expect(tokyo.homeTimeZoneIdentifier == "Europe/Helsinki")
    }

    // MARK: - Ranges

    @Test
    func aCountryWithSeveralOffsetsGivesARange() throws {
        let range = try #require(difference("XA", on: winter))

        #expect(range.isRange)
        #expect(range.minimumOffsetFromDestinationSeconds == -7 * 3_600)
        #expect(range.maximumOffsetFromDestinationSeconds == -2 * 3_600)
        #expect(range.text == "Home (Helsinki) is 2–7 h behind")
    }

    @Test
    func theUnitedStatesIsARangeAndFollowsDaylightSavingOnTheDate() throws {
        // In winter Helsinki is 7 h ahead of New York and 10 h ahead of Los Angeles.
        let us = try #require(difference("US", on: winter))
        #expect(us.text == "Home (Helsinki) is 7–10 h ahead")
    }

    @Test
    func aRangeThatStraddlesHomesClockSaysBothDirections() throws {
        let straddling = try #require(difference("XB", home: "Europe/London", on: winter))

        #expect(straddling.text == "Home (London) is between 4 h behind and 5 h ahead")
    }

    @Test
    func aRangeThatIncludesHomesOwnClockSaysUpTo() throws {
        let includingHome = try #require(difference("XC", on: winter))

        #expect(includingHome.text == "Home (Helsinki) is up to 2 h behind")
    }

    @Test
    func aRangeOfPartHoursKeepsEachEndsUnit() throws {
        let partHours = try #require(difference("XD", on: winter))

        #expect(partHours.text == "Home (Helsinki) is 2 h–3 h 30 min behind")
    }

    // MARK: - Missing data

    @Test
    func anUnknownHomeZoneOrCountryGivesNothing() {
        #expect(difference("AE", home: "Mars/Olympus", on: winter) == nil)
        #expect(difference("QQ", on: winter) == nil)
        #expect(difference("XE", on: winter) == nil)
    }

    @Test
    func zonesTheSystemDoesNotKnowAreSkipped() throws {
        let partial = try #require(difference("XF", on: winter))

        #expect(partial.isRange == false)
        #expect(partial.text == "Home (Helsinki) is 2 h behind")
    }
}
