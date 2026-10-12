import Foundation

// Bundled, offline travel reference data: which side of the road a country drives on, what its
// sockets and mains supply look like, and its currency.
//
// A wrong answer is worse than none (a traveller who steps into traffic looking the wrong way, or
// plugs a 120 V appliance into 230 V), so a country is only listed when at least two independent
// sources agree. Everything else returns nil.
//
// Verified 2026-10
//
// MARK: Driving side
//
// The LEFT-driving list is encoded explicitly (76 jurisdictions: 54 UN member states and 22
// territories); every other valid ISO 3166-1 alpha-2 code drives on the right. A jurisdiction is on
// the list when at least two of these three compilations agree:
//  - Wikipedia, "Left- and right-hand traffic" (country table, retrieved 2026-10-12):
//    https://en.wikipedia.org/wiki/Left-_and_right-hand_traffic
//  - WorldStandards.eu, "List of left-driving countries":
//    https://www.worldstandards.eu/cars/list-of-left-driving-countries/
//  - Motoring Research, "Which countries drive on the left?":
//    https://www.motoringresearch.com/advice/which-countries-drive-the-left/
// Cross-check: the 54 UN member states in the list match the "54 left-driving UN countries" count
// Wikipedia reports. Samoa switched to the left on 7 September 2009 and is included. Myanmar,
// Gibraltar, the British Indian Ocean Territory and Vanuatu drive on the right (Myanmar's cars are
// mostly right-hand-drive imports, but traffic keeps right) and are deliberately absent.
// Ascension Island, Tristan da Cunha and the Akrotiri and Dhekelia base areas have no ISO 3166-1
// code of their own and are covered by SH and CY. No government or road-authority compilation of
// all countries could be read; the per-country FCDO travel advice pages do not state the side.
//
// MARK: Electricity
//
// Sources, both required to agree:
//  - IEC World Plugs (the authority named for this data): https://www.iec.ch/world-plugs. IEC
//    has since retired the interactive guide (the page reads "no longer available", checked
//    2026-10-12), so the figures are IEC's last published per-plug-type pages, read from the
//    Internet Archive snapshot of 2021-10-24 of http://pubweb2.iec.ch/worldplugs/type{A...N}.htm.
//  - Wikipedia, "Mains electricity by country" (retrieved 2026-10-12), which carries national
//    standards and current nominal voltages: https://en.wikipedia.org/wiki/Mains_electricity_by_country
// Rules applied to every row:
//  - `plugTypes` holds only the types BOTH sources list. Rarer types that only one lists (for
//    example Portugal's type E, Thailand's type F) are left out rather than guessed.
//  - `voltage` is the current nominal single-phase household voltage from Wikipedia, accepted only
//    when an IEC value is within 10 % of it. IEC's 220 V and 240 V entries are the pre-harmonisation
//    figures for what is now 230 V (+10 % / -6 %) in most countries, so rows can read 230 where IEC
//    reads 220. Morocco and Indonesia list a second, legacy voltage at IEC (127 V and 110 V); the
//    current single nominal system is stored.
//  - `frequencyHertz` must be identical in both sources.
// Left out, so the lookup returns nil: Brazil (127 V or 220 V depending on the state), Japan (50 Hz
// in the east, 60 Hz in the west; the model holds one frequency), Saudi Arabia, Cuba and Bolivia
// (mixed supplies), Uzbekistan (the sources disagree on the plug types), and every country not in
// the table. Covered: every country in `EmergencyNumberDirectory` except Brazil and Japan, plus the
// most-visited other destinations.
//
// MARK: Currency
//
// Not stored: it comes from Foundation's region data (CLDR) so it never goes stale here.

/// Which side of the road traffic keeps to.
public enum DrivingSide: String, Equatable, Sendable {
    case left
    case right
}

/// The mains supply a traveller finds in a country.
public struct CountryElectricity: Equatable, Sendable {
    /// IEC plug type letters (for example "C", "E"), sorted, that are in common use.
    public let plugTypes: [String]
    /// Nominal single-phase household voltage in volts.
    public let voltage: Int
    public let frequencyHertz: Int

