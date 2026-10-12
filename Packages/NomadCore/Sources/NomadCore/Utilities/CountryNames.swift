import Foundation

/// The one place that turns an ISO 3166-1 alpha-2 country code into a name in the user's language.
public enum CountryNames {
    /// The system's name for a region, or nil when the code is empty or the system only has its generic
    /// "Unknown Region" placeholder for it. The code may be lower case or padded with whitespace.
    public static func localizedName(forCode code: String, locale: Locale = .current) -> String? {
        let normalized = normalizedCode(code)
        guard normalized.isEmpty == false,
              let name = locale.localizedString(forRegionCode: normalized),
              name != locale.localizedString(forRegionCode: "ZZ")
        else {
            return nil
        }

        return name
    }

    /// `localizedName(forCode:locale:)`, or the normalized code itself when the system has no name for it.
    public static func displayName(forCode code: String, locale: Locale = .current) -> String {
        localizedName(forCode: code, locale: locale) ?? normalizedCode(code)
    }

    private static func normalizedCode(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
