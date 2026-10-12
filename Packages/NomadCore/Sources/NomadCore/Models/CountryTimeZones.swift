import Foundation

// Bundled, offline table of the IANA time zones each country uses, so a planned trip can say how far its
// clocks are from home before the traveller is there.
//
// Source: the IANA tz database's `zone.tab` (public domain), turned into
// `Resources/country-timezones.json` by `scripts/update-country-timezones.sh`. Nothing is fetched at
// runtime. `zone.tab` lists a country's zones in the order of the file, which is not a ranking: a country
// with several zones (US, RU, AU, BR, ...) has no single "main" one, so the time difference to such a
// country is a range.

/// The shipped file: a provenance header plus the zones per country.
struct CountryTimeZoneDataset: Codable, Equatable, Sendable {
    let source: String
    let tzdataVersion: String
    /// Upper-case ISO 3166-1 alpha-2 code to IANA time zone identifiers.
    let zones: [String: [String]]
}

/// An immutable index of the zones per country. `CountryTimeZoneIndex.bundled` is the shipped table; tests
/// inject their own.
public struct CountryTimeZoneIndex: Sendable {
    /// The table bundled with NomadCore, decoded once on first use. An unreadable resource yields an empty
    /// index rather than a crash, so a trip preview simply has no time difference.
    public static let bundled = CountryTimeZoneIndex(bundle: .module)

    private let zonesByCountry: [String: [String]]

    public init(zonesByCountry: [String: [String]]) {
        self.zonesByCountry = Dictionary(
            uniqueKeysWithValues: zonesByCountry.map { ($0.key.uppercased(), $0.value) }
        )
    }

    init(bundle: Bundle) {
        guard
            let url = bundle.url(forResource: "country-timezones", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let dataset = try? JSONDecoder().decode(CountryTimeZoneDataset.self, from: data)
        else {
            self.init(zonesByCountry: [:])
            return
        }

        self.init(zonesByCountry: dataset.zones)
    }

    /// IANA identifiers of the zones the system knows for the country, in table order. Identifiers the
    /// system does not recognize are skipped.
    public func zones(forCountryCode code: String) -> [String] {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return (zonesByCountry[normalized] ?? []).filter { TimeZone(identifier: $0) != nil }
    }
}

public enum CountryTimeZones {
    /// IANA time zone identifiers of an ISO 3166-1 alpha-2 country (case-insensitive), for example
    /// `["Europe/Helsinki"]`; empty for an unknown country.
    public static func zones(forCountryCode code: String, index: CountryTimeZoneIndex = .bundled) -> [String] {
        index.zones(forCountryCode: code)
    }

    /// How far a country's clocks are from the home time zone on `date`, or nil when the home zone or the
    /// country's zones are unknown. A country with several zones whose offsets differ gives a range.
    /// The offsets are those in force on `date`, so daylight saving time on either side is taken into
    /// account for that day only.
    public static func timeDifference(
        forCountryCode code: String,
        homeTimeZoneIdentifier: String,
        on date: Date,
        index: CountryTimeZoneIndex = .bundled
    ) -> TripTimeDifference? {
        guard let home = TimeZone(identifier: homeTimeZoneIdentifier) else {
            return nil
        }

        let homeOffset = home.secondsFromGMT(for: date)
        let differences = index.zones(forCountryCode: code)
            .compactMap(TimeZone.init(identifier:))
            .map { homeOffset - $0.secondsFromGMT(for: date) }
        guard let minimum = differences.min(), let maximum = differences.max() else {
            return nil
        }

        return TripTimeDifference(
            homeTimeZoneIdentifier: homeTimeZoneIdentifier,
            homeCityName: cityName(fromTimeZoneIdentifier: homeTimeZoneIdentifier),
            minimumOffsetFromDestinationSeconds: minimum,
            maximumOffsetFromDestinationSeconds: maximum
        )
    }

    /// City part of an identifier, for example "Helsinki" for "Europe/Helsinki".
    static func cityName(fromTimeZoneIdentifier identifier: String) -> String {
        identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? identifier
    }
}

/// The gap between home and a destination on a date, as one offset or, for a country with several zones,
/// a range.
public struct TripTimeDifference: Equatable, Sendable {
    public let homeTimeZoneIdentifier: String
    /// City part of the identifier, for example "Helsinki" for "Europe/Helsinki".
    public let homeCityName: String
    /// Home's UTC offset minus the destination's, in seconds: positive when home is ahead. The smallest
    /// of the destination's zones.
    public let minimumOffsetFromDestinationSeconds: Int
    /// The largest of the destination's zones; equal to the minimum for a country with one offset.
    public let maximumOffsetFromDestinationSeconds: Int

    public init(
        homeTimeZoneIdentifier: String,
        homeCityName: String,
        minimumOffsetFromDestinationSeconds: Int,
        maximumOffsetFromDestinationSeconds: Int
    ) {
        self.homeTimeZoneIdentifier = homeTimeZoneIdentifier
        self.homeCityName = homeCityName
        self.minimumOffsetFromDestinationSeconds = minimumOffsetFromDestinationSeconds
        self.maximumOffsetFromDestinationSeconds = maximumOffsetFromDestinationSeconds
    }

    /// True when the destination's zones do not all share one offset.
    public var isRange: Bool {
        minimumOffsetFromDestinationSeconds != maximumOffsetFromDestinationSeconds
    }

    /// Written from home's point of view, like the arrival briefing: "Home (Helsinki) is 2 h ahead",
    /// "Home (Helsinki) is on the same time", "Home (Helsinki) is 1–3 h ahead" for a range, and "up to 2 h ahead" when one zone matches home, and
    /// "Home (Helsinki) is between 1 h behind and 2 h ahead" when the zones straddle home's clock.
    public var text: String {
        let low = minimumOffsetFromDestinationSeconds
        let high = maximumOffsetFromDestinationSeconds
        let subject = "Home (\(homeCityName)) is"

        if low == 0, high == 0 {
            return "\(subject) on the same time"
        }
        if low < 0, high > 0 {
            return "\(subject) between \(Self.amount(-low)) behind and \(Self.amount(high)) ahead"
        }

        let ahead = high > 0
        let near = min(abs(low), abs(high))
        let far = max(abs(low), abs(high))
        return "\(subject) \(Self.span(from: near, to: far)) \(ahead ? "ahead" : "behind")"
    }

    private static func amount(_ seconds: Int) -> String {
        DurationText.hoursAndMinutes(TimeInterval(seconds))
    }

    /// "2 h" for one offset, "up to 2 h" when one zone matches home, "1–3 h" for a range of whole hours,
    /// else each end with its own unit.
    private static func span(from near: Int, to far: Int) -> String {
        if near == far {
            return amount(far)
        }
        if near == 0 {
            return "up to \(amount(far))"
        }
        if near % 3_600 == 0, far % 3_600 == 0 {
            return "\(near / 3_600)–\(far / 3_600) h"
        }
        return "\(amount(near))–\(amount(far))"
    }
}
