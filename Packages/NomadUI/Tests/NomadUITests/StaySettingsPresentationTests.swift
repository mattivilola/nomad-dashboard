import Foundation
import NomadCore
@testable import NomadUI
import Testing

struct StaySettingsPresentationTests {
    private let locale = Locale(identifier: "en_GB")

    @Test
    func allowanceRowsAreSortedByCountryName() {
        let rows = StaySettingsPresentation.allowanceRows(["TH": 60, "MA": 90, "AL": 90], locale: locale)

        #expect(rows.map(\.countryName) == ["Albania", "Morocco", "Thailand"])
        #expect(rows.map(\.days) == [90, 90, 60])
        #expect(rows.map(\.countryCode) == ["AL", "MA", "TH"])
    }

    @Test
    func settingAnAllowanceKeepsItWithinOneAndThreeSixtyFiveDays() {
        let start = ["MA": 90]

        #expect(StaySettingsPresentation.settingAllowance(30, for: "th", in: start) == ["MA": 90, "TH": 30])
        #expect(StaySettingsPresentation.settingAllowance(0, for: "MA", in: start) == ["MA": 1])
        #expect(StaySettingsPresentation.settingAllowance(900, for: "MA", in: start) == ["MA": 365])
    }

    @Test
    func removingAnAllowanceLeavesTheOthers() {
        #expect(StaySettingsPresentation.removingAllowance(for: "ma", from: ["MA": 90, "TH": 60]) == ["TH": 60])
        #expect(StaySettingsPresentation.removingAllowance(for: "XX", from: ["MA": 90]) == ["MA": 90])
    }

    @Test
    func daysTextIsSingularForOne() {
        #expect(StaySettingsPresentation.daysText(1) == "1 day")
        #expect(StaySettingsPresentation.daysText(183) == "183 days")
    }

    @Test
    func theDocumentedFootersAreInPlace() {
        #expect(StaySettingsPresentation.allowancesFooter.hasPrefix("Use the number of days your visa or entry stamp allows."))
        #expect(StaySettingsPresentation.schengenFooter.contains("90 days in any rolling 180 days"))
        #expect(StaySettingsPresentation.schengenFooter.contains("EU, EEA and Swiss"))
        #expect(StaySettingsPresentation.taxFooter.contains("Not tax advice"))
        #expect(StaySettingsPresentation.airQualityFooter == "European Air Quality Index from Open-Meteo; only a location rounded to about 11 km is sent.")
        #expect(StaySettingsPresentation.defaultAllowanceDays == 90)
    }

    @Test
    func thePickerCanBeTitledForAllowances() {
        #expect(StaySettingsPresentation.allowancePickerTitle == "Choose country")
        #expect(StaySettingsPresentation.addAllowanceTitle == CitizenshipSettingsPresentation.addCountryTitle)
    }
}
