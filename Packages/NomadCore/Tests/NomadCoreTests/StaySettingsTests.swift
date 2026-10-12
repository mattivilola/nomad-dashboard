import Foundation
import NomadCore
import Testing

struct StaySettingsTests {
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

    // MARK: - Defaults and legacy decoding

    @Test
    func defaults() {
        let settings = AppSettings()

        #expect(settings.stayAllowances.isEmpty)
        #expect(settings.schengenCounterEnabled)
        #expect(settings.taxResidenceDaysEnabled)
        #expect(settings.taxResidenceThresholdDays == 183)
        #expect(settings.arrivalBriefingEnabled)
        #expect(settings.arrivalBriefingAcknowledgedCountryCode == nil)
        #expect(settings.arrivalBriefingAcknowledgedAt == nil)
    }

    @Test
    func legacySettingsWithoutStayKeysStillDecodeToTheDefaults() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(Self.legacyPayload.utf8))

        #expect(decoded.stayAllowances.isEmpty)
        #expect(decoded.schengenCounterEnabled)
        #expect(decoded.taxResidenceDaysEnabled)
        #expect(decoded.taxResidenceThresholdDays == 183)
        #expect(decoded.arrivalBriefingEnabled)
        #expect(decoded.arrivalBriefingAcknowledgedCountryCode == nil)
        #expect(decoded.arrivalBriefingAcknowledgedAt == nil)
    }

    @Test
    func stayAndBriefingSettingsRoundTripThroughCoding() throws {
        let acknowledgedAt = Date(timeIntervalSince1970: 1_791_806_400)
        let settings = AppSettings(
            stayAllowances: ["MA": 90, "TH": 60],
            schengenCounterEnabled: false,
            taxResidenceDaysEnabled: false,
            taxResidenceThresholdDays: 90,
            arrivalBriefingEnabled: false,
            arrivalBriefingAcknowledgedCountryCode: "PT",
            arrivalBriefingAcknowledgedAt: acknowledgedAt
        )
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))

        #expect(decoded == settings)
        #expect(decoded.stayAllowances == ["MA": 90, "TH": 60])
        #expect(decoded.schengenCounterEnabled == false)
        #expect(decoded.taxResidenceDaysEnabled == false)
        #expect(decoded.taxResidenceThresholdDays == 90)
        #expect(decoded.arrivalBriefingEnabled == false)
        #expect(decoded.arrivalBriefingAcknowledgedCountryCode == "PT")
        #expect(decoded.arrivalBriefingAcknowledgedAt == acknowledgedAt)
    }

    // MARK: - Sanitizing

    @Test
    func stayAllowancesAreSanitizedToCountryCodesAndDays() {
        let sanitized = AppSettings.sanitizedStayAllowances([
            " ma ": 90, "TH": 60, "xyz": 30, "1A": 30, "": 30, "ES": 0, "FR": -5, "PT": 4_000
        ])

        #expect(sanitized == ["MA": 90, "TH": 60, "PT": 365])
        #expect(AppSettings(stayAllowances: ["ma": 400, "ES": 0]).stayAllowances == ["MA": 365])
        #expect(AppSettings.sanitizedStayAllowances(["ma": 30, "MA": 60]) == ["MA": 60])
    }

    @Test
    func taxResidenceThresholdIsClamped() {
        #expect(AppSettings(taxResidenceThresholdDays: 10).taxResidenceThresholdDays == 30)
        #expect(AppSettings(taxResidenceThresholdDays: 30).taxResidenceThresholdDays == 30)
        #expect(AppSettings(taxResidenceThresholdDays: 183).taxResidenceThresholdDays == 183)
        #expect(AppSettings(taxResidenceThresholdDays: 365).taxResidenceThresholdDays == 365)
        #expect(AppSettings(taxResidenceThresholdDays: 1_000).taxResidenceThresholdDays == 365)
    }

    @Test
    func acknowledgedBriefingCountryIsNormalizedOrDropped() {
        #expect(AppSettings(arrivalBriefingAcknowledgedCountryCode: " pt ").arrivalBriefingAcknowledgedCountryCode == "PT")
        #expect(AppSettings(arrivalBriefingAcknowledgedCountryCode: "Portugal").arrivalBriefingAcknowledgedCountryCode == nil)
    }

    @Test
    func decodingSanitizesPersistedStayValues() throws {
        let payload = Self.legacyPayload.replacingOccurrences(
            of: "\"appearanceMode\": \"system\",",
            with: """
            "appearanceMode": "system", "stayAllowances": {"ma": 90, "xyz": 5, "ES": 0, "PT": 999},
            "taxResidenceThresholdDays": 5, "arrivalBriefingAcknowledgedCountryCode": "pt",
            """
        )
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(payload.utf8))

        #expect(decoded.stayAllowances == ["MA": 90, "PT": 365])
        #expect(decoded.taxResidenceThresholdDays == 30)
        #expect(decoded.arrivalBriefingAcknowledgedCountryCode == "PT")
    }

    @Test
    func malformedPersistedAllowancesDecodeAsEmptyInsteadOfFailing() throws {
        let payload = Self.legacyPayload.replacingOccurrences(
            of: "\"appearanceMode\": \"system\",",
            with: "\"appearanceMode\": \"system\", \"stayAllowances\": [\"MA\", 90],"
        )
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(payload.utf8))

        #expect(decoded.stayAllowances.isEmpty)
    }

    // MARK: - Stays card

    @Test
    func staysCardSitsRightAfterTravelContextAndAfterTravelAlertsOnTheRoad() {
        let nomad = DashboardCardID.defaultOrder
        #expect(nomad.firstIndex(of: .stays) == nomad.firstIndex(of: .travelContext).map { $0 + 1 })

        let roadTrip = DashboardCardID.defaultOrder(for: .roadTrip)
        #expect(roadTrip.firstIndex(of: .stays) == roadTrip.firstIndex(of: .travelAlerts).map { $0 + 1 })
        #expect(Set(roadTrip) == Set(DashboardCardID.allCases))
    }

    @Test
    func staysCardFollowsTheVisitedPlacesSetting() {
        #expect(DashboardCardID.stays.isFeatureEnabled(in: AppSettings(visitedPlacesEnabled: true)))
        #expect(DashboardCardID.stays.isFeatureEnabled(in: AppSettings(visitedPlacesEnabled: false)) == false)
    }

    @Test
    func anUntouchedOrderFromBeforeTheStaysCardBecomesTheNewDefault() {
        let legacyDefault = DashboardCardID.defaultOrder.filter { $0 != .stays }
        let settings = AppSettings(dashboardCardOrder: legacyDefault)

        #expect(settings.dashboardCardOrder == DashboardCardID.defaultOrder)
        #expect(settings.isUsingRecommendedOrder)
    }

    @Test
    func anUntouchedRoadTripOrderFromBeforeTheStaysCardBecomesTheNewRoadTripDefault() throws {
        let legacyRoadTrip = DashboardCardID.defaultOrder(for: .roadTrip).filter { $0 != .stays }
        let settings = AppSettings(travelProfile: .roadTrip, dashboardCardOrder: legacyRoadTrip)

        #expect(settings.dashboardCardOrder == DashboardCardID.defaultOrder(for: .roadTrip))
        #expect(settings.isUsingRecommendedOrder)

        // The same through persisted settings, where the profile is decoded before the order.
        var persisted = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings(travelProfile: .roadTrip))) as? [String: Any]
        )
        persisted["dashboardCardOrder"] = legacyRoadTrip.map(\.rawValue)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: persisted))
        #expect(decoded.dashboardCardOrder == DashboardCardID.defaultOrder(for: .roadTrip))
    }

    @Test
    func aCustomizedOrderGetsTheStaysCardRightAfterTravelContext() {
        let custom: [DashboardCardID] = [.weather, .travelContext, .power, .connectivity]
        let sanitized = DashboardCardID.sanitizedOrder(custom)

        #expect(sanitized.first == .weather)
        #expect(sanitized.firstIndex(of: .stays) == sanitized.firstIndex(of: .travelContext).map { $0 + 1 })
        #expect(Set(sanitized) == Set(DashboardCardID.allCases))
        #expect(sanitized.count == DashboardCardID.allCases.count)

        // Without Travel Context it follows the nearest earlier default card that is present.
        let withoutContext = DashboardCardID.sanitizedOrder([.power, .localInfo])
        #expect(withoutContext.firstIndex(of: .stays) == withoutContext.firstIndex(of: .travelContext).map { $0 + 1 })
    }
}
