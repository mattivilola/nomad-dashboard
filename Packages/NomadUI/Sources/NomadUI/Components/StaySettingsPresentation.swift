import Foundation
import NomadCore

/// Text and list logic behind the Stays & Visas settings page and the arrival briefing and air quality toggles.
/// Visited countries and citizenship are sensitive: everything here works on values stored on this Mac.
public enum StaySettingsPresentation {
    public static let schengenToggleTitle = "Schengen 90/180 counter"

    public static let schengenFooter = """
    Visitors from outside the EU, EEA and Switzerland may stay 90 days in any rolling 180 days in the Schengen area. \
    Entry and exit days count as full days. Citizens of EU, EEA and Swiss countries are exempt, so set your \
    citizenship under General for an accurate count.
    """

    public static let allowancesTitle = "Stay allowances"

    public static let allowancesFooter = """
    Use the number of days your visa or entry stamp allows. Nomad counts the days of your current stay in that country.
    """

    public static let addAllowanceTitle = "Add country…"
    public static let allowancePickerTitle = "Choose country"
    public static let defaultAllowanceDays = 90

    public static let taxToggleTitle = "Count days for tax residence"
    public static let taxThresholdTitle = "Residence threshold"
    public static let taxFooter = """
    Counts the days recorded in each country this calendar year against your threshold, 183 days by default. \
    Rules differ by country. Not tax advice.
    """

    public static let dataTitle = "Data"
    public static let openVisitedMapTitle = "Open Visited Map to review recorded days"
    public static let visitedPlacesPointerTitle = "Privacy & Location › Visited places"
    public static let dataFooter = """
    Days come from the places Nomad recorded on this Mac and never leave it. Correct or add days in the \
    Visited Map if the Mac was off or in another country.
    """
    public static let visitedPlacesOffNotice = """
    Stays & Visas is off because “Save visited places locally” is off. Turn it on under Privacy & Location to \
    count your days.
    """

    public static let arrivalBriefingTitle = "Arrival briefing"
    public static let arrivalBriefingToggleTitle = "Show a briefing when I arrive in a new country"
    public static let arrivalBriefingFooter = """
    A short summary of local time, emergency numbers, your embassy, driving side, plugs and currency, worked out \
    on this Mac from data bundled with the app. Show it again any time from the dashboard menu.
    """

    public static let airQualityTitle = "Air quality"
    public static let airQualityToggleTitle = "Show air quality"
    public static let airQualityFooter = "European Air Quality Index from Open-Meteo; only a location rounded to about 11 km is sent."
    public static let airQualityNeedsLocationExplanation = "Turn on “Use current location for weather” to see air quality."

    /// One stay allowance in the settings list.
    public struct AllowanceRow: Identifiable, Equatable, Sendable {
        public let countryCode: String
        public let countryName: String
        public let days: Int

        public var id: String {
            countryCode
        }
    }

    /// The allowances sorted by country name in the user's language.
    public static func allowanceRows(_ allowances: [String: Int], locale: Locale = .current) -> [AllowanceRow] {
        allowances
            .map { AllowanceRow(
                countryCode: $0.key,
                countryName: CountryNames.displayName(forCode: $0.key, locale: locale),
                days: $0.value
            ) }
            .sorted { $0.countryName.localizedStandardCompare($1.countryName) == .orderedAscending }
    }

    /// `allowances` with `countryCode` set to `days` (kept within 1...365).
    public static func settingAllowance(_ days: Int, for countryCode: String, in allowances: [String: Int]) -> [String: Int] {
        var updated = allowances
        updated[countryCode.uppercased()] = min(max(days, 1), AppSettings.maximumStayAllowanceDays)
        return AppSettings.sanitizedStayAllowances(updated)
    }

    /// `allowances` without `countryCode`.
    public static func removingAllowance(for countryCode: String, from allowances: [String: Int]) -> [String: Int] {
        allowances.filter { $0.key != countryCode.uppercased() }
    }

    /// "90 days" or "1 day".
    public static func daysText(_ days: Int) -> String {
        days == 1 ? "1 day" : "\(days) days"
    }
}
