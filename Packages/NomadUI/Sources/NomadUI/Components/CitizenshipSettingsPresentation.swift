import Foundation
import NomadCore

/// One selectable country in the citizenship picker.
public struct CitizenshipCountry: Identifiable, Equatable, Sendable {
    /// Upper-case ISO 3166-1 alpha-2 code.
    public let code: String
    /// Name in the user's language.
    public let name: String

    public var id: String {
        code
    }

    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }
}

/// Text and lists behind the citizenship settings and the "Your embassy" settings section.
/// Citizenship is sensitive: everything here is computed locally from the stored codes.
public enum CitizenshipSettingsPresentation {
    public static let sectionFooter = "Stays on this Mac. Used only to find your embassy and your foreign ministry's emergency line."

    public static let addCountryTitle = "Add country…"

    public static let pickerTitle = "Choose citizenship"

    public static let pickerSearchPrompt = "Search countries"

    public static let embassySectionFooter = """
    Embassy and consulate locations come from Wikidata (CC0) and are bundled with the app, so they work offline. \
    Phone lines come from each foreign ministry's official website. When your country has no mission where you are, \
    EU consular protection or Nordic cooperation may let another country's mission help; that is not a legal guarantee. \
    The data can be incomplete or out of date, so check the official site before you rely on it.
    """

    /// "You can add up to 3 countries." Shown once the list is full.
    public static var limitText: String {
        "You can add up to \(AppSettings.maximumCitizenships) countries."
    }

    /// "Finland", "Finland and Sweden", "Finland, Sweden and Norway" in the user's language.
    public static func countryList(_ codes: [String], locale: Locale = .current) -> String {
        let names = codes.map { CountryNames.displayName(forCode: $0, locale: locale) }
        let formatter = ListFormatter()
        formatter.locale = locale
        return formatter.string(from: names) ?? names.joined(separator: ", ")
    }

    /// Every country a person can hold citizenship of: ISO 3166-1 regions with a two-letter code,
    /// sorted by their name in the user's language. Excludes the country codes without a name.
    public static func allCountries(locale: Locale = .current) -> [CitizenshipCountry] {
        Locale.Region.isoRegions
            .map(\.identifier)
            .filter(isTwoLetterCode)
            .compactMap { code in
                CountryNames.localizedName(forCode: code, locale: locale).map { CitizenshipCountry(code: code, name: $0) }
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Countries whose name or code contains the search text, ignoring case and diacritics,
    /// minus the ones already chosen.
    public static func countries(
        _ countries: [CitizenshipCountry],
        matching query: String,
        excluding chosen: [String]
    ) -> [CitizenshipCountry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let available = countries.filter { chosen.contains($0.code) == false }
        guard trimmed.isEmpty == false else {
            return available
        }

        return available.filter {
            $0.name.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || $0.code.caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    public static func canAddCountry(to chosen: [String]) -> Bool {
        chosen.count < AppSettings.maximumCitizenships
    }

    /// Settings › Safety › Your embassy status line: who the card is for and whether their foreign
    /// ministry's emergency line is bundled.
    public static func embassyStatus(forCitizenships codes: [String], locale: Locale = .current) -> String {
        guard codes.isEmpty == false else {
            return "No citizenship chosen. The Your Embassy card is off."
        }

        let withLine = codes.filter { ConsularContactsDirectory.contacts(forCitizenship: $0) != nil }
        let countries = countryList(codes, locale: locale)

        switch withLine.count {
        case codes.count:
            return "\(countries) · verified consular emergency line included"
        case 0:
            return "\(countries) · no verified consular line yet, embassy locations still work"
        default:
            return "\(countries) · verified consular line for \(countryList(withLine, locale: locale))"
        }
    }

    private static func isTwoLetterCode(_ identifier: String) -> Bool {
        identifier.count == 2 && identifier.allSatisfy { $0.isASCII && $0.isLetter }
    }
}
