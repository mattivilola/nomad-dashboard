import Foundation
import NomadCore

/// Text behind the "Home country" setting in General › Home. The home country only decides what a
/// destination is compared with (prices, time); it stays on this Mac.
public enum HomeCountrySettingsPresentation {
    public static let title = "Home country"

    public static let pickerTitle = "Choose home country"

    public static let resetTitle = "Use first citizenship"

    public static let footer = "Used to compare prices and time with home. Stays on this Mac."

    /// The value shown next to the title: the chosen country, "Same as first citizenship (Finland)" while it
    /// follows the first citizenship, or "Not set" when neither is known.
    public static func valueText(homeCountryCode: String?, citizenships: [String], locale: Locale = .current) -> String {
        if let homeCountryCode {
            return CountryNames.displayName(forCode: homeCountryCode, locale: locale)
        }

        guard let first = citizenships.first else {
            return "Not set"
        }

        return "Same as first citizenship (\(CountryNames.displayName(forCode: first, locale: locale)))"
    }

    /// Whether there is a chosen home country to reset to the first citizenship.
    public static func canReset(homeCountryCode: String?) -> Bool {
        homeCountryCode != nil
    }
}
