import Foundation
@testable import NomadUI
import Testing

struct HomeCountrySettingsPresentationTests {
    private let locale = Locale(identifier: "en_GB")

    @Test
    func withoutAChosenCountryHomeFollowsTheFirstCitizenship() {
        let text = HomeCountrySettingsPresentation.valueText(homeCountryCode: nil, citizenships: ["FI", "SE"], locale: locale)

        #expect(text == "Same as first citizenship (Finland)")
    }

    @Test
    func aChosenCountryIsNamedAlone() {
        let text = HomeCountrySettingsPresentation.valueText(homeCountryCode: "PT", citizenships: ["FI"], locale: locale)

        #expect(text == "Portugal")
    }

    @Test
    func withNeitherHomeIsNotSet() {
        #expect(HomeCountrySettingsPresentation.valueText(homeCountryCode: nil, citizenships: [], locale: locale) == "Not set")
    }

    @Test
    func onlyAChosenCountryCanBeReset() {
        #expect(HomeCountrySettingsPresentation.canReset(homeCountryCode: "PT"))
        #expect(HomeCountrySettingsPresentation.canReset(homeCountryCode: nil) == false)
    }

    @Test
    func theFooterSaysItStaysOnThisMac() {
        #expect(HomeCountrySettingsPresentation.footer == "Used to compare prices and time with home. Stays on this Mac.")
        #expect(HomeCountrySettingsPresentation.title == "Home country")
    }
}
