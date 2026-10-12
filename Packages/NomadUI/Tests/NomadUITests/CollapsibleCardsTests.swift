import Foundation
@testable import NomadCore
@testable import NomadUI
import Testing

// MARK: Packing and visibility

struct CollapsedPackingTests {
    @Test
    func aCollapsedNarrowCardNeverSharesARow() {
        let rows = DashboardCardPacking.rows(
            order: [.connectivity, .power, .weather],
            widthModes: [.connectivity: .narrow, .power: .narrow, .weather: .narrow],
            collapsed: [.connectivity]
        )

        // Connectivity is a one-line summary, so Power and Weather pair up on their own.
        #expect(rows.map(\.items.count) == [1, 2])
        #expect(rows[0].items[0].cardID == .connectivity)
        #expect(rows[0].items[0].renderWidth == .full)
        #expect(rows[0].items[0].preferredWidthMode == .narrow)
        #expect(rows[1].items.map(\.cardID) == [.power, .weather])
    }

    @Test
    func collapsingOneHalfOfAPairLeavesTheOtherFullWidth() {
        let rows = DashboardCardPacking.rows(
            order: [.connectivity, .power],
            widthModes: [.connectivity: .narrow, .power: .narrow],
            collapsed: [.power]
        )

        #expect(rows.map(\.items.count) == [1, 1])
        #expect(rows.flatMap(\.items).allSatisfy { $0.layoutWidthMode == .wide })
    }
}

struct DashboardCardVisibilityTests {
    private func settings(_ configure: (inout AppSettings) -> Void) -> AppSettings {
        var settings = AppSettings()
        settings.meteredDataEnabled = false
        settings.projectTimeTrackingEnabled = true
        settings.localInfoEnabled = false
        settings.fuelPricesEnabled = false
        settings.emergencyCareEnabled = true
        settings.travelAdvisoryEnabled = true
        configure(&settings)
        return settings
    }

    @Test
    func turnedOffCardsLeaveTheGridAndAreNamedInDashboardOrder() {
        let visibility = DashboardCardVisibility(
            order: DashboardCardID.defaultOrder,
            settings: settings { _ in },
            isCustomizingLayout: false
        )

        #expect(visibility.visibleOrder.contains(.meteredData) == false)
        #expect(visibility.visibleOrder.contains(.localInfo) == false)
        #expect(visibility.visibleOrder.contains(.fuelPrices) == false)
        #expect(visibility.visibleOrder.contains(.connectivity))
        #expect(visibility.visibleOrder.contains(.weather))
        #expect(visibility.turnedOffText == "Turned off: Data Guard, Local Info, Fuel Prices")
    }

    @Test
    func customizingShowsEveryCardAndNoTurnedOffRow() {
        let visibility = DashboardCardVisibility(
            order: DashboardCardID.defaultOrder,
            settings: settings { _ in },
            isCustomizingLayout: true
        )

        #expect(visibility.visibleOrder == DashboardCardID.defaultOrder)
        #expect(visibility.turnedOffText == nil)
    }

    @Test
    func nothingIsTurnedOffWhenEveryFeatureIsOn() {
        let visibility = DashboardCardVisibility(
            order: DashboardCardID.defaultOrder,
            settings: settings {
                $0.meteredDataEnabled = true
                $0.localInfoEnabled = true
                $0.fuelPricesEnabled = true
            },
            isCustomizingLayout: false
        )

        #expect(visibility.visibleOrder == DashboardCardID.defaultOrder)
        #expect(visibility.turnedOffText == nil)
    }
}

// MARK: Collapsed summaries

struct DashboardCardSummaryPresentationTests {
    private var settings: AppSettings {
        var settings = AppSettings()
        settings.meteredDataEnabled = true
        settings.projectTimeTrackingEnabled = true
        settings.localInfoEnabled = true
        settings.fuelPricesEnabled = true
        settings.emergencyCareEnabled = true
        return settings
    }

    private let alerts = TravelAlertPreferences(advisoryEnabled: true, weatherEnabled: true, securityEnabled: true)

    private func summary(
        _ cardID: DashboardCardID,
        snapshot: DashboardSnapshot = .preview,
        timeTracking: TimeTrackingDashboardState = .disabled
    ) -> String {
        DashboardCardSummaryPresentation(
            cardID: cardID,
            snapshot: snapshot,
            settings: settings,
            travelAlertPreferences: alerts,
            timeTracking: timeTracking
        ).text
    }

    @Test
    func connectivityShowsLatencyAndRoundedThroughput() {
        #expect(summary(.connectivity) == "28 ms · 96 ↓ 19 ↑")
    }

    @Test
    func powerShowsChargeAndTimeLeft() {
        #expect(summary(.power) == "72% · 3h 28m")
    }

