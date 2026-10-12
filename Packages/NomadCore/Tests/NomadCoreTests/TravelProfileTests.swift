import Foundation
import NomadCore
import Testing

struct TravelProfileTests {
    @Test
    func profilesExposeTitlesAndSummaries() {
        #expect(TravelProfile.allCases == [.nomad, .roadTrip])
        #expect(TravelProfile.nomad.title == "Nomad")
        #expect(TravelProfile.roadTrip.title == "Road trip & RV")
        #expect(TravelProfile.nomad.summary == "Puts connection quality, work time and city context first.")
        #expect(TravelProfile.roadTrip.summary == "Puts weather, fuel, emergency care, power and data allowance first.")
    }

    @Test
    func recommendedOrdersCoverEveryCardExactlyOnce() {
        for profile in TravelProfile.allCases {
            let order = DashboardCardID.defaultOrder(for: profile)
            #expect(order.count == DashboardCardID.allCases.count)
            #expect(Set(order) == Set(DashboardCardID.allCases))
            #expect(DashboardCardID.sanitizedOrder(order) == order)
        }
    }

    @Test
    func nomadRecommendationIsTheBaselineDefaultOrder() {
        #expect(DashboardCardID.defaultOrder(for: .nomad) == DashboardCardID.defaultOrder)
    }

    @Test
    func roadTripRecommendationLeadsWithWeatherFuelAndEmergencyCare() {
        #expect(DashboardCardID.defaultOrder(for: .roadTrip) == [
            .weather,
            .fuelPrices,
            .emergencyCare,
            .embassy,
            .power,
            .meteredData,
            .travelAlerts,
            .stays,
            .connectivity,
            .localInfo,
            .travelContext,
            .timeTracking
        ])
    }

    @Test
    func freshSettingsUseNomadProfileWithRecommendedOrderAndNoMenuBarHeadsUp() {
        let settings = AppSettings()

        #expect(settings.travelProfile == .nomad)
        #expect(settings.menuBarShowsHeadsUp == false)
        #expect(settings.isUsingRecommendedOrder)
    }

    @Test
    func applyingProfileSwitchesAnUncustomisedOrder() {
        var settings = AppSettings()

        settings.applyTravelProfile(.roadTrip)

        #expect(settings.travelProfile == .roadTrip)
        #expect(settings.dashboardCardOrder == DashboardCardID.defaultOrder(for: .roadTrip))
        #expect(settings.isUsingRecommendedOrder)

        settings.applyTravelProfile(.nomad)

        #expect(settings.travelProfile == .nomad)
        #expect(settings.dashboardCardOrder == DashboardCardID.defaultOrder)
        #expect(settings.isUsingRecommendedOrder)
    }

    @Test
    func applyingProfileKeepsACustomisedOrder() {
        var customOrder = DashboardCardID.defaultOrder
        customOrder.swapAt(0, 1)
        var settings = AppSettings(dashboardCardOrder: customOrder)

        #expect(settings.isUsingRecommendedOrder == false)

        settings.applyTravelProfile(.roadTrip)

        #expect(settings.travelProfile == .roadTrip)
        #expect(settings.dashboardCardOrder == customOrder)
        #expect(settings.isUsingRecommendedOrder == false)
    }

    @Test
    func applyingTheSameProfileIsANoOp() {
        var settings = AppSettings(travelProfile: .roadTrip, dashboardCardOrder: DashboardCardID.defaultOrder(for: .roadTrip))
        let before = settings

        settings.applyTravelProfile(.roadTrip)

        #expect(settings == before)
    }

    @Test
    func recommendedOrderIsJudgedAgainstTheCurrentProfile() {
        let roadTripOrderUnderNomad = AppSettings(dashboardCardOrder: DashboardCardID.defaultOrder(for: .roadTrip))
        let nomadOrderUnderRoadTrip = AppSettings(travelProfile: .roadTrip)

        #expect(roadTripOrderUnderNomad.isUsingRecommendedOrder == false)
        #expect(nomadOrderUnderRoadTrip.isUsingRecommendedOrder == false)
    }

    @Test
    func profileAndMenuBarHeadsUpRoundTripThroughCodable() throws {
        var settings = AppSettings(menuBarShowsHeadsUp: true)
        settings.applyTravelProfile(.roadTrip)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))

        #expect(decoded.travelProfile == .roadTrip)
        #expect(decoded.menuBarShowsHeadsUp == true)
        #expect(decoded.dashboardCardOrder == DashboardCardID.defaultOrder(for: .roadTrip))
        #expect(decoded == settings)
    }

    @Test
    func decodesLegacyJSONWithoutProfileKeys() throws {
        let json = """
        {
          "refreshIntervalSeconds": 15,
          "slowRefreshIntervalSeconds": 300,
          "historyRetentionHours": 24,
          "publicIPGeolocationEnabled": true,
          "automaticUpdateChecksEnabled": true,
          "launchAtLoginEnabled": false,
          "useCurrentLocationForWeather": true,
          "latencyHosts": ["1.1.1.1:443"]
        }
        """

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        #expect(settings.travelProfile == .nomad)
        #expect(settings.menuBarShowsHeadsUp == false)
        #expect(settings.dashboardCardOrder == DashboardCardID.defaultOrder)
        #expect(settings.isUsingRecommendedOrder)
    }

    @Test
    func unknownPersistedProfileFallsBackToNomad() throws {
        let json = """
        {
          "travelProfile": "spaceship",
          "refreshIntervalSeconds": 15,
          "slowRefreshIntervalSeconds": 300,
          "historyRetentionHours": 24,
          "publicIPGeolocationEnabled": true,
          "automaticUpdateChecksEnabled": true,
          "launchAtLoginEnabled": false,
          "useCurrentLocationForWeather": true,
          "latencyHosts": ["1.1.1.1:443"]
        }
        """

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        #expect(settings.travelProfile == .nomad)
    }
}
