import Foundation
import NomadCore
@testable import NomadUI
import Testing

struct NomadUITests {
    @Test
    func previewFixtureExposesDashboardSnapshot() {
        #expect(PreviewFixtures.snapshot.network.downloadHistory.isEmpty == false)
    }

    @Test
    func negativeMinutesFormatAsUnavailable() {
        #expect(NomadFormatters.minutes(-1) == "n/a")
    }

    @Test
    func travelAlertsPresentationShowsAllClearState() {
        let presentation = TravelAlertsCardPresentation(
            preferences: TravelAlertPreferences(advisoryEnabled: true, weatherEnabled: true, securityEnabled: true),
            snapshot: makeTravelAlertsSnapshot(
                states: [
                    makeState(kind: .advisory, status: .ready, severity: .clear, summary: "No elevated advisories."),
                    makeState(kind: .weather, status: .ready, severity: .clear, summary: "No active weather alerts."),
                    makeState(kind: .security, status: .ready, severity: .clear, summary: "No recent security bulletins.")
                ]
            )
        )

        #expect(presentation.badge == TravelAlertsBadgePresentation.severity(.clear))
        #expect(presentation.showsAllClearRow)
    }

    @Test
    func travelAlertsPresentationShowsWarningSeverityForReadySignal() {
        let presentation = TravelAlertsCardPresentation(
            preferences: TravelAlertPreferences(advisoryEnabled: true, weatherEnabled: true, securityEnabled: false),
            snapshot: makeTravelAlertsSnapshot(
                enabledKinds: [.advisory, .weather],
                states: [
                    makeState(kind: .advisory, status: .ready, severity: .clear, summary: "No elevated advisories."),
                    makeState(kind: .weather, status: .ready, severity: .warning, summary: "Flood warning in effect.", count: 2)
                ]
            )
        )

        #expect(presentation.badge == TravelAlertsBadgePresentation.severity(.warning))
        #expect(presentation.rows.first(where: { $0.id == TravelAlertKind.weather })?.summary == "Flood warning in effect.")
        #expect(presentation.rows.first(where: { $0.id == TravelAlertKind.weather })?.count == 2)
    }

    @Test
    func travelAlertsPresentationKeepsStaleRowVisible() {
        let presentation = TravelAlertsCardPresentation(
            preferences: TravelAlertPreferences(advisoryEnabled: false, weatherEnabled: true, securityEnabled: false),
            snapshot: makeTravelAlertsSnapshot(
                enabledKinds: [.weather],
                states: [
                    makeState(kind: .weather, status: .stale, severity: .warning, summary: "Flood warning in effect.", count: 2)
                ]
            )
        )

        let row = presentation.rows.first
        #expect(presentation.badge == TravelAlertsBadgePresentation.severity(.warning))
        #expect(row?.status == TravelAlertSignalStatus.stale)
        #expect(row?.summary == "Last known: Flood warning in effect.")
    }

    @Test
    func travelAlertsPresentationShowsExplicitUnavailableReason() {
        let presentation = TravelAlertsCardPresentation(
            preferences: TravelAlertPreferences(advisoryEnabled: false, weatherEnabled: false, securityEnabled: true),
            snapshot: makeTravelAlertsSnapshot(
                enabledKinds: [.security],
                states: [
                    TravelAlertSignalState(
                        kind: .security,
                        status: .unavailable,
                        signal: nil,
                        reason: .sourceConfigurationRequired,
                        sourceName: "ReliefWeb",
                        sourceURL: URL(string: "https://reliefweb.int"),
                        lastAttemptedAt: .now,
                        lastSuccessAt: nil
                    )
                ]
            )
        )

        let row = presentation.rows.first
        #expect(presentation.badge == TravelAlertsBadgePresentation.limited)
        #expect(row?.status == TravelAlertSignalStatus.unavailable)
        #expect(row?.summary == "Source setup required")
        #expect(row?.sourceName == "ReliefWeb")
    }

    @Test
    func travelAlertsPresentationDoesNotCollapseMixedResolvedRowsIntoCheckingFallback() {
        let presentation = TravelAlertsCardPresentation(
            preferences: TravelAlertPreferences(advisoryEnabled: true, weatherEnabled: true, securityEnabled: true),
            snapshot: makeTravelAlertsSnapshot(
                states: [
                    makeState(kind: .advisory, status: .ready, severity: .clear, summary: "No elevated advisories."),
                    TravelAlertSignalState(
                        kind: .weather,
                        status: .unavailable,
                        signal: nil,
                        reason: .locationRequired,
                        sourceName: "WeatherKit",
                        sourceURL: URL(string: "https://developer.apple.com/weatherkit/"),
                        lastAttemptedAt: .now,
                        lastSuccessAt: nil
                    ),
                    makeState(kind: .security, status: .stale, severity: .info, summary: "Nearby bulletin published.")
                ]
            )
        )

        #expect(presentation.badge == TravelAlertsBadgePresentation.stale)
        #expect(presentation.rows.count == 3)
        #expect(presentation.rows.contains { $0.status == TravelAlertSignalStatus.checking } == false)
        #expect(presentation.rows.contains { $0.summary == "Checking alerts…" } == false)
    }

    @Test
    func surfSectionPresentationShowsWeatherOnlyStateWhenSpotIsNotConfigured() {
        let snapshot = DashboardSnapshot(
            network: DashboardSnapshot.preview.network,
            power: DashboardSnapshot.preview.power,
            travelContext: DashboardSnapshot.preview.travelContext,
            travelAlerts: DashboardSnapshot.preview.travelAlerts,
            weather: DashboardSnapshot.preview.weather,
            marine: nil,
            appState: DashboardSnapshot.preview.appState
        )
        let presentation = SurfSectionPresentation(settings: AppSettings(), snapshot: snapshot)

        #expect(presentation.state == .notConfigured)
        #expect(presentation.marine == nil)
        #expect(presentation.emptyMessage == "Add a surf spot in Settings.")
        #expect(presentation.emptyActionTitle == "Set Surf Spot")
    }

