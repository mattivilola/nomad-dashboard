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
}
