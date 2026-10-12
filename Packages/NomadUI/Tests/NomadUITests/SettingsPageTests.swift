import NomadCore
import Testing
@testable import NomadUI

struct SettingsPageTests {
    @Test
    func pagesAppearInSidebarOrder() {
        #expect(SettingsPage.allCases == [
            .general,
            .weatherAndLocal,
            .safety,
            .connectionAndData,
            .work,
            .privacyAndLocation,
            .advanced
        ])
    }

    @Test
    func pagesHaveTheDocumentedTitlesAndSymbols() {
        let expected: [(SettingsPage, String, String)] = [
            (.general, "General", "gearshape"),
            (.weatherAndLocal, "Weather & Local", "cloud.sun"),
            (.safety, "Safety", "cross.case"),
            (.connectionAndData, "Connection & Data", "antenna.radiowaves.left.and.right"),
            (.work, "Work", "briefcase"),
            (.privacyAndLocation, "Privacy & Location", "hand.raised"),
            (.advanced, "Advanced", "slider.horizontal.3")
        ]

        for (page, title, symbolName) in expected {
            #expect(page.title == title)
            #expect(page.symbolName == symbolName)
        }
    }

    @Test
    func pageIdentifiersAreUnique() {
        let ids = SettingsPage.allCases.map(\.id)

        #expect(Set(ids).count == ids.count)
    }

    @Test
    func everyFocusTargetOpensItsOwnPage() {
        #expect(SettingsFocusTarget.surfSpot.page == .weatherAndLocal)
        #expect(SettingsFocusTarget.homeTimeZone.page == .general)
        #expect(SettingsFocusTarget.quietAlerts.page == .connectionAndData)
        #expect(SettingsFocusTarget.workplaceDiary.page == .work)
        #expect(SettingsFocusTarget.visitedPlaces.page == .privacyAndLocation)
        #expect(SettingsFocusTarget.weather.page == .weatherAndLocal)
        #expect(SettingsFocusTarget.localInfo.page == .weatherAndLocal)
        #expect(SettingsFocusTarget.fuelPrices.page == .weatherAndLocal)
        #expect(SettingsFocusTarget.travelAlerts.page == .safety)
        #expect(SettingsFocusTarget.emergencyCare.page == .safety)
        #expect(SettingsFocusTarget.dataGuard.page == .connectionAndData)
        #expect(SettingsFocusTarget.timeTracking.page == .work)
    }

    @Test
    func focusTargetAnchorsAreUnique() {
        let anchors = SettingsFocusTarget.allCases.map(\.rawValue)

        #expect(Set(anchors).count == anchors.count)
    }

    @Test
    func cardsPointAtTheSettingsGroupThatEnablesThem() {
        let expected: [DashboardCardID: SettingsFocusTarget] = [
            .meteredData: .dataGuard,
            .timeTracking: .timeTracking,
            .localInfo: .localInfo,
            .fuelPrices: .fuelPrices,
            .emergencyCare: .emergencyCare,
            .travelAlerts: .travelAlerts,
            .weather: .weather
        ]

        for card in DashboardCardID.allCases {
            #expect(card.settingsFocusTarget == expected[card])
        }
    }

    @Test
    func cardsWithoutTheirOwnSettingHaveNoFocusTarget() {
        #expect(DashboardCardID.connectivity.settingsFocusTarget == nil)
        #expect(DashboardCardID.power.settingsFocusTarget == nil)
        #expect(DashboardCardID.travelContext.settingsFocusTarget == nil)
    }
}