    @Test
    func travelContextShowsPublicIPAndWiFiNameBecauseTheBadgeSaysVPN() {
        #expect(summary(.travelContext) == "203.0.113.42 · Nomad Hub")
    }

    @Test
    func weatherShowsTemperatureAndCondition() {
        #expect(summary(.weather) == "19° Partly Cloudy")
    }

    @Test
    func travelAlertsSayWhereTheyApplyBecauseTheBadgeHasTheLevel() {
        #expect(summary(.travelAlerts) == "Spain + 4 nearby")

        let off = DashboardCardSummaryPresentation(
            cardID: .travelAlerts,
            snapshot: .preview,
            settings: settings,
            travelAlertPreferences: TravelAlertPreferences(advisoryEnabled: false, weatherEnabled: false, securityEnabled: false),
            timeTracking: .disabled
        )
        #expect(off.text == "Off")
    }

    @Test
    func fuelShowsTheFuelTypePriceAndDistance() {
        let price = FuelPriceFormatting.price(1.429, currencyCode: "EUR")
        #expect(summary(.fuelPrices) == "Diesel \(price) · 4.8 km")
    }

    @Test
    func emergencyLeadsWithTheNumberThenTheNearestDistance() {
        let nearest = DashboardSnapshot.preview.emergencyCare?.hospitals.min { $0.distanceKilometers < $1.distanceKilometers }
        let presentation = DashboardCardSummaryPresentation(
            cardID: .emergencyCare,
            snapshot: .preview,
            settings: settings,
            travelAlertPreferences: alerts,
            timeTracking: .disabled
        )

        #expect(presentation.text == "112 · nearest 2.4 km")
        #expect(presentation.help.contains(nearest?.name ?? "?"))
    }

    @Test
    func emergencyWithoutAKnownNumberNamesTheNearestHospital() {
        let base = DashboardSnapshot.preview
        let unknown = IPLocationSnapshot(
            city: nil, region: nil, country: nil, countryCode: "ZZ", latitude: nil, longitude: nil,
            timeZone: nil, provider: "test", fetchedAt: .now
        )
        let snapshot = DashboardSnapshot(
            network: base.network,
            power: base.power,
            travelContext: TravelContextSnapshot(
                wifi: nil, vpn: nil, timeZoneIdentifier: "UTC", deviceLocation: unknown, publicIP: nil, location: nil
            ),
            weather: nil,
            emergencyCare: base.emergencyCare,
            appState: base.appState
        )

        #expect(summary(.emergencyCare, snapshot: snapshot) == "Nearest 2.4 km · Hospital Casa de Salut")
    }

    @Test
    func localInfoShowsTheNextHolidayDate() throws {
        let start = try #require(DashboardSnapshot.preview.localInfo?.publicHolidayStatus.nextPeriod?.startDate)
        #expect(summary(.localInfo) == "Holiday \(LocalInfoSectionPresentation.formattedDay(start))")
    }

    @Test
    func timeTrackingShowsPendingTimeOrOff() {
        #expect(summary(.timeTracking) == "Off")

        let enabled = TimeTrackingDashboardState(
            isEnabled: true,
            activityState: .running,
            activeProjects: [],
            recentProjects: [],
            todaySummary: TimeTrackingDaySummary(
                dayStart: .now,
                bucketDurations: [],
                totalTrackedDuration: 7 * 3_600,
                totalAllocatedDuration: 0,
                unallocatedDuration: 6 * 3_600 + 58 * 60,
                interruptionCount: 0,
                estimatedFocusLossDuration: 0,
                focusAdjustedDuration: 7 * 3_600,
                lastInterruptionAt: nil
            ),
            openUnallocatedEntryStartAt: nil
        )
        #expect(summary(.timeTracking, timeTracking: enabled) == "Pending 6h 58m")
    }

    @Test
    func dataGuardShowsWhatIsLeft() {
        let metered = makeMetered(used: 4_000_000_000, cap: 5_000_000_000)
        let snapshot = DashboardSnapshot(
            network: DashboardSnapshot.preview.network,
            power: DashboardSnapshot.preview.power,
            travelContext: DashboardSnapshot.preview.travelContext,
            weather: nil,
            appState: DashboardSnapshot.preview.appState,
            meteredData: metered
        )

        #expect(summary(.meteredData, snapshot: snapshot) == "\(MeteredUsageFormatting.byteCount(1_000_000_000)) left")
        #expect(summary(.meteredData) == "Off")
    }
}

// MARK: Data Guard

