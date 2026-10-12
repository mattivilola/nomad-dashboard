import Foundation
import Testing
@testable import NomadCore

struct CountryNamesTests {
    private let english = Locale(identifier: "en_US")

    @Test
    func namesAreLocalizedToTheGivenLocale() {
        #expect(CountryNames.localizedName(forCode: "FI", locale: english) == "Finland")
        #expect(CountryNames.localizedName(forCode: "FI", locale: Locale(identifier: "fi_FI")) == "Suomi")
    }

    @Test
    func codesAreNormalizedBeforeTheLookup() {
        #expect(CountryNames.localizedName(forCode: " ma ", locale: english) == "Morocco")
        #expect(CountryNames.displayName(forCode: " ma ", locale: english) == "Morocco")
    }

    @Test
    func aCodeTheSystemCannotNameHasNoLocalizedName() {
        #expect(CountryNames.localizedName(forCode: "ZZ", locale: english) == nil)
        #expect(CountryNames.localizedName(forCode: "", locale: english) == nil)
        #expect(CountryNames.localizedName(forCode: "  ", locale: english) == nil)
    }

    @Test
    func theDisplayNameFallsBackToTheNormalizedCode() {
        #expect(CountryNames.displayName(forCode: "ZZ", locale: english) == "ZZ")
        #expect(CountryNames.displayName(forCode: " zz ", locale: english) == "ZZ")
    }
}
