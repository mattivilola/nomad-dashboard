import Foundation
import NomadCore
import Testing

struct TravelFormattingTests {
    @Test
    func temperatureRoundsToWholeDegreesWithDegreeSign() {
        #expect(TravelUnitFormatting.temperature(19.2) == "19°")
        #expect(TravelUnitFormatting.temperature(19.5) == "20°")
        #expect(TravelUnitFormatting.temperature(0) == "0°")
        #expect(TravelUnitFormatting.temperature(32) == "32°")
    }

    @Test
    func temperatureKeepsTheSignOfNegativeValuesButNeverShowsNegativeZero() {
        #expect(TravelUnitFormatting.temperature(-3) == "-3°")
        #expect(TravelUnitFormatting.temperature(-2.6) == "-3°")
        #expect(TravelUnitFormatting.temperature(-0.4) == "0°")
        #expect(TravelUnitFormatting.temperature(-0.0) == "0°")
    }

    @Test
    func temperatureIsTotalForNonFiniteValues() {
        #expect(TravelUnitFormatting.temperature(.nan) == "n/a")
        #expect(TravelUnitFormatting.temperature(.infinity) == "n/a")
    }

    @Test
    func fuelPriceUsesLocaleCurrencyWithThreeDecimals() {
        let spanish = FuelPriceFormatting.price(1.429, currencyCode: "EUR", locale: Locale(identifier: "es_ES"))
        let american = FuelPriceFormatting.price(1.429, currencyCode: "EUR", locale: Locale(identifier: "en_US"))

        #expect(spanish.contains("1,429"))
        #expect(spanish.contains("€"))
        #expect(american.contains("1.429"))
        #expect(american.contains("€"))
    }
}
