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
    func powerMetricsPresentationShowsChargingTimeToFullAndOmitsUnknownAdapter() {
        let presentation = PowerMetricsPresentation(snapshot: makePowerSnapshot(
            state: .charging,
            timeRemainingMinutes: nil,
            timeToFullChargeMinutes: 13
        ))

        #expect(presentation.drainValue == nil)
        #expect(presentation.timeLeftTitle == "To Full")
        #expect(presentation.timeLeftValue == "13m")
        #expect(presentation.summary == "Charging · 13m to full")
    }

    @Test
    func powerMetricsPresentationShowsAdapterWattageWhileCharging() {
        let presentation = PowerMetricsPresentation(snapshot: makePowerSnapshot(
            state: .charging,
            timeRemainingMinutes: nil,
            timeToFullChargeMinutes: 40,
            adapterWatts: 96
        ))

        #expect(presentation.drainTitle == "Adapter")
        #expect(presentation.drainValue == "96.0 W")
    }

    @Test
    func powerMetricsPresentationEstimatesChargingWithoutTimeToFullInsteadOfRepeatingTheSubtitle() {
        let presentation = PowerMetricsPresentation(snapshot: makePowerSnapshot(
            state: .charging,
            timeRemainingMinutes: nil,
            timeToFullChargeMinutes: nil
        ))

        #expect(presentation.drainValue == nil)
        #expect(presentation.timeLeftValue == "Estimating")
        #expect(presentation.summary == "Charging")
    }

    @Test
    func powerMetricsPresentationShowsFullWhenCharged() {
        let presentation = PowerMetricsPresentation(snapshot: makePowerSnapshot(
            state: .charged,
            timeRemainingMinutes: nil,
            timeToFullChargeMinutes: nil,
            adapterWatts: 67
        ))

        #expect(presentation.drainTitle == "Adapter")
        #expect(presentation.drainValue == "67.0 W")
        #expect(presentation.timeLeftValue == "Full")
        #expect(presentation.summary == "Plugged in")
    }

    @Test
    func powerMetricsPresentationOmitsAdapterWhenChargedWithoutWattage() {
        let presentation = PowerMetricsPresentation(snapshot: makePowerSnapshot(
            state: .charged,
            timeRemainingMinutes: nil,
            timeToFullChargeMinutes: nil
        ))

        #expect(presentation.drainValue == nil)
        #expect(presentation.timeLeftValue == "Full")
    }

    @Test
    func powerMetricsPresentationSummarisesBatteryTimeLeft() {
        let presentation = PowerMetricsPresentation(snapshot: makePowerSnapshot(
            state: .battery,
            timeRemainingMinutes: 150,
            timeToFullChargeMinutes: nil
        ))

        #expect(presentation.summary == "2h 30m left")
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
    func inlineButtonHighlightedActionUsesExplicitThemeColors() {
        let style = DashboardInlineButtonAppearance.make(role: .highlighted, isEnabled: true)

        #expect(style == DashboardInlineButtonAppearance(
            foreground: NomadTheme.teal.opacity(1),
            background: NomadTheme.inlineButtonBackground.opacity(1),
            border: NomadTheme.cardBorder.opacity(1)
        ))
    }

    @Test
    func inlineButtonNeutralActionUsesExplicitThemeColors() {
        let style = DashboardInlineButtonAppearance.make(role: .neutral, isEnabled: true)

        #expect(style == DashboardInlineButtonAppearance(
            foreground: NomadTheme.primaryText.opacity(1),
            background: NomadTheme.inlineButtonBackground.opacity(1),
            border: NomadTheme.cardBorder.opacity(1)
        ))
    }

    @Test
    func inlineButtonDisabledHighlightedActionKeepsVisibleReducedOpacity() {
        let style = DashboardInlineButtonAppearance.make(role: .highlighted, isEnabled: false)

        #expect(style == DashboardInlineButtonAppearance(
            foreground: NomadTheme.teal.opacity(0.72),
            background: NomadTheme.inlineButtonBackground.opacity(0.76),
            border: NomadTheme.cardBorder.opacity(0.76)
        ))
    }

    @Test
    func inlineButtonCanFillAvailableWidth() {
        let layout = DashboardInlineButtonLayout.make(
            isCompact: true,
            fillsAvailableWidth: true
        )

        #expect(layout == DashboardInlineButtonLayout(
            horizontalPadding: 10,
            verticalPadding: 6,
            fillsAvailableWidth: true
        ))
    }

    @Test
    func inlineButtonKeepsIntrinsicWidthByDefault() {
        let layout = DashboardInlineButtonLayout.make(
            isCompact: false,
            fillsAvailableWidth: false
        )

        #expect(layout == DashboardInlineButtonLayout(
            horizontalPadding: 12,
            verticalPadding: 7,
            fillsAvailableWidth: false
        ))
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
    func timeTrackingQuickActionsPresentationFallsBackToLatestActiveProjectsWhenRecentsAreMissing() {
        let alpha = TimeTrackingProject(name: "Alpha")
        let bravo = TimeTrackingProject(name: "Bravo")
        let charlie = TimeTrackingProject(name: "Charlie")
        let presentation = TimeTrackingQuickActionsPresentation(
            activeProjects: [alpha, bravo, charlie],
            recentProjects: [],
            pendingDurationText: "9m",
            activityState: .running
        )

        #expect(presentation.recommendedProjects(maxCount: 2).map(\.trimmedName) == ["Charlie", "Bravo"])
    }

    @Test
    func timeTrackingQuickActionsPresentationDedupesRecentProjectsAgainstActiveFallback() {
        let alpha = TimeTrackingProject(name: "Alpha")
        let bravo = TimeTrackingProject(name: "Bravo")
        let charlie = TimeTrackingProject(name: "Charlie")
        let presentation = TimeTrackingQuickActionsPresentation(
            activeProjects: [alpha, bravo, charlie],
            recentProjects: [bravo],
            pendingDurationText: "9m",
            activityState: .running
        )

        #expect(presentation.recommendedProjects(maxCount: 3).map(\.trimmedName) == ["Bravo", "Charlie", "Alpha"])
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
        #expect(presentation.detail == "18° · No current alerts")
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
        #expect(presentation.detail == "18° · Flood warning in effect.")
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
        #expect(presentation.detail == "18° · Alerts off")
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
        let updatedAt = fixedTravelAlertDate(day: 7)
        let presentation = TravelAlertsCardPresentation(
            preferences: TravelAlertPreferences(advisoryEnabled: true, weatherEnabled: true, securityEnabled: false),
            snapshot: makeTravelAlertsSnapshot(
                enabledKinds: [.advisory, .weather],
                states: [
                    makeState(kind: .advisory, status: .ready, severity: .clear, summary: "No elevated advisories."),
                    makeState(
                        kind: .weather,
                        status: .ready,
                        severity: .warning,
                        summary: "Flood warning in effect.",
                        count: 2,
                        updatedAt: updatedAt
                    )
                ]
            )
        )

        let row = presentation.rows.first(where: { $0.id == TravelAlertKind.weather })
        #expect(presentation.badge == TravelAlertsBadgePresentation.severity(.warning))
        #expect(row?.summary == "Flood warning in effect.")
        #expect(row?.count == 2)
        #expect(row?.statusLabel == "Warning")
        #expect(row?.impactText == "Review before travel")
        #expect(row?.freshnessText == "Updated 7 Apr")
        #expect(row?.metadataText == "WeatherKit · Updated 7 Apr")
    }

    @Test
    func travelAlertsPresentationKeepsAdvisoryDetailSummarySeparateFromMainSummary() {
        let presentation = TravelAlertsCardPresentation(
            preferences: TravelAlertPreferences(advisoryEnabled: true, weatherEnabled: false, securityEnabled: false),
            snapshot: makeTravelAlertsSnapshot(
                enabledKinds: [.advisory],
                states: [
                    makeState(
                        kind: .advisory,
                        status: .ready,
                        severity: .caution,
                        summary: "France nearby: exercise a high degree of caution.",
                        detailSummary: "Exercise a high degree of caution in France due to the threat of terrorism.",
                        sourceURL: URL(string: "https://example.com/france")
                    )
                ]
            )
        )

        let row = presentation.rows.first
        #expect(row?.summary == "France nearby: exercise a high degree of caution.")
        #expect(row?.detailSummary == "Exercise a high degree of caution in France due to the threat of terrorism.")
        #expect(row?.sourceURL?.absoluteString == "https://example.com/france")
    }

    @Test
    func travelAlertsPresentationKeepsStaleRowVisible() {
        let lastSuccessAt = fixedTravelAlertDate(day: 7)
        let presentation = TravelAlertsCardPresentation(
            preferences: TravelAlertPreferences(advisoryEnabled: false, weatherEnabled: true, securityEnabled: false),
            snapshot: makeTravelAlertsSnapshot(
                enabledKinds: [.weather],
                states: [
                    makeState(
                        kind: .weather,
                        status: .stale,
                        severity: .warning,
                        summary: "Flood warning in effect.",
                        count: 2,
                        lastSuccessAt: lastSuccessAt
                    )
                ]
            )
        )

        let row = presentation.rows.first
        #expect(presentation.badge == TravelAlertsBadgePresentation.severity(.warning))
        #expect(row?.status == TravelAlertSignalStatus.stale)
        #expect(row?.statusLabel == "Stale")
        #expect(row?.impactText == "Last known signal")
        #expect(row?.summary == "Last known: Flood warning in effect.")
        #expect(row?.freshnessText == "Last good refresh 7 Apr")
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
        #expect(row?.statusLabel == "Unavailable")
        #expect(row?.impactText == "Source issue")
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

        #expect(presentation.badge == TravelAlertsBadgePresentation.severity(.info))
        #expect(presentation.staleNotice != nil)
        #expect(presentation.limitedNotice?.text == "Some sources unavailable")
        #expect(presentation.rows.count == 3)
        #expect(presentation.rows.contains { $0.status == TravelAlertSignalStatus.checking } == false)
        #expect(presentation.rows.contains { $0.summary == "Checking alerts…" } == false)
    }

    @Test
    func travelAlertsHeaderBadgeShowsHighestLevelEvenWhenASignalIsStale() {
        let lastSuccessAt = fixedTravelAlertDate(day: 12)
        let presentation = TravelAlertsCardPresentation(
            preferences: TravelAlertPreferences(advisoryEnabled: true, weatherEnabled: true, securityEnabled: false),
            snapshot: makeTravelAlertsSnapshot(
                enabledKinds: [.advisory, .weather],
                states: [
                    makeState(kind: .advisory, status: .ready, severity: .caution, summary: "Exercise caution."),
                    makeState(kind: .weather, status: .stale, severity: .clear, summary: "No active weather alerts.", lastSuccessAt: lastSuccessAt)
                ]
            )
        )

        #expect(presentation.badge == TravelAlertsBadgePresentation.severity(.caution))
        #expect(presentation.staleNotice == TravelAlertsCardPresentation.Notice(
            text: "Updated 12 Apr · may be outdated",
            symbolName: "clock.arrow.circlepath"
        ))
        #expect(presentation.limitedNotice == nil)
    }

    @Test
    func travelAlertsStaleNoticeUsesTheOldestGoodRefresh() {
        let presentation = TravelAlertsCardPresentation(
            preferences: TravelAlertPreferences(advisoryEnabled: true, weatherEnabled: true, securityEnabled: false),
            snapshot: makeTravelAlertsSnapshot(
                enabledKinds: [.advisory, .weather],
                states: [
                    makeState(kind: .advisory, status: .stale, severity: .clear, summary: "Clear.", lastSuccessAt: fixedTravelAlertDate(day: 9)),
                    makeState(kind: .weather, status: .stale, severity: .clear, summary: "Clear.", lastSuccessAt: fixedTravelAlertDate(day: 3))
                ]
            )
        )

        #expect(presentation.staleNotice?.text == "Updated 3 Apr · may be outdated")
    }

    @Test
    func travelAlertsCardHasNoNoticesWhenEverythingIsFresh() {
        let presentation = TravelAlertsCardPresentation(
            preferences: TravelAlertPreferences(advisoryEnabled: true, weatherEnabled: false, securityEnabled: false),
            snapshot: makeTravelAlertsSnapshot(
                enabledKinds: [.advisory],
                states: [makeState(kind: .advisory, status: .ready, severity: .warning, summary: "Warning.")]
            )
        )

        #expect(presentation.notices.isEmpty)
    }

    @Test
    func travelAlertRowOnlyShowsTheImpactLineWhenItAddsToTheStatusChip() throws {
        func row(_ severity: TravelAlertSeverity, status: TravelAlertSignalStatus = .ready) throws -> TravelAlertRowModel {
            let presentation = TravelAlertsCardPresentation(
                preferences: TravelAlertPreferences(advisoryEnabled: true, weatherEnabled: false, securityEnabled: false),
                snapshot: makeTravelAlertsSnapshot(
                    enabledKinds: [.advisory],
                    states: [makeState(kind: .advisory, status: status, severity: severity, summary: "Summary.")]
                )
            )
            return try #require(presentation.rows.first)
        }

        #expect(try row(.clear).showsImpactText == false)
        #expect(try row(.caution).showsImpactText == false)
        #expect(try row(.caution, status: .stale).showsImpactText == false)
        #expect(try row(.warning).showsImpactText)
        #expect(try row(.critical).showsImpactText)
        #expect(try row(.warning).impactText == "Review before travel")
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

        #expect(presentation.showsForecastDisclosure)
        #expect(presentation.isForecastExpanded == false)
        #expect(presentation.shouldShowTomorrowSummary)
    }

    @Test
    func weatherForecastPresentationReflectsPersistedExpandedState() {
        var settings = AppSettings()
        settings.weatherForecastExpanded = true

        let presentation = WeatherForecastPresentation(
            settings: settings,
            weather: makeWeatherSnapshot(),
            widthMode: .wide
        )

        #expect(presentation.isForecastExpanded)
        #expect(presentation.shouldShowTomorrowSummary == false)
    }

    @Test
    func weatherForecastPresentationKeepsNarrowCardsCompact() {
        var settings = AppSettings()
        settings.weatherForecastExpanded = true

        let presentation = WeatherForecastPresentation(
            settings: settings,
            weather: makeWeatherSnapshot(),
            widthMode: .narrow
        )

        #expect(presentation.showsForecastDisclosure == false)
        #expect(presentation.isForecastExpanded == false)
        #expect(presentation.shouldShowTomorrowSummary)
    }

    @Test
    func weatherForecastPresentationAlwaysKeepsTheHourlyStripVisible() {
        var settings = AppSettings()
        settings.weatherForecastExpanded = false

        for widthMode in [DashboardCardWidthMode.wide, .narrow] {
            let presentation = WeatherForecastPresentation(
                settings: settings,
                weather: makeWeatherSnapshot(),
                widthMode: widthMode
            )

            #expect(presentation.hourlySlots.count == 4)
        }
    }

    @Test
    func weatherForecastDisclosureOnlyGovernsTheDailyOutlook() {
        var settings = AppSettings()
        settings.weatherForecastExpanded = true

        let wide = WeatherForecastPresentation(settings: settings, weather: makeWeatherSnapshot(), widthMode: .wide)
        #expect(wide.hourlySlots.count == 4)
        #expect(wide.showsForecastDisclosure)
        #expect(wide.isForecastExpanded)
        #expect(wide.dailyRows.count == 7)

        let withoutDailyRows = WeatherSnapshot(
            currentTemperatureCelsius: 18,
            apparentTemperatureCelsius: 17,
            conditionDescription: "Clear",
            symbolName: "sun.max.fill",
            precipitationChance: 0,
            windSpeedKph: 5,
            windDirectionDegrees: 90,
            hourlyForecastSlots: makeWeatherSnapshot().hourlyForecastSlots,
            fetchedAt: .now
        )
        let hourlyOnly = WeatherForecastPresentation(settings: settings, weather: withoutDailyRows, widthMode: .wide)
        #expect(hourlyOnly.showsForecastDisclosure == false)
        #expect(hourlyOnly.hourlySlots.count == 4)
    }

    @Test
    func surfForecastSlotKeepsWindOnASingleLine() {
        let slot = SurfForecastSlotPresentation(
            index: 0,
            slot: MarineForecastSlot(
                date: Date().addingTimeInterval(3 * 3_600),
                waveHeightMeters: 1.2,
                swellHeightMeters: 1.0,
                windSpeedKph: 16,
                windDirectionDegrees: 315
            ),
            referenceDate: .now
        )

        #expect(slot.windValue == "16 km/h NW")
        #expect(slot.windValue.contains("\n") == false)
    }

    @Test
    func weatherWindMetricPresentationUsesKilometersPerHourDirectionAndMetersPerSecond() {
        let presentation = WeatherWindMetricPresentation(snapshot: makeWeatherSnapshot())

        #expect(presentation.primaryValue == "14 km/h NW")
        #expect(presentation.secondaryValue == "3.9 m/s")
    }

    @Test
    func weatherHourlyForecastSlotPresentationCombinesRainAndWind() {
        let slot = WeatherHourlyForecastSlotPresentation(
            index: 0,
            slot: makeWeatherSnapshot().hourlyForecastSlots[0],
            referenceDate: makeWeatherSnapshot().fetchedAt
        )

        #expect(slot.detailValue == "Rain 10% · 12 km/h NW")
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
    func localInfoSectionPresentationShowsLocationHolidayAndPriceRows() {
        var settings = AppSettings()
        settings.localInfoEnabled = true

        let presentation = LocalInfoSectionPresentation(
            settings: settings,
            snapshot: DashboardSnapshot.preview,
            locationStatusDetail: nil
        )

        #expect(presentation.badge.title == "Live")
        #expect(presentation.rows.map(\.title) == ["Emergency", "Public Holiday", "School Break", "Prices vs EU"])
        #expect(presentation.subtitle == "Valencia · Valencian Community, Spain · Europe/Madrid")
        #expect(presentation.sourceLine?.contains("Nager.Date") == true)
        #expect(presentation.rows.first(where: { $0.title == "School Break" })?.badge == nil)
        #expect(presentation.rows.first(where: { $0.title == "Public Holiday" })?.badge == nil)
    }

    @Test
    func localInfoSectionPresentationUsesLocationDetailWhenCountryContextIsMissing() {
        var settings = AppSettings()
        settings.localInfoEnabled = true

        let snapshot = DashboardSnapshot(
            network: DashboardSnapshot.preview.network,
            power: DashboardSnapshot.preview.power,
            travelContext: DashboardSnapshot.preview.travelContext,
            travelAlerts: DashboardSnapshot.preview.travelAlerts,
            weather: DashboardSnapshot.preview.weather,
            localInfo: LocalInfoSnapshot(
                status: .locationRequired,
                locality: nil,
                administrativeRegion: nil,
                countryCode: nil,
                countryName: nil,
                timeZoneIdentifier: nil,
                subdivisionCode: nil,
                publicHolidayStatus: LocalHolidayStatus(
                    state: .unavailable,
                    currentPeriod: nil,
                    nextPeriod: nil,
                    note: "Allow current location or external IP location to look up local holiday information."
                ),
                schoolHolidayStatus: nil,
                localPriceLevel: nil,
                sources: [],
                fetchedAt: nil,
                detail: "Allow current location or external IP location to estimate local info.",
                note: nil
            ),
            marine: DashboardSnapshot.preview.marine,
            appState: DashboardSnapshot.preview.appState
        )

        let presentation = LocalInfoSectionPresentation(
            settings: settings,
            snapshot: snapshot,
            locationStatusDetail: "Allow location access to use local info."
        )

        #expect(presentation.badge.title == "Location Needed")
        #expect(presentation.rows.isEmpty)
        #expect(presentation.emptyMessage == "Allow location access to use local info.")
    }

    @Test
    func localInfoSectionPresentationKeepsLocationRequiredStateEvenWithPartialPlaceText() {
        var settings = AppSettings()
        settings.localInfoEnabled = true

        let snapshot = DashboardSnapshot(
            network: DashboardSnapshot.preview.network,
            power: DashboardSnapshot.preview.power,
            travelContext: DashboardSnapshot.preview.travelContext,
            travelAlerts: DashboardSnapshot.preview.travelAlerts,
            weather: DashboardSnapshot.preview.weather,
            localInfo: LocalInfoSnapshot(
                status: .locationRequired,
                locality: "Paris",
                administrativeRegion: "Ile-de-France",
                countryCode: nil,
                countryName: "France",
                timeZoneIdentifier: "Europe/Paris",
                subdivisionCode: nil,
                publicHolidayStatus: LocalHolidayStatus(
                    state: .unavailable,
                    currentPeriod: nil,
                    nextPeriod: nil,
                    note: "Allow current location or external IP location to look up local holiday information."
                ),
                schoolHolidayStatus: nil,
                localPriceLevel: nil,
                sources: [],
                fetchedAt: nil,
                detail: "Allow current location or external IP location to estimate local info.",
                note: nil
            ),
            marine: DashboardSnapshot.preview.marine,
            appState: DashboardSnapshot.preview.appState
        )

        let presentation = LocalInfoSectionPresentation(
            settings: settings,
            snapshot: snapshot,
            locationStatusDetail: "Allow location access to use local info."
        )

        #expect(presentation.rows.isEmpty)
        #expect(presentation.emptyActionTitle == "Open Settings")
        #expect(presentation.emptyMessage == "Allow location access to use local info.")
    }

    @Test
    func localInfoSectionPresentationShowsBusyTodayBadgeForActivePublicHoliday() {
        var settings = AppSettings()
        settings.localInfoEnabled = true

        let snapshot = DashboardSnapshot(
            network: DashboardSnapshot.preview.network,
            power: DashboardSnapshot.preview.power,
            travelContext: DashboardSnapshot.preview.travelContext,
            travelAlerts: DashboardSnapshot.preview.travelAlerts,
            weather: DashboardSnapshot.preview.weather,
            localInfo: LocalInfoSnapshot(
                status: .partial,
                locality: "Paris",
                administrativeRegion: "Ile-de-France",
                countryCode: "FR",
                countryName: "France",
                timeZoneIdentifier: "Europe/Paris",
                subdivisionCode: nil,
                publicHolidayStatus: LocalHolidayStatus(
                    state: .current,
                    currentPeriod: HolidayPeriodSnapshot(
                        name: "Labour Day",
                        startDate: .now,
                        endDate: .now
                    ),
                    nextPeriod: nil,
                    note: nil
                ),
                schoolHolidayStatus: nil,
                localPriceLevel: nil,
                sources: [HolidaySourceAttribution(name: "Nager.Date", url: nil)],
                fetchedAt: .now,
                detail: nil,
                note: nil
            ),
            marine: DashboardSnapshot.preview.marine,
            appState: DashboardSnapshot.preview.appState
        )

        let presentation = LocalInfoSectionPresentation(
            settings: settings,
            snapshot: snapshot,
            locationStatusDetail: nil
        )

        #expect(presentation.rows.first(where: { $0.title == "Public Holiday" })?.value == "Today")
        #expect(presentation.rows.first(where: { $0.title == "Public Holiday" })?.badge?.title == "Busy Today")
    }

    @Test
    func localInfoSectionPresentationShowsBusyPeriodBadgeForActiveSchoolBreak() {
        var settings = AppSettings()
        settings.localInfoEnabled = true

        let snapshot = DashboardSnapshot(
            network: DashboardSnapshot.preview.network,
            power: DashboardSnapshot.preview.power,
            travelContext: DashboardSnapshot.preview.travelContext,
            travelAlerts: DashboardSnapshot.preview.travelAlerts,
            weather: DashboardSnapshot.preview.weather,
            localInfo: LocalInfoSnapshot(
                status: .partial,
                locality: "Berlin",
                administrativeRegion: "Berlin",
                countryCode: "DE",
                countryName: "Germany",
                timeZoneIdentifier: "Europe/Berlin",
                subdivisionCode: "DE-BE",
                publicHolidayStatus: LocalHolidayStatus(
                    state: .upcoming,
                    currentPeriod: nil,
                    nextPeriod: HolidayPeriodSnapshot(
                        name: "Labour Day",
                        startDate: .now.addingTimeInterval(86_400),
                        endDate: .now.addingTimeInterval(86_400)
                    ),
                    note: nil
                ),
                schoolHolidayStatus: LocalHolidayStatus(
                    state: .current,
                    currentPeriod: HolidayPeriodSnapshot(
                        name: "Easter Holidays",
                        startDate: .now.addingTimeInterval(-86_400),
                        endDate: .now.addingTimeInterval(4 * 86_400)
                    ),
                    nextPeriod: nil,
                    note: nil
                ),
                localPriceLevel: nil,
                sources: [HolidaySourceAttribution(name: "OpenHolidays", url: nil)],
                fetchedAt: .now,
                detail: nil,
                note: nil
            ),
            marine: DashboardSnapshot.preview.marine,
            appState: DashboardSnapshot.preview.appState
        )

        let presentation = LocalInfoSectionPresentation(
            settings: settings,
            snapshot: snapshot,
            locationStatusDetail: nil
        )

        #expect(presentation.rows.first(where: { $0.title == "School Break" })?.value == "On Break")
        #expect(presentation.rows.first(where: { $0.title == "School Break" })?.badge?.title == "Busy Period")
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
        #expect(presentation.rows.map(\.ownershipTitle) == [nil, "Public", "Private"])
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

        #expect(presentation.subtitle == "Within 50 km · Emergency 112")
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
        windDirectionDegrees: 315,
        hourlyForecastSlots: [
            WeatherHourlyForecastSlot(
                date: Date().addingTimeInterval(3 * 3_600),
                symbolName: "cloud.sun.fill",
                conditionDescription: "Partly Cloudy",
                temperatureCelsius: 19,
                precipitationChance: 0.1,
                windSpeedKph: 12,
                windDirectionDegrees: 315
            ),
            WeatherHourlyForecastSlot(
                date: Date().addingTimeInterval(6 * 3_600),
                symbolName: "sun.max.fill",
                conditionDescription: "Clear",
                temperatureCelsius: 20,
                precipitationChance: 0.05,
                windSpeedKph: 10,
                windDirectionDegrees: 270
            ),
            WeatherHourlyForecastSlot(
                date: Date().addingTimeInterval(12 * 3_600),
                symbolName: "cloud.fill",
                conditionDescription: "Cloudy",
                temperatureCelsius: 16,
                precipitationChance: 0.22,
                windSpeedKph: 15,
                windDirectionDegrees: 225
            ),
            WeatherHourlyForecastSlot(
                date: Date().addingTimeInterval(24 * 3_600),
                symbolName: "cloud.rain.fill",
                conditionDescription: "Rain",
                temperatureCelsius: 15,
                precipitationChance: 0.48,
                windSpeedKph: 18,
                windDirectionDegrees: 180
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
    dischargeRateWatts: Double? = 11.2,
    adapterWatts: Double? = nil
) -> PowerSnapshot {
    PowerSnapshot(
        chargePercent: 0.72,
        state: state,
        timeRemainingMinutes: timeRemainingMinutes,
        timeToFullChargeMinutes: timeToFullChargeMinutes,
        isLowPowerModeEnabled: false,
        dischargeRateWatts: dischargeRateWatts,
        adapterWatts: adapterWatts,
        collectedAt: .now
    )
}

private func makeState(
    kind: TravelAlertKind,
    status: TravelAlertSignalStatus,
    severity: TravelAlertSeverity,
    summary: String,
    detailSummary: String? = nil,
    sourceName: String? = nil,
    sourceURL: URL? = nil,
    count: Int? = nil,
    updatedAt: Date = .now,
    lastAttemptedAt: Date = .now,
    lastSuccessAt: Date = .now
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
            detailSummary: detailSummary,
            sourceName: sourceName ?? defaultSourceName,
            sourceURL: sourceURL,
            updatedAt: updatedAt,
            affectedCountryCodes: ["ES"],
            itemCount: count
        ),
        reason: nil,
        sourceName: sourceName ?? defaultSourceName,
        sourceURL: sourceURL,
        lastAttemptedAt: lastAttemptedAt,
        lastSuccessAt: lastSuccessAt
    )
}

private func fixedTravelAlertDate(day: Int) -> Date {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = TimeZone(secondsFromGMT: 0)
    components.year = 2_026
    components.month = 4
    components.day = day
    return components.date ?? .now
}