private func makeMetered(
    used: UInt64,
    cap: UInt64?,
    monitoring: Bool = true,
    known: Bool = false,
    manual: Bool = false,
    period: MeteredBillingPeriod = .session,
    startedAt: Date? = nil
) -> MeteredUsageSnapshot {
    MeteredUsageSnapshot(
        isFeatureEnabled: true,
        isMonitoringActive: monitoring,
        networkKey: "net",
        networkDisplayName: "Hotspot",
        meteredInterfaceName: "en0",
        sessionStartedAt: startedAt,
        sessionBytesReceived: used * 4 / 5,
        sessionBytesSent: used / 5,
        periodStartedAt: startedAt,
        periodBytesReceived: used * 4 / 5,
        periodBytesSent: used / 5,
        capBytes: cap,
        usageFraction: cap.map { Double(used) / Double($0) },
        isCapReached: cap.map { used >= $0 } ?? false,
        billingPeriod: period,
        manualSessionEnabled: manual,
        isKnownMeteredNetwork: known,
        networkNameSource: .liveSSID,
        isWiFiConnected: true,
        needsLocationForWiFiNames: false,
        statusMessage: nil,
        capAlertSignal: nil
    )
}

struct DataGuardCardPresentationTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .now
    }

    @Test
    func leadsWithWhatIsLeftAndTheCapStatus() {
        let presentation = DataGuardCardPresentation(
            snapshot: makeMetered(used: 4_000_000_000, cap: 5_000_000_000),
            now: date(2_026, 10, 12),
            calendar: calendar
        )

        #expect(presentation.leadText == "\(MeteredUsageFormatting.byteCount(1_000_000_000)) left")
        #expect(presentation.level == .caution)
        #expect(presentation.progress == 0.8)
        #expect(presentation.transferCaption == "↓ \(MeteredUsageFormatting.byteCount(3_200_000_000)) · ↑ \(MeteredUsageFormatting.byteCount(800_000_000))")
    }

    @Test
    func captionJoinsCapResetAndPaceAndOmitsUnknownParts() {
        let now = date(2_026, 10, 12)
        let monthly = DataGuardCardPresentation(
            snapshot: makeMetered(
                used: 1_000_000_000,
                cap: 5_000_000_000,
                period: .calendarMonth,
                startedAt: now.addingTimeInterval(-86_400 * 2)
            ),
            now: now,
            calendar: calendar
        )
        let reset = date(2_026, 11, 1, 0).formatted(.dateTime.month(.abbreviated).day())
        // 1 GB in 2 days leaves 4 GB, which lasts 8 days at that pace.
        #expect(monthly.usageCaption == "of \(MeteredUsageFormatting.byteCount(5_000_000_000)) · resets \(reset) · ~8 days at this pace")

        let session = DataGuardCardPresentation(
            snapshot: makeMetered(used: 1_000_000_000, cap: 5_000_000_000),
            now: now,
            calendar: calendar
        )
        #expect(session.usageCaption == "of \(MeteredUsageFormatting.byteCount(5_000_000_000))")
    }

    @Test
    func withoutACapItShowsUsageOnly() {
        let presentation = DataGuardCardPresentation(
            snapshot: makeMetered(used: 3_000_000_000, cap: nil),
            now: .now
        )

        #expect(presentation.leadText == "Used \(MeteredUsageFormatting.byteCount(3_000_000_000))")
        #expect(presentation.progress == nil)
        #expect(presentation.usageCaption == nil)
    }

    @Test
    func reachingTheCapSaysSo() {
        let presentation = DataGuardCardPresentation(
            snapshot: makeMetered(used: 5_500_000_000, cap: 5_000_000_000),
            now: .now
        )

        #expect(presentation.leadText == "Cap reached")
        #expect(presentation.level == .attention)
        #expect(presentation.progress == 1)
    }

    @Test
    func statusLineExplainsWhyMonitoringIsActive() {
        func status(_ monitoring: Bool, known: Bool = false, manual: Bool = false) -> String {
            DataGuardCardPresentation(
                snapshot: makeMetered(used: 0, cap: 1_000, monitoring: monitoring, known: known, manual: manual),
                now: .now
            ).statusText
        }

        #expect(status(false, known: true, manual: true) == "Not monitoring")
        #expect(status(true, known: true) == "Remembered metered network")
        #expect(status(true, manual: true) == "Turned on manually")
        #expect(status(true) == "Monitoring")
    }

    @Test
    func paceReadsAsDaysRoundedAndBounded() {
        #expect(DataGuardCardPresentation.paceText(0.4) == "<1 day at this pace")
        #expect(DataGuardCardPresentation.paceText(1.2) == "~1 day at this pace")
        #expect(DataGuardCardPresentation.paceText(2.4) == "~2 days at this pace")
        #expect(DataGuardCardPresentation.paceText(400) == "100+ days at this pace")
    }
}

// MARK: Emergency numbers

struct EmergencyNumbersPresentationTests {
    @Test
    func headlineNamesTheGeneralNumber() {
        #expect(EmergencyNumbers(general: "110", ambulance: "119", fire: "119").headline == "Emergency 110")
    }

