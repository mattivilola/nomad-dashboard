import Foundation
import NomadCore

/// Text for the Offline essentials sheet, matching how the dashboard cards format the same values.
public enum OfflineEssentialsPresentation {
    /// "19° · Partly Cloudy", or the condition alone when the temperature is unknown.
    public static func weatherSummary(_ weather: WeatherSnapshot) -> String {
        let temperature = weather.currentTemperatureCelsius.map { "\(TravelUnitFormatting.temperature($0)) · " } ?? ""
        return temperature + weather.conditionDescription
    }

    /// "Station · 1,429 €/L", using the three-decimal pump-price format of the fuel card.
    public static func fuelLine(_ station: FuelStationPrice, locale: Locale = .autoupdatingCurrent) -> String {
        "\(station.stationName) · \(FuelPriceFormatting.price(station.pricePerLiter, currencyCode: station.currencyCode, locale: locale))/L"
    }

    /// Emergency numbers for the user's current country, or nil when the country is unknown or unverified.
    public static func emergencyNumbers(for snapshot: DashboardSnapshot) -> EmergencyNumbers? {
        EmergencyNumberDirectory.numbers(forCountryCode: snapshot.currentCountryCode)
    }

    /// What the Offline essentials sheet shows about the user's embassy: the nearest mission of their
    /// own state and their foreign ministry's consular line. Nil when nothing is available.
    public static func embassy(settings: AppSettings, snapshot: DashboardSnapshot) -> EmbassyEssentials? {
        let card = EmbassyCardPresentation(settings: settings, snapshot: snapshot)
        let mission = card.missions.first.map { [$0.name, $0.locationText].filter { $0.isEmpty == false }.joined(separator: ", ") }
        let hotlines = card.hotlines.map { EmbassyEssentials.Hotline(title: $0.title, phone: $0.phone) }
        let essentials = EmbassyEssentials(nearestMission: mission, hotlines: hotlines)
        return essentials.isEmpty ? nil : essentials
    }
}

public struct EmbassyEssentials: Equatable, Sendable {
    public struct Hotline: Equatable, Sendable {
        /// Short ministry name, prefixed with the country when the user has several citizenships.
        public let title: String
        public let phone: String

        public init(title: String, phone: String) {
            self.title = title
            self.phone = phone
        }
    }

    /// "Embassy of Finland, Rabat".
    public let nearestMission: String?
    public let hotlines: [Hotline]

    public var isEmpty: Bool {
        nearestMission == nil && hotlines.isEmpty
    }

    public init(nearestMission: String?, hotlines: [Hotline]) {
        self.nearestMission = nearestMission
        self.hotlines = hotlines
    }
}
