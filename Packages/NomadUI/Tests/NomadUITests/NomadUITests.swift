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