    @Test
    func surfSectionPresentationShowsMarineMetricsWhenSpotAndMarineDataExist() {
        var settings = AppSettings()
        settings.surfSpotName = "El Saler"
        settings.surfSpotLatitude = 39.355
        settings.surfSpotLongitude = -0.314

        let presentation = SurfSectionPresentation(settings: settings, snapshot: DashboardSnapshot.preview)

        #expect(presentation.state == .ready)
        #expect(presentation.spotName == "El Saler")
        #expect(presentation.waveSummary == "1.6 m · 11 s")
        #expect(presentation.swellSummary == "1.2 m · E")
        #expect(presentation.windSummary == "18 km/h · NW")
        #expect(presentation.forecastSlots.count == 4)
        #expect(presentation.forecastSlots.first?.title == "Now")
    }

    @Test
    func surfSectionPresentationShowsInvalidSpotState() {
        var settings = AppSettings()
        settings.surfSpotName = "Broken Spot"
        settings.surfSpotLatitude = 120
        settings.surfSpotLongitude = -0.314

        let presentation = SurfSectionPresentation(settings: settings, snapshot: DashboardSnapshot.placeholder)

        #expect(presentation.state == .invalid)
        #expect(presentation.emptyMessage == "Fix surf spot coordinates in Settings.")
        #expect(presentation.emptyActionTitle == "Open Surf Settings")
    }

    @Test
    func surfSectionPresentationShowsUnavailableStateForConfiguredSpotWithoutMarineData() {
        var settings = AppSettings()
        settings.surfSpotName = "El Saler"
        settings.surfSpotLatitude = 39.355
        settings.surfSpotLongitude = -0.314

        let snapshot = DashboardSnapshot(
            network: DashboardSnapshot.preview.network,
            power: DashboardSnapshot.preview.power,
            travelContext: DashboardSnapshot.preview.travelContext,
            travelAlerts: DashboardSnapshot.preview.travelAlerts,
            weather: DashboardSnapshot.preview.weather,
            marine: nil,
            appState: DashboardSnapshot.preview.appState
        )
        let presentation = SurfSectionPresentation(settings: settings, snapshot: snapshot)

        #expect(presentation.state == .unavailable)
        #expect(presentation.emptyMessage == "Surf check unavailable.")
        #expect(presentation.emptyActionTitle == nil)
    }

    @Test
    func weatherSectionPresentationExplainsBuildIssue() {
        let presentation = WeatherSectionPresentation(
            settings: AppSettings(),
            snapshot: DashboardSnapshot.placeholder,
            weatherAvailabilityExplanation: "WeatherKit is unavailable in this build because the app is not signed for WeatherKit access.",
            locationStatusDetail: nil
        )

        #expect(presentation.badge.title == "Build Issue")
        #expect(presentation.subtitle == "WeatherKit unavailable in this build")
        #expect(presentation.emptyTitle == "WeatherKit Unavailable")
    }

    @Test
    func weatherSectionPresentationUsesLocationDetailWhenWeatherNeedsLocation() {
        let snapshot = DashboardSnapshot(
            network: DashboardSnapshot.preview.network,
            power: DashboardSnapshot.preview.power,
            travelContext: DashboardSnapshot.preview.travelContext,
            travelAlerts: DashboardSnapshot.preview.travelAlerts,
            weather: nil,
            marine: nil,
            appState: AppStatusSnapshot(lastRefresh: .now, updateState: .idle, issues: [.weatherLocationRequired])
        )
        let presentation = WeatherSectionPresentation(
            settings: AppSettings(),
            snapshot: snapshot,
            weatherAvailabilityExplanation: nil,
            locationStatusDetail: "Allow location access to use current weather."
        )

        #expect(presentation.badge.title == "Location Needed")
        #expect(presentation.emptyMessage == "Allow location access to use current weather.")
    }
}

private func makeTravelAlertsSnapshot(
    enabledKinds: [TravelAlertKind] = [.advisory, .weather, .security],
    primaryCountryCode: String? = "ES",
    primaryCountryName: String? = "Spain",
    coverageCountryCodes: [String] = ["ES", "FR", "PT"],
    states: [TravelAlertSignalState]
) -> TravelAlertsSnapshot {
    TravelAlertsSnapshot(
        enabledKinds: enabledKinds,
        primaryCountryCode: primaryCountryCode,
        primaryCountryName: primaryCountryName,
        coverageCountryCodes: coverageCountryCodes,
        states: states,
        fetchedAt: .now
    )
}

private func makeState(
    kind: TravelAlertKind,
    status: TravelAlertSignalStatus,
    severity: TravelAlertSeverity,
    summary: String,
    sourceName: String? = nil,
    count: Int? = nil
) -> TravelAlertSignalState {
    let defaultSourceName: String = switch kind {
    case .advisory:
        "Smartraveller"
    case .weather:
        "WeatherKit"
    case .security:
        "ReliefWeb"
    }

    return TravelAlertSignalState(
        kind: kind,
        status: status,
        signal: TravelAlertSignalSnapshot(
            kind: kind,
            severity: severity,
            title: kind.rawValue,
            summary: summary,
            sourceName: sourceName ?? defaultSourceName,
            sourceURL: nil,
            updatedAt: .now,
            affectedCountryCodes: ["ES"],
            itemCount: count
        ),
        reason: nil,
        sourceName: sourceName ?? defaultSourceName,
        sourceURL: nil,
        lastAttemptedAt: .now,
        lastSuccessAt: .now
    )
}