    public init(plugTypes: [String], voltage: Int, frequencyHertz: Int) {
        self.plugTypes = plugTypes
        self.voltage = voltage
        self.frequencyHertz = frequencyHertz
    }

    /// True when an appliance and adapter from `other` need rethinking here: different plug types,
    /// a voltage more than 10 % apart (230 V versus 240 V is the same supply, 120 V versus 230 V is
    /// not), or a different frequency.
    public func differs(from other: CountryElectricity) -> Bool {
        if Set(plugTypes) != Set(other.plugTypes) || frequencyHertz != other.frequencyHertz {
            return true
        }
        let larger = Double(max(voltage, other.voltage))
        return Double(abs(voltage - other.voltage)) / larger > 0.1
    }
}

public enum TravelReferenceData {
    // MARK: - Driving side

    /// The side of the road for an ISO 3166-1 alpha-2 country code (case-insensitive), or nil when
    /// the code is not a valid region.
    public static func drivingSide(forCountryCode code: String?) -> DrivingSide? {
        guard let normalized = normalized(code), validRegions.contains(normalized) else {
            return nil
        }
        return leftDrivingRegions.contains(normalized) ? .left : .right
    }

    /// Jurisdictions that drive on the left, by ISO 3166-1 alpha-2 code.
    static let leftDrivingRegions: Set<String> = [
        // Europe
        "GB", "IE", "MT", "CY", "GG", "JE", "IM",
        // Africa
        "BW", "KE", "LS", "MW", "MU", "MZ", "NA", "SC", "SZ", "TZ", "UG", "ZA", "ZM", "ZW",
        "SH",
        // Caribbean and South America
        "AG", "BS", "BB", "DM", "GD", "GY", "JM", "KN", "LC", "VC", "SR", "TT",
        "AI", "BM", "VG", "KY", "MS", "TC", "FK", "GS", "VI",
        // Asia
        "BD", "BT", "BN", "IN", "ID", "JP", "LK", "MV", "MY", "NP", "PK", "SG", "TH", "TL",
        "HK", "MO",
        // Oceania
        "AU", "CX", "CC", "NF", "CK", "NU", "FJ", "KI", "NR", "NZ", "PG", "WS", "SB", "TO", "TV",
        "PN", "TK"
    ]

    // MARK: - Electricity

    /// Plug types and mains supply for an ISO 3166-1 alpha-2 country code (case-insensitive), or nil
    /// when the country could not be verified against two sources.
    public static func electricity(forCountryCode code: String?) -> CountryElectricity? {
        guard let normalized = normalized(code) else {
            return nil
        }
        return electricityEntries[normalized]
    }

