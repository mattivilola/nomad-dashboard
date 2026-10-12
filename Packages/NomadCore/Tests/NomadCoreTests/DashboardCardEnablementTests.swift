import Foundation
import NomadCore
import Testing

struct DashboardCardEnablementTests {
    @Test
    func cardsWithoutAFeatureToggleAreAlwaysEnabled() {
        var settings = AppSettings()
        settings.meteredDataEnabled = false
        settings.localInfoEnabled = false

        for card in [DashboardCardID.connectivity, .power, .travelContext, .weather] {
            #expect(card.isFeatureEnabled(in: settings))
        }
    }

    @Test
    func featureCardsFollowTheirSettingsFlag() {
        var settings = AppSettings(
            localInfoEnabled: false,
            fuelPricesEnabled: false,
            emergencyCareEnabled: false,
            projectTimeTrackingEnabled: false,
            meteredDataEnabled: false
        )

        #expect(DashboardCardID.meteredData.isFeatureEnabled(in: settings) == false)
        #expect(DashboardCardID.timeTracking.isFeatureEnabled(in: settings) == false)
        #expect(DashboardCardID.localInfo.isFeatureEnabled(in: settings) == false)
        #expect(DashboardCardID.fuelPrices.isFeatureEnabled(in: settings) == false)
        #expect(DashboardCardID.emergencyCare.isFeatureEnabled(in: settings) == false)

        settings.meteredDataEnabled = true
        settings.projectTimeTrackingEnabled = true
        settings.localInfoEnabled = true
        settings.fuelPricesEnabled = true
        settings.emergencyCareEnabled = true

        #expect(DashboardCardID.meteredData.isFeatureEnabled(in: settings))
        #expect(DashboardCardID.timeTracking.isFeatureEnabled(in: settings))
        #expect(DashboardCardID.localInfo.isFeatureEnabled(in: settings))
        #expect(DashboardCardID.fuelPrices.isFeatureEnabled(in: settings))
        #expect(DashboardCardID.emergencyCare.isFeatureEnabled(in: settings))
    }

    @Test
    func travelAlertsIsEnabledWhenAnyAlertKindIsOn() {
        let allOff = AppSettings(
            travelAdvisoryEnabled: false,
            travelWeatherAlertsEnabled: false,
            regionalSecurityEnabled: false
        )
        #expect(DashboardCardID.travelAlerts.isFeatureEnabled(in: allOff) == false)

        #expect(DashboardCardID.travelAlerts.isFeatureEnabled(in: AppSettings(travelAdvisoryEnabled: true, travelWeatherAlertsEnabled: false, regionalSecurityEnabled: false)))
        #expect(DashboardCardID.travelAlerts.isFeatureEnabled(in: AppSettings(travelAdvisoryEnabled: false, travelWeatherAlertsEnabled: true, regionalSecurityEnabled: false)))
        #expect(DashboardCardID.travelAlerts.isFeatureEnabled(in: AppSettings(travelAdvisoryEnabled: false, travelWeatherAlertsEnabled: false, regionalSecurityEnabled: true)))
    }

    @Test
    func embassyIsEnabledOnlyWhenACitizenshipIsSet() {
        #expect(DashboardCardID.embassy.isFeatureEnabled(in: AppSettings()) == false)
        #expect(DashboardCardID.embassy.isFeatureEnabled(in: AppSettings(citizenshipCountryCodes: ["FI"])))
        #expect(DashboardCardID.embassy.isFeatureEnabled(in: AppSettings(citizenshipCountryCodes: ["FI", "SE"])))
    }

    @Test
    func collapsedCardsDefaultToEmpty() {
        #expect(AppSettings().dashboardCollapsedCards.isEmpty)
    }

    @Test
    func collapsedCardsRoundTripThroughCoding() throws {
        let settings = AppSettings(dashboardCollapsedCards: [.weather, .meteredData])
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))

        #expect(decoded.dashboardCollapsedCards == [.weather, .meteredData])
    }

    @Test
    func legacySettingsWithoutCollapsedCardsStillDecode() throws {
        let payload = """
        {
          "appearanceMode": "system",
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
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(payload.utf8))

        #expect(decoded.dashboardCollapsedCards.isEmpty)
    }

    @Test
    func collapsedCardsIgnoreUnknownAndMigrateLegacyIdentifiers() throws {
        let payload = """
        {
          "dashboardCollapsedCards": ["weather", "localPriceLevel", "notACard"],
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
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(payload.utf8))

        #expect(decoded.dashboardCollapsedCards == [.weather, .localInfo])
    }
}
