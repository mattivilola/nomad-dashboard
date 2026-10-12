import Foundation
import NomadCore
import Testing

struct CitizenshipSettingsTests {
    private static let legacyPayload = """
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

    @Test
    func citizenshipDefaultsToNone() {
        #expect(AppSettings().citizenshipCountryCodes.isEmpty)
    }

    @Test
    func legacySettingsWithoutCitizenshipStillDecode() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(Self.legacyPayload.utf8))

        #expect(decoded.citizenshipCountryCodes.isEmpty)
        #expect(DashboardCardID.embassy.isFeatureEnabled(in: decoded) == false)
    }

    @Test
    func citizenshipRoundTripsThroughCodingInOrder() throws {
        let settings = AppSettings(citizenshipCountryCodes: ["SE", "FI"])
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))

        #expect(decoded.citizenshipCountryCodes == ["SE", "FI"])
        #expect(decoded == settings)
    }

    @Test
    func sanitizerUppercasesDeduplicatesAndKeepsOrder() {
        #expect(AppSettings.sanitizedCitizenshipCodes(["fi", " se ", "FI", "SE", "no"]) == ["FI", "SE", "NO"])
    }

    @Test
    func sanitizerDropsAnythingThatIsNotATwoLetterCode() {
        #expect(AppSettings.sanitizedCitizenshipCodes(["", "F", "FIN", "1A", "É1", "ÅÄ", "fi"]) == ["FI"])
    }

    @Test
    func sanitizerCapsAtThreeCountries() {
        #expect(AppSettings.maximumCitizenships == 3)
        #expect(AppSettings.sanitizedCitizenshipCodes(["FI", "SE", "NO", "DK", "IS"]) == ["FI", "SE", "NO"])
        #expect(AppSettings(citizenshipCountryCodes: ["FI", "SE", "NO", "DK"]).citizenshipCountryCodes == ["FI", "SE", "NO"])
    }

    @Test
    func decodingSanitizesPersistedCitizenship() throws {
        let payload = Self.legacyPayload.replacingOccurrences(
            of: "\"appearanceMode\": \"system\",",
            with: "\"appearanceMode\": \"system\", \"citizenshipCountryCodes\": [\"fi\", \"FI\", \"xyz\", \"se\", \"no\", \"dk\"],"
        )
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(payload.utf8))

        #expect(decoded.citizenshipCountryCodes == ["FI", "SE", "NO"])
    }

    @Test
    func malformedPersistedCitizenshipDecodesAsEmptyInsteadOfFailing() throws {
        let payload = Self.legacyPayload.replacingOccurrences(
            of: "\"appearanceMode\": \"system\",",
            with: "\"appearanceMode\": \"system\", \"citizenshipCountryCodes\": \"FI\","
        )
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(payload.utf8))

        #expect(decoded.citizenshipCountryCodes.isEmpty)
    }

    @Test
    func embassyCardSitsRightAfterEmergencyCareInEveryRecommendedOrder() {
        for profile in TravelProfile.allCases {
            let order = DashboardCardID.defaultOrder(for: profile)
            let emergencyIndex = order.firstIndex(of: .emergencyCare)
            let embassyIndex = order.firstIndex(of: .embassy)

            #expect(emergencyIndex != nil)
            #expect(embassyIndex == emergencyIndex.map { $0 + 1 })
        }
    }

    @Test
    func anUntouchedOrderFromBeforeTheEmbassyCardBecomesTheNewDefault() {
        let legacyDefault = DashboardCardID.defaultOrder.filter { $0 != .embassy }
        let settings = AppSettings(dashboardCardOrder: legacyDefault)

        #expect(settings.dashboardCardOrder == DashboardCardID.defaultOrder)
        #expect(settings.isUsingRecommendedOrder)
    }

    @Test
    func anUntouchedRoadTripOrderFromBeforeTheEmbassyCardBecomesTheNewRoadTripDefault() {
        let legacyRoadTrip = DashboardCardID.defaultOrder(for: .roadTrip).filter { $0 != .embassy }
        let settings = AppSettings(travelProfile: .roadTrip, dashboardCardOrder: legacyRoadTrip)

        #expect(settings.dashboardCardOrder == DashboardCardID.defaultOrder(for: .roadTrip))
        #expect(settings.isUsingRecommendedOrder)
    }

    @Test
    func aCustomizedOrderGetsTheEmbassyCardRightAfterEmergencyCare() {
        let custom: [DashboardCardID] = [.weather, .emergencyCare, .power, .connectivity]
        let sanitized = DashboardCardID.sanitizedOrder(custom)

        #expect(sanitized.first == .weather)
        #expect(sanitized.firstIndex(of: .embassy) == sanitized.firstIndex(of: .emergencyCare).map { $0 + 1 })
        #expect(Set(sanitized) == Set(DashboardCardID.allCases))
        #expect(sanitized.count == DashboardCardID.allCases.count)
    }

    @Test
    func missingCardsFollowTheirNearestPresentPredecessorOrComeFirst() {
        // Without Emergency Care the embassy card follows Fuel Prices, the nearest earlier default card present.
        let withoutEmergency = DashboardCardID.sanitizedOrder([.fuelPrices, .weather])
        #expect(withoutEmergency.firstIndex(of: .embassy) == withoutEmergency.firstIndex(of: .emergencyCare).map { $0 + 1 })

        // Nothing before it present: the first default card goes to the very start.
        #expect(DashboardCardID.sanitizedOrder([.weather]).first == .connectivity)
        #expect(DashboardCardID.sanitizedOrder([]) == DashboardCardID.defaultOrder)
    }

    @Test
    func sanitizingIsIdempotentAndDropsDuplicates() {
        let order: [DashboardCardID] = [.weather, .weather, .power]
        let once = DashboardCardID.sanitizedOrder(order)

        #expect(DashboardCardID.sanitizedOrder(once) == once)
        #expect(once.filter { $0 == .weather }.count == 1)
    }

    @Test
    func analyticsPropertiesNeverCarryUserSettings() {
        let context = AnalyticsContext(
            appID: "id",
            appName: "Nomad Dashboard",
            appVersion: "1",
            buildNumber: "1",
            distributionChannel: .test,
            appType: .menuBar
        )

        #expect(Set(context.baseProperties.keys) == [
            "app_name", "app_version", "build_number", "distribution_channel", "app_type"
        ])
    }
}