    private static let electricityEntries: [String: CountryElectricity] = [
        // European Union and EEA
        "AT": CountryElectricity(plugTypes: ["C", "F"], voltage: 230, frequencyHertz: 50),
        "BE": CountryElectricity(plugTypes: ["C", "E"], voltage: 230, frequencyHertz: 50),
        "BG": CountryElectricity(plugTypes: ["C", "F"], voltage: 230, frequencyHertz: 50),
        "HR": CountryElectricity(plugTypes: ["C", "F"], voltage: 230, frequencyHertz: 50),
        "CY": CountryElectricity(plugTypes: ["G"], voltage: 240, frequencyHertz: 50),
        "CZ": CountryElectricity(plugTypes: ["C", "E"], voltage: 230, frequencyHertz: 50),
        "DK": CountryElectricity(plugTypes: ["C", "E", "F", "K"], voltage: 230, frequencyHertz: 50),
        "EE": CountryElectricity(plugTypes: ["C", "F"], voltage: 230, frequencyHertz: 50),
        "FI": CountryElectricity(plugTypes: ["C", "F"], voltage: 230, frequencyHertz: 50),
        "FR": CountryElectricity(plugTypes: ["C", "E"], voltage: 230, frequencyHertz: 50),
        "DE": CountryElectricity(plugTypes: ["C", "F"], voltage: 230, frequencyHertz: 50),
        "GR": CountryElectricity(plugTypes: ["C", "F"], voltage: 230, frequencyHertz: 50),
        "HU": CountryElectricity(plugTypes: ["C", "F"], voltage: 230, frequencyHertz: 50),
        "IS": CountryElectricity(plugTypes: ["C", "F"], voltage: 230, frequencyHertz: 50),
        "IE": CountryElectricity(plugTypes: ["G"], voltage: 230, frequencyHertz: 50),
        "IT": CountryElectricity(plugTypes: ["C", "F", "L"], voltage: 230, frequencyHertz: 50),
        "LV": CountryElectricity(plugTypes: ["C", "F"], voltage: 230, frequencyHertz: 50),
        "LI": CountryElectricity(plugTypes: ["C", "J"], voltage: 230, frequencyHertz: 50),
        "LT": CountryElectricity(plugTypes: ["C", "F"], voltage: 230, frequencyHertz: 50),
        "LU": CountryElectricity(plugTypes: ["C", "F"], voltage: 230, frequencyHertz: 50),
        "MT": CountryElectricity(plugTypes: ["G"], voltage: 230, frequencyHertz: 50),
        "NL": CountryElectricity(plugTypes: ["C", "F"], voltage: 230, frequencyHertz: 50),
        "NO": CountryElectricity(plugTypes: ["C", "F"], voltage: 230, frequencyHertz: 50),
        "PL": CountryElectricity(plugTypes: ["C", "E"], voltage: 230, frequencyHertz: 50),
        "PT": CountryElectricity(plugTypes: ["C", "F"], voltage: 230, frequencyHertz: 50),
        "RO": CountryElectricity(plugTypes: ["C", "F"], voltage: 230, frequencyHertz: 50),
        "SK": CountryElectricity(plugTypes: ["C", "E"], voltage: 230, frequencyHertz: 50),
        "SI": CountryElectricity(plugTypes: ["C", "F"], voltage: 230, frequencyHertz: 50),
        "ES": CountryElectricity(plugTypes: ["C", "F"], voltage: 230, frequencyHertz: 50),
        "SE": CountryElectricity(plugTypes: ["C", "F"], voltage: 230, frequencyHertz: 50),

        // Other European and post-Soviet countries
        "GB": CountryElectricity(plugTypes: ["G"], voltage: 230, frequencyHertz: 50),
        "CH": CountryElectricity(plugTypes: ["C", "J"], voltage: 230, frequencyHertz: 50),
        "TR": CountryElectricity(plugTypes: ["C", "F"], voltage: 230, frequencyHertz: 50),
        "GE": CountryElectricity(plugTypes: ["C", "F"], voltage: 220, frequencyHertz: 50),
        "AL": CountryElectricity(plugTypes: ["C", "F"], voltage: 230, frequencyHertz: 50),
        "BA": CountryElectricity(plugTypes: ["C", "F"], voltage: 230, frequencyHertz: 50),
        "ME": CountryElectricity(plugTypes: ["C", "F"], voltage: 230, frequencyHertz: 50),
        "RS": CountryElectricity(plugTypes: ["C", "F"], voltage: 230, frequencyHertz: 50),
        "MK": CountryElectricity(plugTypes: ["C", "F"], voltage: 230, frequencyHertz: 50),
        "UA": CountryElectricity(plugTypes: ["C", "F"], voltage: 230, frequencyHertz: 50),
        "MD": CountryElectricity(plugTypes: ["C", "F"], voltage: 230, frequencyHertz: 50),
        "BY": CountryElectricity(plugTypes: ["C", "F"], voltage: 230, frequencyHertz: 50),
        "AM": CountryElectricity(plugTypes: ["C", "F"], voltage: 230, frequencyHertz: 50),
        "AZ": CountryElectricity(plugTypes: ["C", "F"], voltage: 220, frequencyHertz: 50),
        "KZ": CountryElectricity(plugTypes: ["C", "F"], voltage: 230, frequencyHertz: 50),
        "RU": CountryElectricity(plugTypes: ["C", "F"], voltage: 230, frequencyHertz: 50),

        // Americas
        "US": CountryElectricity(plugTypes: ["A", "B"], voltage: 120, frequencyHertz: 60),
        "CA": CountryElectricity(plugTypes: ["A", "B"], voltage: 120, frequencyHertz: 60),
        "MX": CountryElectricity(plugTypes: ["A", "B"], voltage: 127, frequencyHertz: 60),
        "CR": CountryElectricity(plugTypes: ["A", "B"], voltage: 120, frequencyHertz: 60),
        "PA": CountryElectricity(plugTypes: ["A", "B"], voltage: 120, frequencyHertz: 60),
        "CO": CountryElectricity(plugTypes: ["A", "B"], voltage: 120, frequencyHertz: 60),
        "PE": CountryElectricity(plugTypes: ["A", "B", "C"], voltage: 220, frequencyHertz: 60),
        "CL": CountryElectricity(plugTypes: ["C", "L"], voltage: 220, frequencyHertz: 50),
        "AR": CountryElectricity(plugTypes: ["C", "I"], voltage: 220, frequencyHertz: 50),
        "EC": CountryElectricity(plugTypes: ["A", "B"], voltage: 120, frequencyHertz: 60),
        "UY": CountryElectricity(plugTypes: ["C", "F", "I", "L"], voltage: 230, frequencyHertz: 50),
        "DO": CountryElectricity(plugTypes: ["A", "B"], voltage: 120, frequencyHertz: 60),
        "BS": CountryElectricity(plugTypes: ["A", "B"], voltage: 120, frequencyHertz: 60),
        "JM": CountryElectricity(plugTypes: ["A", "B"], voltage: 110, frequencyHertz: 50),
        "PR": CountryElectricity(plugTypes: ["A", "B"], voltage: 120, frequencyHertz: 60),
        "GT": CountryElectricity(plugTypes: ["A", "B"], voltage: 120, frequencyHertz: 60),

        // Asia-Pacific
        "TH": CountryElectricity(plugTypes: ["A", "B", "C"], voltage: 230, frequencyHertz: 50),
        "VN": CountryElectricity(plugTypes: ["A", "C", "F"], voltage: 220, frequencyHertz: 50),
        "ID": CountryElectricity(plugTypes: ["C", "F"], voltage: 230, frequencyHertz: 50),
        "MY": CountryElectricity(plugTypes: ["C", "G", "M"], voltage: 230, frequencyHertz: 50),
        "SG": CountryElectricity(plugTypes: ["C", "G", "M"], voltage: 230, frequencyHertz: 50),
        "PH": CountryElectricity(plugTypes: ["A", "B", "C"], voltage: 230, frequencyHertz: 60),
        "KR": CountryElectricity(plugTypes: ["C", "F"], voltage: 220, frequencyHertz: 60),
        "TW": CountryElectricity(plugTypes: ["A", "B"], voltage: 110, frequencyHertz: 60),
        "IN": CountryElectricity(plugTypes: ["C", "D", "M"], voltage: 230, frequencyHertz: 50),
        "LK": CountryElectricity(plugTypes: ["D", "G", "M"], voltage: 230, frequencyHertz: 50),
        "NP": CountryElectricity(plugTypes: ["C", "D", "M"], voltage: 230, frequencyHertz: 50),
        "KH": CountryElectricity(plugTypes: ["A", "C", "G"], voltage: 230, frequencyHertz: 50),
        "AU": CountryElectricity(plugTypes: ["I"], voltage: 230, frequencyHertz: 50),
        "NZ": CountryElectricity(plugTypes: ["I"], voltage: 230, frequencyHertz: 50),
        "CN": CountryElectricity(plugTypes: ["A", "I"], voltage: 220, frequencyHertz: 50),
        "HK": CountryElectricity(plugTypes: ["D", "G"], voltage: 220, frequencyHertz: 50),
        "MO": CountryElectricity(plugTypes: ["D", "G", "M"], voltage: 230, frequencyHertz: 50),
        "LA": CountryElectricity(plugTypes: ["A", "B", "C", "E", "F"], voltage: 230, frequencyHertz: 50),
        "MM": CountryElectricity(plugTypes: ["C", "D", "F", "G"], voltage: 230, frequencyHertz: 50),
        "BD": CountryElectricity(plugTypes: ["C", "D", "G"], voltage: 220, frequencyHertz: 50),
        "PK": CountryElectricity(plugTypes: ["C", "D", "G", "M"], voltage: 230, frequencyHertz: 50),
        "MV": CountryElectricity(plugTypes: ["D", "G", "J", "K", "L"], voltage: 230, frequencyHertz: 50),

        // Middle East and Africa
        "AE": CountryElectricity(plugTypes: ["G"], voltage: 230, frequencyHertz: 50),
        "IL": CountryElectricity(plugTypes: ["C", "H"], voltage: 230, frequencyHertz: 50),
        "JO": CountryElectricity(plugTypes: ["B", "C", "D", "F", "G", "J"], voltage: 230, frequencyHertz: 50),
        "EG": CountryElectricity(plugTypes: ["C", "F"], voltage: 220, frequencyHertz: 50),
        "ZA": CountryElectricity(plugTypes: ["C", "M", "N"], voltage: 230, frequencyHertz: 50),
        "MA": CountryElectricity(plugTypes: ["C", "E"], voltage: 220, frequencyHertz: 50),
        "KE": CountryElectricity(plugTypes: ["G"], voltage: 240, frequencyHertz: 50),
        "TZ": CountryElectricity(plugTypes: ["D", "G"], voltage: 230, frequencyHertz: 50),
        "BH": CountryElectricity(plugTypes: ["G"], voltage: 230, frequencyHertz: 50),
        "QA": CountryElectricity(plugTypes: ["D", "G"], voltage: 240, frequencyHertz: 50),
        "OM": CountryElectricity(plugTypes: ["G"], voltage: 240, frequencyHertz: 50),
        "KW": CountryElectricity(plugTypes: ["C", "G"], voltage: 240, frequencyHertz: 50),
        "LB": CountryElectricity(plugTypes: ["A", "B", "C", "D", "G"], voltage: 220, frequencyHertz: 50),
        "TN": CountryElectricity(plugTypes: ["C", "E"], voltage: 230, frequencyHertz: 50),
        "DZ": CountryElectricity(plugTypes: ["C", "F"], voltage: 230, frequencyHertz: 50),
        "NG": CountryElectricity(plugTypes: ["D", "G"], voltage: 230, frequencyHertz: 50),
        "GH": CountryElectricity(plugTypes: ["D", "G"], voltage: 230, frequencyHertz: 50),
        "NA": CountryElectricity(plugTypes: ["D", "M"], voltage: 220, frequencyHertz: 50),
        "MU": CountryElectricity(plugTypes: ["C", "G"], voltage: 230, frequencyHertz: 50),
        "UG": CountryElectricity(plugTypes: ["G"], voltage: 240, frequencyHertz: 50)
    ]

    // MARK: - Currency

    /// The ISO 4217 currency code in use in an ISO 3166-1 alpha-2 country (for example "MAD" for
    /// "MA"), from Foundation's region data, or nil when the region has no currency of its own.
    public static func currencyCode(forCountryCode code: String?) -> String? {
        guard let normalized = normalized(code), validRegions.contains(normalized),
              let currency = Locale(identifier: "und_" + normalized).currency?.identifier,
              currency != "XXX"
        else {
            return nil
        }
        return currency
    }

    // MARK: - Helpers

    private static let validRegions: Set<String> = Set(Locale.Region.isoRegions.map(\.identifier))

    private static func normalized(_ code: String?) -> String? {
        guard let code else { return nil }
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalized.isEmpty ? nil : normalized
    }
}