    @Test
    func othersListOnlyWhatDiffers() {
        #expect(EmergencyNumbers(general: "112").othersText == nil)
        #expect(EmergencyNumbers(general: "112", police: "101").othersText == "Police 101")
        #expect(EmergencyNumbers(general: "110", ambulance: "119", fire: "119").othersText == "Ambulance/Fire 119")
        #expect(EmergencyNumbers(general: "112", police: "133", ambulance: "144", fire: "122").othersText == "Police 133 · Ambulance 144 · Fire 122")
    }

    @Test
    func emergencyCareSubtitleCarriesTheCountryNumber() {
        var settings = AppSettings()
        settings.emergencyCareEnabled = true
        let presentation = EmergencyCareSectionPresentation(settings: settings, snapshot: .preview, locationStatusDetail: nil)

        #expect(presentation.subtitle == "Within 25 km · Emergency 112")
        #expect(presentation.emergencyNumbers?.general == "112")
    }

    @Test
    func emergencyCareSubtitleStaysPlainWithoutKnownNumbers() {
        var settings = AppSettings()
        settings.emergencyCareEnabled = true
        let base = DashboardSnapshot.preview
        let unknown = IPLocationSnapshot(
            city: nil, region: nil, country: nil, countryCode: "ZZ", latitude: nil, longitude: nil,
            timeZone: nil, provider: "test", fetchedAt: .now
        )
        let snapshot = DashboardSnapshot(
            network: base.network,
            power: base.power,
            travelContext: TravelContextSnapshot(
                wifi: nil, vpn: nil, timeZoneIdentifier: "UTC", deviceLocation: unknown, publicIP: nil, location: nil
            ),
            weather: nil,
            emergencyCare: base.emergencyCare,
            appState: base.appState
        )
        let presentation = EmergencyCareSectionPresentation(settings: settings, snapshot: snapshot, locationStatusDetail: nil)

        #expect(presentation.subtitle == "Within 25 km")
        #expect(presentation.emergencyNumbers == nil)
    }

    @Test
    func localInfoGetsAnEmergencyRowWithSelectableNumber() throws {
        var settings = AppSettings()
        settings.localInfoEnabled = true
        let presentation = LocalInfoSectionPresentation(settings: settings, snapshot: .preview, locationStatusDetail: nil)
        let row = try #require(presentation.rows.first { $0.id == "emergency-numbers" })

        #expect(row.title == "Emergency")
        #expect(row.value == "112")
        #expect(row.isValueSelectable)
    }
}

// MARK: Fuel and travel alert chips

struct FuelAndAlertPresentationTests {
    @Test
    func fuelRowsUseTheLocaleCurrencyFormatWithASeparateUnit() throws {
        var settings = AppSettings()
        settings.fuelPricesEnabled = true
        let presentation = FuelPricesSectionPresentation(settings: settings, snapshot: .preview, locationStatusDetail: nil)
        let row = try #require(presentation.rows.first)

        #expect(row.priceValue == FuelPriceFormatting.price(1.429, currencyCode: "EUR"))
        #expect(row.priceUnit == "/L")
    }

    private func presentation(severities: [TravelAlertSeverity]) -> TravelAlertsCardPresentation {
        let kinds: [TravelAlertKind] = [.advisory, .weather, .security]
        let used = Array(kinds.prefix(severities.count))
        let states = zip(used, severities).map { kind, severity in
            TravelAlertSignalState(
                kind: kind,
                status: .ready,
                signal: TravelAlertSignalSnapshot(
                    kind: kind,
                    severity: severity,
                    title: kind.rawValue,
                    summary: "Summary",
                    sourceName: "Source",
                    sourceURL: nil,
                    updatedAt: .now,
                    affectedCountryCodes: ["ES"]
                ),
                reason: nil,
                sourceName: "Source",
                sourceURL: nil,
                lastAttemptedAt: .now,
                lastSuccessAt: .now
            )
        }

        return TravelAlertsCardPresentation(
            preferences: TravelAlertPreferences(
                advisoryEnabled: used.contains(.advisory),
                weatherEnabled: used.contains(.weather),
                securityEnabled: used.contains(.security)
            ),
            snapshot: TravelAlertsSnapshot(
                enabledKinds: used,
                primaryCountryCode: "ES",
                primaryCountryName: "Spain",
                coverageCountryCodes: ["ES"],
                states: states,
                fetchedAt: .now
            )
        )
    }

    @Test
    func aSingleReadySignalDoesNotRepeatTheHeaderLevel() {
        #expect(presentation(severities: [.caution]).showsSignalChips == false)
    }

    @Test
    func severalSignalsKeepTheirOwnChips() {
        #expect(presentation(severities: [.caution, .clear]).showsSignalChips)
    }
}
