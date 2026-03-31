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
    func powerMetricsPresentationShowsBatteryTimeRemaining() {
        let presentation = PowerMetricsPresentation(snapshot: makePowerSnapshot(
            state: .battery,
            timeRemainingMinutes: 87,
            timeToFullChargeMinutes: nil
        ))

        #expect(presentation.drainValue == "11.2 W")
        #expect(presentation.timeLeftValue == "1h 27m")
    }

    @Test
    func powerMetricsPresentationFallsBackToOnBatteryWithoutWattage() {
        let presentation = PowerMetricsPresentation(snapshot: makePowerSnapshot(
            state: .battery,
            timeRemainingMinutes: 87,
            timeToFullChargeMinutes: nil,
            dischargeRateWatts: nil
        ))

        #expect(presentation.drainValue == "On battery")
        #expect(presentation.timeLeftValue == "1h 27m")
    }

    @Test
    func powerMetricsPresentationShowsChargingTimeToFull() {
        let presentation = PowerMetricsPresentation(snapshot: makePowerSnapshot(
            state: .charging,
            timeRemainingMinutes: nil,
            timeToFullChargeMinutes: 13
        ))

        #expect(presentation.drainValue == "Charging")
        #expect(presentation.timeLeftValue == "13m")
    }

    @Test
    func powerMetricsPresentationFallsBackToPluggedInWhileChargingWithoutEstimate() {
        let presentation = PowerMetricsPresentation(snapshot: makePowerSnapshot(
            state: .charging,
            timeRemainingMinutes: nil,
            timeToFullChargeMinutes: nil
        ))

        #expect(presentation.drainValue == "Charging")
        #expect(presentation.timeLeftValue == "Plugged in")
    }

    @Test
    func powerMetricsPresentationShowsPluggedInWhenCharged() {
        let presentation = PowerMetricsPresentation(snapshot: makePowerSnapshot(
            state: .charged,
            timeRemainingMinutes: nil,
            timeToFullChargeMinutes: nil
        ))

        #expect(presentation.drainValue == "Plugged in")
        #expect(presentation.timeLeftValue == "Plugged in")
    }

    @Test
    func internetStatusIndicatorModelShowsWideOnlineState() {
        let model = InternetStatusIndicatorModel(
            connectivity: ConnectivitySnapshot(pathAvailable: true, internetState: .online, lastCheckedAt: .now),
            style: .wideInline
        )

        #expect(model.symbolName == "checkmark.circle.fill")
        #expect(model.iconTreatment == .plain)
        #expect(model.label == "Online")
        #expect(model.accessibilityLabel == "Internet online")
        #expect(model.tone == .online)
        #expect(model.style == .wideInline)
    }

    @Test
    func internetStatusIndicatorModelCollapsesToIconInCompactMode() {
        let model = InternetStatusIndicatorModel(
            connectivity: ConnectivitySnapshot(pathAvailable: true, internetState: .offline, lastCheckedAt: .now),
            style: .compactIcon
        )

        #expect(model.symbolName == "wifi.slash")
        #expect(model.iconTreatment == .warningBadge)
        #expect(model.label == nil)
        #expect(model.accessibilityLabel == "Internet offline")
        #expect(model.tone == .offline)
        #expect(model.style == .compactIcon)
    }

    @Test
    func internetStatusIndicatorModelShowsCheckingLabelInWideMode() {
        let model = InternetStatusIndicatorModel(
            connectivity: ConnectivitySnapshot(pathAvailable: nil, internetState: .checking, lastCheckedAt: nil),
            style: .wideInline
        )

        #expect(model.symbolName == "ellipsis.circle.fill")
        #expect(model.iconTreatment == .plain)
        #expect(model.label == "Checking")
        #expect(model.accessibilityLabel == "Checking internet")
        #expect(model.tone == .checking)
    }

    @Test
    func dashboardRefreshHeaderPresentationShowsManualRefreshStatus() {
        let presentation = DashboardRefreshHeaderPresentation(
            lastRefresh: .now.addingTimeInterval(-30),
            refreshActivity: .manualInProgress
        )

        #expect(presentation.statusText == "Refreshing dashboard…")
        #expect(presentation.buttonTitle == "Refreshing dashboard")
        #expect(presentation.isButtonEnabled == false)
    }

    @Test
    func dashboardRefreshHeaderPresentationShowsBackgroundRefreshStatus() {
        let presentation = DashboardRefreshHeaderPresentation(
            lastRefresh: .now.addingTimeInterval(-30),
            refreshActivity: .slowAutomaticInProgress
        )

        #expect(presentation.statusText == "Background refresh…")
        #expect(presentation.buttonTitle == "Background refresh in progress")
        #expect(presentation.isButtonEnabled == false)
    }

    @Test
    func dashboardRefreshHeaderPresentationShowsLastRefreshWhenIdle() {
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let presentation = DashboardRefreshHeaderPresentation(
            lastRefresh: referenceDate,
            refreshActivity: .idle
        )

        #expect(presentation.statusText == "Last refresh \(NomadFormatters.relativeDate(referenceDate))")
        #expect(presentation.buttonTitle == "Refresh")
        #expect(presentation.isButtonEnabled)
    }

    @Test
    func timeTrackingQuickActionsPresentationUsesLatestProjectsInReverseRecencyOrder() {
        let presentation = TimeTrackingQuickActionsPresentation(
            activeProjects: [
                TimeTrackingProject(name: "One"),
                TimeTrackingProject(name: "Two"),
                TimeTrackingProject(name: "Three"),
                TimeTrackingProject(name: "Four"),
                TimeTrackingProject(name: "Five")
            ],
            pendingDurationText: "2m",
            activityState: .running
        )

        #expect(presentation.latestProjects(maxCount: 4).map(\.trimmedName) == ["Five", "Four", "Three", "Two"])
        #expect(presentation.latestProjects(maxCount: 3).map(\.trimmedName) == ["Five", "Four", "Three"])
    }

    @Test
    func timeTrackingQuickActionsPresentationExcludesArchivedAndBlankProjects() {
        let presentation = TimeTrackingQuickActionsPresentation(
            activeProjects: [
                TimeTrackingProject(name: "Alpha"),
                TimeTrackingProject(name: "   "),
                TimeTrackingProject(name: "Archived", isArchived: true),
                TimeTrackingProject(name: "Bravo")
            ],
            pendingDurationText: "2m",
            activityState: .running
        )

        #expect(presentation.latestProjects(maxCount: 4).map(\.trimmedName) == ["Bravo", "Alpha"])
    }

    @Test
    func timeTrackingQuickActionsPresentationBuildsDialogBucketChips() {
        let projectA = TimeTrackingProject(name: "Alpha")
        let projectB = TimeTrackingProject(name: "Bravo")
        let projectC = TimeTrackingProject(name: "Charlie")
        let projectD = TimeTrackingProject(name: "Delta")
        let presentation = TimeTrackingQuickActionsPresentation(
            activeProjects: [projectA, projectB, projectC, projectD],
            pendingDurationText: "2m",
            activityState: .running
        )

        let chips = presentation.quickBucketChips(maxProjectCount: 3, includeUnallocated: true)
        #expect(chips.map(\.title) == ["Delta", "Charlie", "Bravo", "Other", "Unallocated"])
        #expect(chips.map(\.bucket.stableID) == [
            TimeTrackingBucket.project(projectD.id).stableID,
            TimeTrackingBucket.project(projectC.id).stableID,
            TimeTrackingBucket.project(projectB.id).stableID,
            TimeTrackingBucket.other.stableID,
            TimeTrackingBucket.unallocated.stableID
        ])
    }

    @Test
    func timeTrackingQuickActionsPresentationKeepsHeaderControlsAvailable() {
        let presentation = TimeTrackingQuickActionsPresentation(
            activeProjects: [TimeTrackingProject(name: "Long Client Project Name That Should Truncate In UI")],
            pendingDurationText: "2m",
            activityState: .running
        )

        #expect(presentation.pendingDurationText == "2m")
        #expect(presentation.activityTitle == "Running")
        #expect(presentation.primaryControlTitle == "Pause")
        #expect(presentation.primaryControlSystemImage == "pause.fill")
        #expect(presentation.stopControlTitle == "Stop")
        #expect(presentation.stopControlSystemImage == "stop.fill")
        #expect(presentation.otherChipTitle == "Other")
        #expect(presentation.openTitle == "Open")
        #expect(presentation.openSystemImage == "clock.badge.checkmark")
        #expect(presentation.latestProjects(maxCount: 3).first?.trimmedName == "Long Client Project Name That Should Truncate In UI")
    }

    @Test
    func timeTrackingQuickActionsPresentationBuildsHeaderCompactConfigurations() {
        let recentProjects = [
            TimeTrackingProject(name: "Alpha"),
            TimeTrackingProject(name: "Bravo"),
            TimeTrackingProject(name: "Charlie")
        ]
        let presentation = TimeTrackingQuickActionsPresentation(
            activeProjects: recentProjects,
            recentProjects: recentProjects,
            pendingDurationText: "14m",
            activityState: .running
        )

        let configurations = presentation.headerCompactConfigurations(maxProjectCount: 2)
        #expect(configurations.map { $0.chips.map(\.title) } == [
            ["Alpha", "Bravo", "Other"],
            ["Alpha", "Other"],
            ["Other"],
            []
        ])
    }

    @Test
    func timeTrackingQuickActionsPresentationMapsVisibleHeaderControlsByState() {
        let running = TimeTrackingQuickActionsPresentation(
            activeProjects: [],
            pendingDurationText: "2m",
            activityState: .running
        )
        let paused = TimeTrackingQuickActionsPresentation(
            activeProjects: [],
            pendingDurationText: "2m",
            activityState: .paused
        )
        let stopped = TimeTrackingQuickActionsPresentation(
            activeProjects: [],
            pendingDurationText: "2m",
            activityState: .stopped
        )

        #expect(running.primaryControlIcon.title == "Pause")
        #expect(running.primaryControlIcon.systemImage == "pause.fill")
        #expect(running.visibleHeaderControls.map(\.title) == ["Pause"])
        #expect(paused.primaryControlIcon.title == "Resume")
        #expect(paused.primaryControlIcon.systemImage == "play.fill")
        #expect(paused.visibleHeaderControls.map(\.title) == ["Resume", "Stop"])
        #expect(stopped.primaryControlIcon.title == "Play")
        #expect(stopped.primaryControlIcon.systemImage == "play.fill")
        #expect(stopped.visibleHeaderControls.map(\.title) == ["Play"])
    }

    @Test
    func timeTrackingQuickActionsPresentationUsesRecentProjectRecommendations() {
        let alpha = TimeTrackingProject(name: "Alpha")
        let beta = TimeTrackingProject(name: "Beta")
        let gamma = TimeTrackingProject(name: "Gamma")
        let presentation = TimeTrackingQuickActionsPresentation(
            activeProjects: [alpha, beta, gamma],
            recentProjects: [gamma, alpha],
            pendingDurationText: "9m",
            activityState: .paused
        )

        #expect(presentation.recommendedProjects(maxCount: 2).map(\.trimmedName) == ["Gamma", "Alpha"])
    }

    @Test
    func timeTrackingQuickActionsPresentationDropsArchivedRecommendations() {
        let active = TimeTrackingProject(name: "Active")
        let archived = TimeTrackingProject(name: "Archived", isArchived: true)
        let presentation = TimeTrackingQuickActionsPresentation(
            activeProjects: [active],
            recentProjects: [archived, active],
            pendingDurationText: "9m",
            activityState: .running
        )

        #expect(presentation.recommendedProjects(maxCount: 2).map(\.trimmedName) == ["Active"])
    }

    @Test
    func alertsSummaryTilePresentationShowsTemperatureAndClearState() {
        let presentation = SummaryTilePresentation(
            weather: makeWeatherSnapshot(),
            alertsPresentation: TravelAlertsCardPresentation(
                preferences: TravelAlertPreferences(advisoryEnabled: true, weatherEnabled: true, securityEnabled: true),
                snapshot: makeTravelAlertsSnapshot(
                    states: [
                        makeState(kind: .advisory, status: .ready, severity: .clear, summary: "No elevated advisories."),
                        makeState(kind: .weather, status: .ready, severity: .clear, summary: "No active weather alerts."),
                        makeState(kind: .security, status: .ready, severity: .clear, summary: "No recent security bulletins.")
                    ]
                )
            )
        )

        #expect(presentation.title == "Alerts")
        #expect(presentation.label == "Clear")
        #expect(presentation.detail == "18 C · No current alerts")
        #expect(presentation.tone == .ready)
    }

    @Test
    func alertsSummaryTilePresentationUsesHighestSeverityAlertSummary() {
        let presentation = SummaryTilePresentation(
            weather: makeWeatherSnapshot(),
            alertsPresentation: TravelAlertsCardPresentation(
                preferences: TravelAlertPreferences(advisoryEnabled: true, weatherEnabled: true, securityEnabled: true),
                snapshot: makeTravelAlertsSnapshot(
                    states: [
                        makeState(kind: .advisory, status: .ready, severity: .caution, summary: "France remains at a higher caution level nearby."),
                        makeState(kind: .weather, status: .ready, severity: .warning, summary: "Flood warning in effect."),
                        makeState(kind: .security, status: .stale, severity: .info, summary: "One recent security bulletin was published nearby.")
                    ]
                )
            )
        )

        #expect(presentation.label == "Warning")
        #expect(presentation.detail == "18 C · Flood warning in effect.")
        #expect(presentation.tone == .attention)
    }

    @Test
    func alertsSummaryTilePresentationShowsDisabledState() {
        let presentation = SummaryTilePresentation(
            weather: makeWeatherSnapshot(),
            alertsPresentation: TravelAlertsCardPresentation(
                preferences: TravelAlertPreferences(advisoryEnabled: false, weatherEnabled: false, securityEnabled: false),
                snapshot: nil
            )
        )

        #expect(presentation.label == "Off")
        #expect(presentation.detail == "18 C · Alerts off")
        #expect(presentation.tone == .neutral)
    }

    @Test
    func networkSummaryTilePresentationIncludesLatencyAndJitter() {
        let presentation = SummaryTilePresentation(
            title: "Network",
            network: NetworkSectionSnapshot(
                throughput: NetworkThroughputSample(
                    downloadBytesPerSecond: 8_000_000,
                    uploadBytesPerSecond: 2_000_000,
                    activeInterface: "en0",
                    collectedAt: .now
                ),
                connectivity: ConnectivitySnapshot(pathAvailable: true, internetState: .online, lastCheckedAt: .now),
                latency: LatencySample(host: "1.1.1.1", milliseconds: 28, jitterMilliseconds: 48, collectedAt: .now),
                downloadHistory: [],
                uploadHistory: [],
                latencyHistory: []
            ),
            health: SectionHealth(label: "Attention", level: .attention, reason: "Jitter 48 ms", symbolName: "waveform.path.ecg")
        )

        #expect(presentation.detail == "Latency 28 ms · Jitter 48 ms")
        #expect(presentation.tone == .attention)
    }

    @Test
    func powerSummaryTilePresentationPrefixesBatteryPercentage() {
        let presentation = SummaryTilePresentation(
            title: "Power",
            power: PowerSectionSnapshot(
                snapshot: makePowerSnapshot(
                    state: .charged,
                    timeRemainingMinutes: nil,
                    timeToFullChargeMinutes: nil
                ),
                chargeHistory: [],
                dischargeHistory: []
            ),
            health: SectionHealth(label: "Ready", level: .ready, reason: "Connected to power", symbolName: "powerplug.fill")
        )

        #expect(presentation.detail == "72% · Connected to power")
        #expect(presentation.tone == .ready)
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
    func travelAlertsPresentationPrefersDiagnosticSummaryForUnavailableSource() {
        let presentation = TravelAlertsCardPresentation(
            preferences: TravelAlertPreferences(advisoryEnabled: false, weatherEnabled: false, securityEnabled: true),
            snapshot: makeTravelAlertsSnapshot(
                enabledKinds: [.security],
                states: [
                    TravelAlertSignalState(
                        kind: .security,
                        status: .unavailable,
                        signal: nil,
                        reason: .sourceUnavailable,
                        diagnosticSummary: "ReliefWeb returned HTTP 429.",
                        sourceName: "ReliefWeb",
                        sourceURL: URL(string: "https://reliefweb.int"),
                        lastAttemptedAt: .now,
                        lastSuccessAt: nil
                    )
                ]
            )
        )

        let row = presentation.rows.first
        #expect(row?.status == TravelAlertSignalStatus.unavailable)
        #expect(row?.summary == "ReliefWeb returned HTTP 429.")
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
        #expect(presentation.forecastSlots.first?.title == "+3h")
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

    @Test
    func weatherForecastPresentationDefaultsToCollapsedDisclosures() {
        let presentation = WeatherForecastPresentation(
            settings: AppSettings(),
            weather: makeWeatherSnapshot(),
            widthMode: .wide
        )

        #expect(presentation.showsHourlyDisclosure)
        #expect(presentation.showsDailyDisclosure)
        #expect(presentation.isHourlyExpanded == false)
        #expect(presentation.isDailyExpanded == false)
        #expect(presentation.shouldShowTomorrowSummary)
    }

    @Test
    func weatherForecastPresentationReflectsPersistedExpandedState() {
        var settings = AppSettings()
        settings.weatherHourlyForecastExpanded = true
        settings.weatherDailyForecastExpanded = true

        let presentation = WeatherForecastPresentation(
            settings: settings,
            weather: makeWeatherSnapshot(),
            widthMode: .wide
        )

        #expect(presentation.isHourlyExpanded)
        #expect(presentation.isDailyExpanded)
        #expect(presentation.shouldShowTomorrowSummary == false)
    }

    @Test
    func weatherForecastPresentationKeepsNarrowCardsCompact() {
        var settings = AppSettings()
        settings.weatherHourlyForecastExpanded = true
        settings.weatherDailyForecastExpanded = true

        let presentation = WeatherForecastPresentation(
            settings: settings,
            weather: makeWeatherSnapshot(),
            widthMode: .narrow
        )

        #expect(presentation.showsHourlyDisclosure == false)
        #expect(presentation.showsDailyDisclosure == false)
        #expect(presentation.isHourlyExpanded == false)
        #expect(presentation.isDailyExpanded == false)
        #expect(presentation.shouldShowTomorrowSummary)
    }

    @Test
    func fuelPricesSectionPresentationShowsRowsForReadySnapshot() {
        var settings = AppSettings()
        settings.fuelPricesEnabled = true

        let presentation = FuelPricesSectionPresentation(
            settings: settings,
            snapshot: DashboardSnapshot.preview,
            locationStatusDetail: nil
        )

        #expect(presentation.badge.title == "Live")
        #expect(presentation.visualMode == .animatedCamper)
        #expect(presentation.rows.count == 2)
        #expect(presentation.rows.first?.title == "Diesel")
        #expect(presentation.rows.map(\.hasMapActions) == [true, true])
    }

    @Test
    func fuelPricesSectionPresentationUsesAmbientModeWhileChecking() {
        var settings = AppSettings()
        settings.fuelPricesEnabled = true

        let snapshot = DashboardSnapshot(
            network: DashboardSnapshot.preview.network,
            power: DashboardSnapshot.preview.power,
            travelContext: DashboardSnapshot.preview.travelContext,
            travelAlerts: DashboardSnapshot.preview.travelAlerts,
            weather: DashboardSnapshot.preview.weather,
            fuelPrices: nil,
            marine: DashboardSnapshot.preview.marine,
            appState: DashboardSnapshot.preview.appState
        )

        let presentation = FuelPricesSectionPresentation(
            settings: settings,
            snapshot: snapshot,
            locationStatusDetail: nil
        )

        #expect(presentation.visualMode == .ambient)
        #expect(presentation.emptyTitle == "Checking Fuel Prices")
    }

    @Test
    func fuelPricesSectionPresentationUsesLocationDetailWhenCurrentLocationIsMissing() {
        var settings = AppSettings()
        settings.fuelPricesEnabled = true

        let snapshot = DashboardSnapshot(
            network: DashboardSnapshot.preview.network,
            power: DashboardSnapshot.preview.power,
            travelContext: DashboardSnapshot.preview.travelContext,
            travelAlerts: DashboardSnapshot.preview.travelAlerts,
            weather: DashboardSnapshot.preview.weather,
            fuelPrices: FuelPriceSnapshot(
                status: .locationRequired,
                sourceName: "Nomad Fuel Prices",
                sourceURL: nil,
                countryCode: nil,
                countryName: nil,
                searchRadiusKilometers: 50,
                diesel: nil,
                gasoline: nil,
                fetchedAt: nil,
                detail: "Allow current location to look up nearby fuel prices."
            ),
            marine: DashboardSnapshot.preview.marine,
            appState: DashboardSnapshot.preview.appState
        )

        let presentation = FuelPricesSectionPresentation(
            settings: settings,
            snapshot: snapshot,
            locationStatusDetail: "Allow location access to use current fuel prices."
        )

        #expect(presentation.badge.title == "Location Needed")
        #expect(presentation.visualMode == .ambient)
        #expect(presentation.emptyMessage == "Allow location access to use current fuel prices.")
    }

    @Test
    func fuelPricesSectionPresentationExplainsUnsupportedCountry() {
        var settings = AppSettings()
        settings.fuelPricesEnabled = true

        let snapshot = DashboardSnapshot(
            network: DashboardSnapshot.preview.network,
            power: DashboardSnapshot.preview.power,
            travelContext: DashboardSnapshot.preview.travelContext,
            travelAlerts: DashboardSnapshot.preview.travelAlerts,
            weather: DashboardSnapshot.preview.weather,
            fuelPrices: FuelPriceSnapshot(
                status: .unsupported,
                sourceName: "Nomad Fuel Prices",
                sourceURL: nil,
                countryCode: "FI",
                countryName: "Finland",
                searchRadiusKilometers: 50,
                diesel: nil,
                gasoline: nil,
                fetchedAt: .now,
                detail: "Fuel prices are not supported in Finland yet."
            ),
            marine: DashboardSnapshot.preview.marine,
            appState: DashboardSnapshot.preview.appState
        )

        let presentation = FuelPricesSectionPresentation(
            settings: settings,
            snapshot: snapshot,
            locationStatusDetail: nil
        )

        #expect(presentation.badge.title == "Unsupported")
        #expect(presentation.visualMode == .ambient)
        #expect(presentation.emptyMessage == "Fuel prices are not supported in Finland yet.")
    }

    @Test
    func fuelPricesSectionPresentationKeepsNormalizedDiagnosticNote() {
        var settings = AppSettings()
        settings.fuelPricesEnabled = true

        let snapshot = DashboardSnapshot(
            network: DashboardSnapshot.preview.network,
            power: DashboardSnapshot.preview.power,
            travelContext: DashboardSnapshot.preview.travelContext,
            travelAlerts: DashboardSnapshot.preview.travelAlerts,
            weather: DashboardSnapshot.preview.weather,
            fuelPrices: FuelPriceSnapshot(
                status: .unavailable,
                sourceName: "Spanish Ministry Fuel Prices",
                sourceURL: URL(string: "https://example.com/fuel"),
                countryCode: "ES",
                countryName: "Spain",
                searchRadiusKilometers: 50,
                diesel: nil,
                gasoline: nil,
                fetchedAt: .now,
                detail: "Nearby fuel prices are unavailable right now.",
                note: "Fuel source TLS handshake failed."
            ),
            fuelDiagnostics: FuelDiagnosticsSnapshot(
                status: .unavailable,
                stage: .requestStarted,
                countryCode: "ES",
                countryName: "Spain",
                latitude: 39.4699,
                longitude: -0.3763,
                searchRadiusKilometers: 50,
                providerName: "Spanish Ministry Fuel Prices",
                sourceURL: URL(string: "https://example.com/fuel"),
                startedAt: .now.addingTimeInterval(-1),
                finishedAt: .now,
                elapsedMilliseconds: 1_000,
                summary: "Fuel source TLS handshake failed.",
                error: nil
            ),
            marine: DashboardSnapshot.preview.marine,
            appState: DashboardSnapshot.preview.appState
        )

        let presentation = FuelPricesSectionPresentation(
            settings: settings,
            snapshot: snapshot,
            locationStatusDetail: nil
        )

        #expect(presentation.visualMode == .ambient)
        #expect(presentation.note == "Fuel source TLS handshake failed.")
    }

    @Test
    func fuelPricesSectionPresentationShowsGoogleFallbackOnlyForInvalidCoordinates() {
        var settings = AppSettings()
        settings.fuelPricesEnabled = true

        let snapshot = DashboardSnapshot(
            network: DashboardSnapshot.preview.network,
            power: DashboardSnapshot.preview.power,
            travelContext: DashboardSnapshot.preview.travelContext,
            travelAlerts: DashboardSnapshot.preview.travelAlerts,
            weather: DashboardSnapshot.preview.weather,
            fuelPrices: FuelPriceSnapshot(
                status: .ready,
                sourceName: "Spanish Ministry Fuel Prices",
                sourceURL: URL(string: "https://example.com/fuel"),
                countryCode: "ES",
                countryName: "Spain",
                searchRadiusKilometers: 50,
                diesel: FuelStationPrice(
                    fuelType: .diesel,
                    stationName: "Broken Station",
                    address: "Harbor Road 12",
                    locality: "Valencia",
                    pricePerLiter: 1.429,
                    distanceKilometers: 4.8,
                    latitude: 190,
                    longitude: -0.3763,
                    updatedAt: .now
                ),
                gasoline: nil,
                fetchedAt: .now,
                detail: "Cheapest prices within 50 km.",
                note: nil
            ),
            marine: DashboardSnapshot.preview.marine,
            appState: DashboardSnapshot.preview.appState
        )

        let presentation = FuelPricesSectionPresentation(
            settings: settings,
            snapshot: snapshot,
            locationStatusDetail: nil
        )

        #expect(presentation.rows.count == 1)
        #expect(presentation.rows.first?.hasPreviewMapAction == false)
        #expect(presentation.rows.first?.hasGoogleMapsAction == true)
        #expect(presentation.rows.first?.hasMapActions == true)
    }

    @Test
    func emergencyCareSectionPresentationShowsRowsForReadySnapshot() {
        var settings = AppSettings()
        settings.emergencyCareEnabled = true

        let presentation = EmergencyCareSectionPresentation(
            settings: settings,
            snapshot: DashboardSnapshot.preview,
            locationStatusDetail: nil
        )

        #expect(presentation.badge.title == "Nearby")
        #expect(presentation.rows.count == 3)
        #expect(presentation.rows.first?.ownershipTitle == "Public")
        #expect(presentation.rows.last?.ownershipTitle == nil)
        #expect(presentation.rows.map(\.hasMapActions) == [true, true, true])
    }

    @Test
    func emergencyCareSectionPresentationUsesExpandedRadiusSubtitleForReadySnapshot() {
        var settings = AppSettings()
        settings.emergencyCareEnabled = true

        let snapshot = DashboardSnapshot(
            network: DashboardSnapshot.preview.network,
            power: DashboardSnapshot.preview.power,
            travelContext: DashboardSnapshot.preview.travelContext,
            travelAlerts: DashboardSnapshot.preview.travelAlerts,
            weather: DashboardSnapshot.preview.weather,
            fuelPrices: DashboardSnapshot.preview.fuelPrices,
            fuelDiagnostics: DashboardSnapshot.preview.fuelDiagnostics,
            emergencyCare: EmergencyCareSnapshot(
                status: .ready,
                sourceName: "Apple Maps",
                sourceURL: URL(string: "https://maps.apple.com"),
                searchRadiusKilometers: 50,
                hospitals: DashboardSnapshot.preview.emergencyCare?.hospitals ?? [],
                fetchedAt: .now,
                detail: "Nearby emergency hospitals within 50 km."
            ),
            marine: DashboardSnapshot.preview.marine,
            appState: DashboardSnapshot.preview.appState
        )

        let presentation = EmergencyCareSectionPresentation(
            settings: settings,
            snapshot: snapshot,
            locationStatusDetail: nil
        )

        #expect(presentation.subtitle == "Within 50 km")
        #expect(presentation.rows.count == 3)
    }

    @Test
    func emergencyCareSectionPresentationUsesCheckingStateWhileSnapshotIsMissing() {
        var settings = AppSettings()
        settings.emergencyCareEnabled = true

        let snapshot = DashboardSnapshot(
            network: DashboardSnapshot.preview.network,
            power: DashboardSnapshot.preview.power,
            travelContext: DashboardSnapshot.preview.travelContext,
            travelAlerts: DashboardSnapshot.preview.travelAlerts,
            weather: DashboardSnapshot.preview.weather,
            fuelPrices: DashboardSnapshot.preview.fuelPrices,
            fuelDiagnostics: DashboardSnapshot.preview.fuelDiagnostics,
            emergencyCare: nil,
            marine: DashboardSnapshot.preview.marine,
            appState: DashboardSnapshot.preview.appState
        )

        let presentation = EmergencyCareSectionPresentation(
            settings: settings,
            snapshot: snapshot,
            locationStatusDetail: nil
        )

        #expect(presentation.badge.title == "Checking")
        #expect(presentation.emptyTitle == "Checking Emergency Care")
    }

    @Test
    func emergencyCareSectionPresentationUsesLocationDetailWhenLocationIsMissing() {
        var settings = AppSettings()
        settings.emergencyCareEnabled = true

        let snapshot = DashboardSnapshot(
            network: DashboardSnapshot.preview.network,
            power: DashboardSnapshot.preview.power,
            travelContext: DashboardSnapshot.preview.travelContext,
            travelAlerts: DashboardSnapshot.preview.travelAlerts,
            weather: DashboardSnapshot.preview.weather,
            fuelPrices: DashboardSnapshot.preview.fuelPrices,
            fuelDiagnostics: DashboardSnapshot.preview.fuelDiagnostics,
            emergencyCare: EmergencyCareSnapshot(
                status: .locationRequired,
                sourceName: "Apple Maps",
                sourceURL: URL(string: "https://maps.apple.com"),
                searchRadiusKilometers: 25,
                hospitals: [],
                fetchedAt: nil,
                detail: "Allow current location to look up nearby emergency hospitals."
            ),
            marine: DashboardSnapshot.preview.marine,
            appState: DashboardSnapshot.preview.appState
        )

        let presentation = EmergencyCareSectionPresentation(
            settings: settings,
            snapshot: snapshot,
            locationStatusDetail: "Allow location access to use current emergency care."
        )

        #expect(presentation.badge.title == "Location Needed")
        #expect(presentation.emptyMessage == "Allow location access to use current emergency care.")
    }

    @Test
    func emergencyCareSectionPresentationShowsNoMatchesCopy() {
        var settings = AppSettings()
        settings.emergencyCareEnabled = true

        let snapshot = DashboardSnapshot(
            network: DashboardSnapshot.preview.network,
            power: DashboardSnapshot.preview.power,
            travelContext: DashboardSnapshot.preview.travelContext,
            travelAlerts: DashboardSnapshot.preview.travelAlerts,
            weather: DashboardSnapshot.preview.weather,
            fuelPrices: DashboardSnapshot.preview.fuelPrices,
            fuelDiagnostics: DashboardSnapshot.preview.fuelDiagnostics,
            emergencyCare: EmergencyCareSnapshot(
                status: .noHospitalsFound,
                sourceName: "Apple Maps",
                sourceURL: URL(string: "https://maps.apple.com"),
                searchRadiusKilometers: 25,
                hospitals: [],
                fetchedAt: .now,
                detail: "No nearby emergency hospitals were found."
            ),
            marine: DashboardSnapshot.preview.marine,
            appState: DashboardSnapshot.preview.appState
        )

        let presentation = EmergencyCareSectionPresentation(
            settings: settings,
            snapshot: snapshot,
            locationStatusDetail: nil
        )

        #expect(presentation.badge.title == "No Matches")
        #expect(presentation.emptyTitle == "No Nearby Hospitals")
        #expect(presentation.emptyMessage == "No nearby emergency hospitals were found.")
    }

    @Test
    func fuelCardVisibilityRatioReflectsVisibleHeight() {
        let ratio = fuelCardVisibilityRatio(
            frame: CGRect(x: 0, y: 520, width: 300, height: 200),
            viewportHeight: 640
        )

        #expect(abs(ratio - 0.6) < 0.000_1)
    }

    @Test
    func fuelBackdropAnimationStateStartsAnimatingAtVisibilityThreshold() {
        let state = fuelBackdropAnimationState(
            frame: CGRect(x: 0, y: 570, width: 300, height: 200),
            viewportHeight: 640,
            visualMode: .animatedCamper,
            reduceMotion: false
        )

        #expect(abs(state.visibilityRatio - 0.35) < 0.000_1)
        #expect(state.isAnimating)
    }

    @Test
    func fuelBackdropAnimationStateStopsAnimatingWhenCardIsNotVisibleEnough() {
        let state = fuelBackdropAnimationState(
            frame: CGRect(x: 0, y: 580, width: 300, height: 200),
            viewportHeight: 640,
            visualMode: .animatedCamper,
            reduceMotion: false
        )

        #expect(abs(state.visibilityRatio - 0.3) < 0.000_1)
        #expect(state.isAnimating == false)
    }

    @Test
    func fuelBackdropAnimationStateStaysStaticForAmbientMode() {
        let state = fuelBackdropAnimationState(
            frame: CGRect(x: 0, y: 420, width: 300, height: 200),
            viewportHeight: 640,
            visualMode: .ambient,
            reduceMotion: false
        )

        #expect(abs(state.visibilityRatio - 1) < 0.000_1)
        #expect(state.isAnimating == false)
    }
}

private func makeWeatherSnapshot() -> WeatherSnapshot {
    var dailyForecast: [WeatherDaySummary] = []
    for dayOffset in 1...7 {
        dailyForecast.append(
            WeatherDaySummary(
                date: Calendar.current.date(byAdding: .day, value: dayOffset, to: .now) ?? .now,
                symbolName: dayOffset == 1 ? "cloud.sun.fill" : "sun.max.fill",
                summary: dayOffset == 1 ? "Tomorrow outlook" : "Day \(dayOffset)",
                temperatureMinCelsius: Double(10 + dayOffset),
                temperatureMaxCelsius: Double(18 + dayOffset),
                precipitationChance: Double(dayOffset) / 100
            )
        )
    }

    return WeatherSnapshot(
        currentTemperatureCelsius: 18,
        apparentTemperatureCelsius: 17,
        conditionDescription: "Partly Cloudy",
        symbolName: "cloud.sun.fill",
        precipitationChance: 0.18,
        windSpeedKph: 14,
        hourlyForecastSlots: [
            WeatherHourlyForecastSlot(
                date: Date().addingTimeInterval(3 * 3_600),
                symbolName: "cloud.sun.fill",
                conditionDescription: "Partly Cloudy",
                temperatureCelsius: 19,
                precipitationChance: 0.1,
                windSpeedKph: 12
            ),
            WeatherHourlyForecastSlot(
                date: Date().addingTimeInterval(6 * 3_600),
                symbolName: "sun.max.fill",
                conditionDescription: "Clear",
                temperatureCelsius: 20,
                precipitationChance: 0.05,
                windSpeedKph: 10
            ),
            WeatherHourlyForecastSlot(
                date: Date().addingTimeInterval(12 * 3_600),
                symbolName: "cloud.fill",
                conditionDescription: "Cloudy",
                temperatureCelsius: 16,
                precipitationChance: 0.22,
                windSpeedKph: 15
            ),
            WeatherHourlyForecastSlot(
                date: Date().addingTimeInterval(24 * 3_600),
                symbolName: "cloud.rain.fill",
                conditionDescription: "Rain",
                temperatureCelsius: 15,
                precipitationChance: 0.48,
                windSpeedKph: 18
            )
        ],
        dailyForecast: dailyForecast,
        fetchedAt: .now
    )
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

private func makePowerSnapshot(
    state: PowerSourceState,
    timeRemainingMinutes: Int?,
    timeToFullChargeMinutes: Int?,
    dischargeRateWatts: Double? = 11.2
) -> PowerSnapshot {
    PowerSnapshot(
        chargePercent: 0.72,
        state: state,
        timeRemainingMinutes: timeRemainingMinutes,
        timeToFullChargeMinutes: timeToFullChargeMinutes,
        isLowPowerModeEnabled: false,
        dischargeRateWatts: dischargeRateWatts,
        adapterWatts: nil,
        collectedAt: .now
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
    let defaultSourceName = switch kind {
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
