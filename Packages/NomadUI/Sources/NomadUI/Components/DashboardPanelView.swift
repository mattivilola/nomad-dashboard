import AppKit
import NomadCore
import SwiftUI

public struct DashboardPanelView: View {
    private let snapshot: DashboardSnapshot
    private let overviewContent: AnyView?
    private let sectionActivity: [DashboardDataSection: DashboardSectionActivity]
    private let resourcePolicy: DashboardResourcePolicy
    private let retrySection: (DashboardDataSection) -> Void
    private let refreshActivity: DashboardRefreshActivity
    private let settings: AppSettings
    private let dashboardCardOrder: [DashboardCardID]
    private let dashboardCardWidthModes: [DashboardCardID: DashboardCardWidthMode]
    private let dashboardCollapsedCards: Set<DashboardCardID>
    private let travelProfile: TravelProfile
    private let isPublicIPLocationEnabled: Bool
    private let travelAlertPreferences: TravelAlertPreferences
    private let visitedCountryDays: [VisitedCountryDay]
    private let versionDescription: String
    private let buildFlavorBadgeTitle: String?
    private let weatherAvailabilityExplanation: String?
    private let locationStatusDetail: String?
    private let appIcon: NSImage?
    private let timeTrackingDashboardState: TimeTrackingDashboardState
    private let refreshAction: () -> Void
    private let toggleAppearanceAction: () -> Void
    private let playTimeTrackingAction: () -> Void
    private let pauseTimeTrackingAction: () -> Void
    private let resumeTimeTrackingAction: () -> Void
    private let stopTimeTrackingAction: () -> Void
    private let reportTimeTrackingInterruptionAction: () -> Void
    private let allocateTimeTrackingAction: (TimeTrackingBucket) -> Void
    private let openTimeTrackingAction: () -> Void
    private let openTripPlannerAction: () -> Void
    private let keepAwakeSession: KeepAwakeSession?
    private let keepAwakeKeepsDisplayOn: Bool
    private let startKeepAwakeAction: (KeepAwakeDuration) -> Void
    private let stopKeepAwakeAction: () -> Void
    private let setKeepAwakeKeepsDisplayOnAction: (Bool) -> Void
    private let keepAwakeWhileLidClosed: Bool
    private let keepAwakeLidClosedState: KeepAwakeLidClosedState
    private let keepAwakeEndReason: String?
    private let keepAwakeErrorMessage: String?
    private let setKeepAwakeWhileLidClosedAction: (Bool) -> Void
    private let allowKeepAwakeLidClosedAction: () -> Void
    private let copyIPAddressAction: () -> Void
    private let openVisitedMapAction: () -> Void
    private let showArrivalBriefingAction: (() -> Void)?
    private let openNetworkSettingsAction: () -> Void
    private let openFuelStationMapPreviewAction: (FuelStationMapDestination) -> Void
    private let openFuelStationInGoogleMapsAction: (FuelStationMapDestination) -> Void
    private let openEmergencyHospitalMapPreviewAction: (EmergencyHospitalMapDestination) -> Void
    private let openEmergencyHospitalInGoogleMapsAction: (EmergencyHospitalMapDestination) -> Void
    private let openTravelAlertSourceAction: (URL) -> Void
    private let openExternalURLAction: (URL) -> Void
    private let copyTextAction: (String) -> Void
    private let checkForUpdatesAction: (() -> Void)?
    private let openSettingsAction: () -> Void
    private let openSettingsForCard: (DashboardCardID) -> Void
    private let openSurfSpotSettingsAction: () -> Void
    private let openAboutAction: () -> Void
    private let quitAction: () -> Void
    private let onCardOrderChange: ([DashboardCardID]) -> Void
    private let onCardWidthModesChange: ([DashboardCardID: DashboardCardWidthMode]) -> Void
    private let onCollapsedCardsChange: (Set<DashboardCardID>) -> Void
    private let onTravelProfileChange: (TravelProfile) -> Void
    private let onWeatherForecastExpandedChange: (Bool) -> Void
    private let setManualMeteredSessionEnabled: (Bool) -> Void
    private let markCurrentNetworkAsMetered: () -> Void
    private let forgetCurrentMeteredNetwork: () -> Void
    private let resetMeteredUsagePeriod: () -> Void
    private let requestLocationForWiFiNamesAction: () -> Void
    private let wifiSSIDLocationButtonTitle: String

    @Environment(\.colorScheme) private var colorScheme
    @State private var resolvedCardOrder: [DashboardCardID]
    @State private var resolvedCardWidthModes: [DashboardCardID: DashboardCardWidthMode]
    @State private var resolvedCollapsedCards: Set<DashboardCardID>
    @State private var activeDropCardID: DashboardCardID?
    @State private var isCustomizingLayout = false

    public init(
        snapshot: DashboardSnapshot,
        overviewContent: AnyView? = nil,
        sectionActivity: [DashboardDataSection: DashboardSectionActivity] = [:],
        resourcePolicy: DashboardResourcePolicy = .normal,
        retrySection: @escaping (DashboardDataSection) -> Void = { _ in },
        refreshActivity: DashboardRefreshActivity,
        settings: AppSettings,
        dashboardCardOrder: [DashboardCardID],
        dashboardCardWidthModes: [DashboardCardID: DashboardCardWidthMode],
        dashboardCollapsedCards: Set<DashboardCardID> = [],
        travelProfile: TravelProfile = .nomad,
        isPublicIPLocationEnabled: Bool,
        travelAlertPreferences: TravelAlertPreferences,
        visitedCountryDays: [VisitedCountryDay] = [],
        versionDescription: String = "",
        buildFlavorBadgeTitle: String? = nil,
        weatherAvailabilityExplanation: String? = nil,
        locationStatusDetail: String? = nil,
        appIcon: NSImage? = nil,
        timeTrackingDashboardState: TimeTrackingDashboardState = .disabled,
        refreshAction: @escaping () -> Void,
        toggleAppearanceAction: @escaping () -> Void,
        playTimeTrackingAction: @escaping () -> Void = {},
        pauseTimeTrackingAction: @escaping () -> Void = {},
        resumeTimeTrackingAction: @escaping () -> Void = {},
        stopTimeTrackingAction: @escaping () -> Void = {},
        reportTimeTrackingInterruptionAction: @escaping () -> Void = {},
        allocateTimeTrackingAction: @escaping (TimeTrackingBucket) -> Void = { _ in },
        openTimeTrackingAction: @escaping () -> Void = {},
        openTripPlannerAction: @escaping () -> Void = {},
        keepAwakeSession: KeepAwakeSession? = nil,
        keepAwakeKeepsDisplayOn: Bool = true,
        startKeepAwakeAction: @escaping (KeepAwakeDuration) -> Void = { _ in },
        stopKeepAwakeAction: @escaping () -> Void = {},
        setKeepAwakeKeepsDisplayOnAction: @escaping (Bool) -> Void = { _ in },
        keepAwakeWhileLidClosed: Bool = true,
        keepAwakeLidClosedState: KeepAwakeLidClosedState = .off,
        keepAwakeEndReason: String? = nil,
        keepAwakeErrorMessage: String? = nil,
        setKeepAwakeWhileLidClosedAction: @escaping (Bool) -> Void = { _ in },
        allowKeepAwakeLidClosedAction: @escaping () -> Void = {},
        copyIPAddressAction: @escaping () -> Void,
        openVisitedMapAction: @escaping () -> Void,
        showArrivalBriefingAction: (() -> Void)? = nil,
        openNetworkSettingsAction: @escaping () -> Void,
        openFuelStationMapPreviewAction: @escaping (FuelStationMapDestination) -> Void = { _ in },
        openFuelStationInGoogleMapsAction: @escaping (FuelStationMapDestination) -> Void = { _ in },
        openEmergencyHospitalMapPreviewAction: @escaping (EmergencyHospitalMapDestination) -> Void = { _ in },
        openEmergencyHospitalInGoogleMapsAction: @escaping (EmergencyHospitalMapDestination) -> Void = { _ in },
        openTravelAlertSourceAction: @escaping (URL) -> Void = { _ in },
        openExternalURLAction: @escaping (URL) -> Void = { _ in },
        copyTextAction: @escaping (String) -> Void = { _ in },
        checkForUpdatesAction: (() -> Void)? = nil,
        openSettingsAction: @escaping () -> Void,
        openSettingsForCard: @escaping (DashboardCardID) -> Void = { _ in },
        openSurfSpotSettingsAction: @escaping () -> Void,
        openAboutAction: @escaping () -> Void,
        quitAction: @escaping () -> Void,
        onCardOrderChange: @escaping ([DashboardCardID]) -> Void = { _ in },
        onCardWidthModesChange: @escaping ([DashboardCardID: DashboardCardWidthMode]) -> Void = { _ in },
        onCollapsedCardsChange: @escaping (Set<DashboardCardID>) -> Void = { _ in },
        onTravelProfileChange: @escaping (TravelProfile) -> Void = { _ in },
        onWeatherForecastExpandedChange: @escaping (Bool) -> Void = { _ in },
        setManualMeteredSessionEnabled: @escaping (Bool) -> Void = { _ in },
        markCurrentNetworkAsMetered: @escaping () -> Void = {},
        forgetCurrentMeteredNetwork: @escaping () -> Void = {},
        resetMeteredUsagePeriod: @escaping () -> Void = {},
        requestLocationForWiFiNamesAction: @escaping () -> Void = {},
        wifiSSIDLocationButtonTitle: String = "Allow location for Wi‑Fi names…"
    ) {
        self.snapshot = snapshot
        self.overviewContent = overviewContent
        self.sectionActivity = sectionActivity
        self.resourcePolicy = resourcePolicy
        self.retrySection = retrySection
        self.refreshActivity = refreshActivity
        self.settings = settings
        self.dashboardCardOrder = DashboardCardID.sanitizedOrder(dashboardCardOrder)
        self.dashboardCardWidthModes = DashboardCardID.sanitizedWidthModes(dashboardCardWidthModes)
        self.dashboardCollapsedCards = dashboardCollapsedCards
        self.travelProfile = travelProfile
        self.isPublicIPLocationEnabled = isPublicIPLocationEnabled
        self.travelAlertPreferences = travelAlertPreferences
        self.visitedCountryDays = visitedCountryDays
        self.versionDescription = versionDescription
        self.buildFlavorBadgeTitle = buildFlavorBadgeTitle
        self.weatherAvailabilityExplanation = weatherAvailabilityExplanation
        self.locationStatusDetail = locationStatusDetail
        self.appIcon = appIcon
        self.timeTrackingDashboardState = timeTrackingDashboardState
        self.refreshAction = refreshAction
        self.toggleAppearanceAction = toggleAppearanceAction
        self.playTimeTrackingAction = playTimeTrackingAction
        self.pauseTimeTrackingAction = pauseTimeTrackingAction
        self.resumeTimeTrackingAction = resumeTimeTrackingAction
        self.stopTimeTrackingAction = stopTimeTrackingAction
        self.reportTimeTrackingInterruptionAction = reportTimeTrackingInterruptionAction
        self.allocateTimeTrackingAction = allocateTimeTrackingAction
        self.openTimeTrackingAction = openTimeTrackingAction
        self.openTripPlannerAction = openTripPlannerAction
        self.keepAwakeSession = keepAwakeSession
        self.keepAwakeKeepsDisplayOn = keepAwakeKeepsDisplayOn
        self.startKeepAwakeAction = startKeepAwakeAction
        self.stopKeepAwakeAction = stopKeepAwakeAction
        self.setKeepAwakeKeepsDisplayOnAction = setKeepAwakeKeepsDisplayOnAction
        self.keepAwakeWhileLidClosed = keepAwakeWhileLidClosed
        self.keepAwakeLidClosedState = keepAwakeLidClosedState
        self.keepAwakeEndReason = keepAwakeEndReason
        self.keepAwakeErrorMessage = keepAwakeErrorMessage
        self.setKeepAwakeWhileLidClosedAction = setKeepAwakeWhileLidClosedAction
        self.allowKeepAwakeLidClosedAction = allowKeepAwakeLidClosedAction
        self.copyIPAddressAction = copyIPAddressAction
        self.openVisitedMapAction = openVisitedMapAction
        self.showArrivalBriefingAction = showArrivalBriefingAction
        self.openNetworkSettingsAction = openNetworkSettingsAction
        self.openFuelStationMapPreviewAction = openFuelStationMapPreviewAction
        self.openFuelStationInGoogleMapsAction = openFuelStationInGoogleMapsAction
        self.openEmergencyHospitalMapPreviewAction = openEmergencyHospitalMapPreviewAction
        self.openEmergencyHospitalInGoogleMapsAction = openEmergencyHospitalInGoogleMapsAction
        self.openTravelAlertSourceAction = openTravelAlertSourceAction
        self.openExternalURLAction = openExternalURLAction
        self.copyTextAction = copyTextAction
        self.checkForUpdatesAction = checkForUpdatesAction
        self.openSettingsAction = openSettingsAction
        self.openSettingsForCard = openSettingsForCard
        self.openSurfSpotSettingsAction = openSurfSpotSettingsAction
        self.openAboutAction = openAboutAction
        self.quitAction = quitAction
        self.onCardOrderChange = onCardOrderChange
        self.onCardWidthModesChange = onCardWidthModesChange
        self.onCollapsedCardsChange = onCollapsedCardsChange
        self.onTravelProfileChange = onTravelProfileChange
        self.onWeatherForecastExpandedChange = onWeatherForecastExpandedChange
        self.setManualMeteredSessionEnabled = setManualMeteredSessionEnabled
        self.markCurrentNetworkAsMetered = markCurrentNetworkAsMetered
        self.forgetCurrentMeteredNetwork = forgetCurrentMeteredNetwork
        self.resetMeteredUsagePeriod = resetMeteredUsagePeriod
        self.requestLocationForWiFiNamesAction = requestLocationForWiFiNamesAction
        self.wifiSSIDLocationButtonTitle = wifiSSIDLocationButtonTitle
        _resolvedCardOrder = State(initialValue: DashboardCardID.sanitizedOrder(dashboardCardOrder))
        _resolvedCardWidthModes = State(initialValue: DashboardCardID.sanitizedWidthModes(dashboardCardWidthModes))
        _resolvedCollapsedCards = State(initialValue: dashboardCollapsedCards)
    }

    public var body: some View {
        GeometryReader { viewport in
            let contentWidth = max(viewport.size.width - 36, 0)

            ZStack {
                NomadTheme.background.ignoresSafeArea()

                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            header
                            if let overviewContent {
                                overviewContent
                            } else {
                                summaryStrip
                            }
                            orderedCardSections(viewportHeight: viewport.size.height)
                            footer
                        }
                        .frame(width: contentWidth, alignment: .topLeading)
                        .padding(18)
                        .environment(
                            \.dashboardScrollToCard,
                            DashboardScrollToCardAction { cardID in
                                // A collapsed target opens first so the scroll lands on its content.
                                let wasCollapsed = resolvedCollapsedCards.contains(cardID)
                                if wasCollapsed {
                                    setCollapsed(false, for: cardID)
                                }

                                DispatchQueue.main.async {
                                    withAnimation(.snappy) {
                                        scrollProxy.scrollTo(cardID, anchor: .top)
                                    }
                                }
                            }
                        )
                    }
                    .coordinateSpace(name: DashboardScrollCoordinateSpace.name)
                }
            }
        }
        .frame(width: 430, height: 640)
        .environment(\.nomadLowImpact, resourcePolicy.reducesBackgroundWork)
        .onChange(of: dashboardCardOrder) { _, newValue in
            let sanitizedOrder = DashboardCardID.sanitizedOrder(newValue)
            guard resolvedCardOrder != sanitizedOrder else {
                return
            }

            resolvedCardOrder = sanitizedOrder
        }
        .onChange(of: dashboardCollapsedCards) { _, newValue in
            guard resolvedCollapsedCards != newValue else {
                return
            }

            resolvedCollapsedCards = newValue
        }
        .onChange(of: dashboardCardWidthModes) { _, newValue in
            let sanitizedWidthModes = DashboardCardID.sanitizedWidthModes(newValue)
            guard resolvedCardWidthModes != sanitizedWidthModes else {
                return
            }

            resolvedCardWidthModes = sanitizedWidthModes
        }
    }

    private var header: some View {
        let refreshHeader = DashboardRefreshHeaderPresentation(
            lastRefresh: snapshot.appState.lastRefresh,
            refreshActivity: refreshActivity
        )
        let location = DashboardHeaderPresentation(
            deviceLocation: snapshot.travelContext.deviceLocation,
            ipLocation: snapshot.travelContext.location
        )

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(location.headline)
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundStyle(NomadTheme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .layoutPriority(1)

                        if let buildFlavorBadgeTitle {
                            BadgeView(
                                badge: PillBadge(
                                    title: buildFlavorBadgeTitle,
                                    symbolName: "hammer.fill",
                                    tint: NomadTheme.sand
                                )
                            )
                        }
                    }

                    headerLocationDetail(location)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 8) {
                        keepAwakeMenu

                        HeaderIconButton(
                            systemImage: "arrow.clockwise",
                            title: refreshHeader.buttonTitle,
                            isEnabled: refreshHeader.isButtonEnabled,
                            activity: refreshActivity,
                            action: refreshAction
                        )

                        headerMenu
                    }

                    Text(refreshHeader.statusText)
                        .font(.caption)
                        .foregroundStyle(refreshStatusTint)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }

            if let keepAwakeSession {
                KeepAwakeHeaderPillView(
                    session: keepAwakeSession,
                    lidClosedState: keepAwakeLidClosedState,
                    allowLidClosedAction: allowKeepAwakeLidClosedAction,
                    stopAction: stopKeepAwakeAction
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if timeTrackingDashboardState.isEnabled {
                timeTrackingHeaderPill
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var keepAwakeMenu: some View {
        let isKeepingAwake = keepAwakeSession != nil

        return Menu {
            if let keepAwakeNotice = KeepAwakeLidClosedPresentation.menuNotice(
                endReason: keepAwakeEndReason,
                errorMessage: keepAwakeErrorMessage
            ) {
                Text(keepAwakeNotice)
                    .disabled(true)

                Divider()
            }

            if isKeepingAwake {
                Button("Stop Keeping Awake", systemImage: "stop.fill") {
                    stopKeepAwakeAction()
                }

                Divider()
            }

            Section("Keep Mac Awake") {
                ForEach(KeepAwakeDuration.allCases) { duration in
                    Button(duration.title) {
                        startKeepAwakeAction(duration)
                    }
                }
            }

            Divider()

            Toggle(
                "Keep Display On",
                isOn: Binding(
                    get: { keepAwakeKeepsDisplayOn },
                    set: { setKeepAwakeKeepsDisplayOnAction($0) }
                )
            )

            Toggle(
                "Keep Awake With Lid Closed",
                isOn: Binding(
                    get: { keepAwakeWhileLidClosed },
                    set: { setKeepAwakeWhileLidClosedAction($0) }
                )
            )
        } label: {
            HeaderActionIcon(
                systemImage: isKeepingAwake ? "cup.and.heat.waves.fill" : "cup.and.heat.waves",
                tint: isKeepingAwake ? NomadTheme.teal : nil
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Keep Awake")
        .accessibilityLabel("Keep Awake")
    }

    private var travelProfileSelection: Binding<TravelProfile> {
        Binding(get: { travelProfile }, set: { onTravelProfileChange($0) })
    }

    private var headerMenu: some View {
        Menu {
            Button("Open Visited Map", systemImage: "globe.europe.africa.fill") {
                openVisitedMapAction()
            }

            if let showArrivalBriefingAction {
                Button("Show Arrival Briefing", systemImage: "airplane.arrival") {
                    showArrivalBriefingAction()
                }
                .disabled(snapshot.currentCountryCode == nil)
            }

            Button("Open Time Tracking", systemImage: "clock.badge.checkmark") {
                openTimeTrackingAction()
            }

            Button("Trip Planner", systemImage: "airplane.departure") {
                openTripPlannerAction()
            }

            Button("Open Network Settings", systemImage: "gearshape.2") {
                openNetworkSettingsAction()
            }

            Divider()

            Button(
                isCustomizingLayout ? "Done Customizing" : "Customize Layout",
                systemImage: isCustomizingLayout ? "checkmark.circle" : "rectangle.3.group"
            ) {
                isCustomizingLayout.toggle()
            }

            Button(appearanceToggleTitle, systemImage: appearanceToggleSystemImage) {
                toggleAppearanceAction()
            }

            Menu("Travel Profile", systemImage: "suitcase") {
                Picker("Travel Profile", selection: travelProfileSelection) {
                    ForEach(TravelProfile.allCases, id: \.self) { profile in
                        Text(profile.title).tag(profile)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Divider()

            Button("Settings", systemImage: "slider.horizontal.3") {
                openSettingsAction()
            }

            if let checkForUpdatesAction {
                Button("Check for Updates", systemImage: "sparkles") {
                    checkForUpdatesAction()
                }
            }

            Button("About Nomad Dashboard", systemImage: "info.circle") {
                openAboutAction()
            }

            Divider()

            Button("Quit Nomad Dashboard", systemImage: "power") {
                quitAction()
            }
        } label: {
            HeaderActionIcon(systemImage: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    /// Second header line: device region and country, then the IP location, so a
    /// VPN or a stale geo-IP result is visible next to where the Mac actually is.
    /// Shorter variants take over when the full line would not fit, so the IP part
    /// is never the one that gets cut off.
    @ViewBuilder
    private func headerLocationDetail(_ location: DashboardHeaderPresentation) -> some View {
        if let last = location.detailVariants.last {
            let variants = location.detailVariants
            ViewThatFits(in: .horizontal) {
                headerLocationLine(variants[0]).fixedSize(horizontal: true, vertical: false)
                headerLocationLine(variants[min(1, variants.count - 1)]).fixedSize(horizontal: true, vertical: false)
                headerLocationLine(last)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.85)
            }
        }
    }

    private func headerLocationLine(_ variant: DashboardHeaderPresentation.DetailVariant) -> some View {
        let device = variant.device.map {
            Text("\(Text(Image(systemName: "location.fill")).foregroundStyle(NomadTheme.tertiaryText)) \($0)")
        }
        let ip = variant.ip.map {
            Text("\(Text(Image(systemName: "globe")).foregroundStyle(NomadTheme.tertiaryText)) IP \($0)")
        }
        let line: Text = switch (device, ip) {
        case let (device?, ip?): Text("\(device)  ·  \(ip)")
        case let (device?, nil): device
        case let (nil, ip?): ip
        case (nil, nil): Text("")
        }

        return line
            .font(.caption)
            .foregroundStyle(NomadTheme.secondaryText)
    }

    private var summaryStrip: some View {
        HStack(spacing: 10) {
            SummaryTile(presentation: alertsSummaryTilePresentation)
            SummaryTile(presentation: networkSummaryTilePresentation)
            SummaryTile(presentation: powerSummaryTilePresentation)
        }
    }

    private func orderedCardSections(viewportHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if isCustomizingLayout {
                customizeLayoutStrip
            }

            ForEach(packedCardRows) { row in
                if row.items.count == 2 {
                    // Top-aligned: each half keeps its natural height instead of stretching to its neighbour.
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(row.items) { item in
                            dashboardCardItem(item, viewportHeight: viewportHeight)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                } else if let item = row.items.first {
                    dashboardCardItem(item, viewportHeight: viewportHeight)
                }
            }

            if let turnedOffText = cardVisibility.turnedOffText {
                turnedOffRow(turnedOffText, firstTurnedOffCard: cardVisibility.turnedOffCards.first)
            }
        }
    }

    private var cardVisibility: DashboardCardVisibility {
        DashboardCardVisibility(
            order: DashboardCardID.sanitizedOrder(resolvedCardOrder),
            settings: settings,
            isCustomizingLayout: isCustomizingLayout
        )
    }

    /// One compact line naming the cards whose feature is off, with a way to turn them on.
    private func turnedOffRow(_ text: String, firstTurnedOffCard: DashboardCardID?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "switch.2")
                .font(.caption.weight(.semibold))
                .foregroundStyle(NomadTheme.tertiaryText)
                .accessibilityHidden(true)

            Text(text)
                .font(.caption)
                .foregroundStyle(NomadTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button("Settings") {
                if let firstTurnedOffCard {
                    openSettingsForCard(firstTurnedOffCard)
                } else {
                    openSettingsAction()
                }
            }
            .buttonStyle(.dashboardInline(isCompact: true))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(NomadTheme.tileBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(NomadTheme.cardBorder, lineWidth: 1)
                )
        )
    }

    private var customizeLayoutStrip: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.3.group")
                .font(.caption.weight(.semibold))
                .foregroundStyle(NomadTheme.teal)
                .accessibilityHidden(true)

            Text("Drag cards to reorder or change their width")
                .font(.caption)
                .foregroundStyle(NomadTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button("Done") {
                isCustomizingLayout = false
            }
            .buttonStyle(.dashboardInline(isCompact: true))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(NomadTheme.teal.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(NomadTheme.teal.opacity(0.18))
                )
        )
    }

    private var packedCardRows: [DashboardCardRow] {
        DashboardCardPacking.rows(
            order: cardVisibility.visibleOrder,
            widthModes: DashboardCardID.sanitizedWidthModes(resolvedCardWidthModes),
            collapsed: resolvedCollapsedCards
        )
    }

    private func dashboardCardItem(_ item: DashboardCardRowItem, viewportHeight: CGFloat) -> some View {
        interactiveCard(
            cardID: item.cardID,
            renderWidth: item.renderWidth
        ) {
            VStack(alignment: .leading, spacing: 5) {
                dashboardCard(for: item.cardID, widthMode: item.layoutWidthMode, viewportHeight: viewportHeight)
                if resolvedCollapsedCards.contains(item.cardID) == false {
                    ForEach(dataSections(for: item.cardID), id: \.self) { section in
                        if let state = sectionActivity[section] {
                            DashboardCardRefreshFooter(section: section, state: state, isOffline: resourcePolicy.isOffline) { retrySection(section) }
                        }
                    }
                }
            }
        }
        .id(item.cardID)
    }

    /// The data sections whose refresh state a card shows as footer rows, in display order.
    private func dataSections(for card: DashboardCardID) -> [DashboardDataSection] {
        switch card {
        case .travelContext: [.publicIP]
        case .localInfo: [.localInfo]
        case .fuelPrices: [.fuel]
        case .emergencyCare: [.emergencyCare]
        case .travelAlerts: [.travelAlerts]
        // Air quality is fetched separately from the weather, so it has its own footer row.
        case .weather: settings.isAirQualityActive ? [.weather, .airQuality] : [.weather]
        default: []
        }
    }

    @ViewBuilder
    private func dashboardCard(
        for cardID: DashboardCardID,
        widthMode: DashboardCardWidthMode,
        viewportHeight: CGFloat
    ) -> some View {
        switch cardID {
        case .connectivity:
            connectivitySection(widthMode: widthMode)
        case .meteredData:
            meteredDataSection(widthMode: widthMode)
        case .power:
            powerSection(widthMode: widthMode)
        case .timeTracking:
            timeTrackingSection(widthMode: widthMode)
        case .travelContext:
            travelSection(widthMode: widthMode)
        case .stays:
            staysSection(widthMode: widthMode)
        case .localInfo:
            localInfoSection(widthMode: widthMode)
        case .fuelPrices:
            fuelPricesSection(widthMode: widthMode, viewportHeight: viewportHeight)
        case .emergencyCare:
            emergencyCareSection(widthMode: widthMode)
        case .embassy:
            embassySection(widthMode: widthMode)
        case .travelAlerts:
            travelAlertsSection(widthMode: widthMode)
        case .weather:
            weatherSection(widthMode: widthMode)
        }
    }

    private func interactiveCard(
        cardID: DashboardCardID,
        renderWidth: DashboardCardRenderWidth,
        @ViewBuilder content: @escaping () -> some View
    ) -> some View {
        DashboardCardDropTarget(
            isHighlighted: activeDropCardID == cardID,
            content: content
        ) { items, location, size in
            applyDrop(
                items: items,
                onto: cardID,
                location: location,
                size: size,
                renderWidth: renderWidth
            )
        } isTargeted: { isTargeted in
            if isTargeted {
                activeDropCardID = cardID
            } else if activeDropCardID == cardID {
                activeDropCardID = nil
            }
        }
    }

    @discardableResult
    private func applyDrop(
        items: [String],
        onto targetCardID: DashboardCardID,
        location: CGPoint,
        size: CGSize,
        renderWidth: DashboardCardRenderWidth
    ) -> Bool {
        activeDropCardID = nil

        guard let rawValue = items.first,
              let draggedCardID = DashboardCardID(rawValue: rawValue),
              let targetIndex = resolvedCardOrder.firstIndex(of: targetCardID)
        else {
            return false
        }

        let insertAfter: Bool = switch renderWidth {
        case .full:
            location.y >= size.height / 2
        case .half:
            location.x >= size.width / 2
        }

        let insertionIndex = insertAfter ? targetIndex + 1 : targetIndex
        return moveCard(draggedCardID, toOriginalInsertionIndex: insertionIndex)
    }

    @discardableResult
    private func moveCard(_ cardID: DashboardCardID, toOriginalInsertionIndex insertionIndex: Int) -> Bool {
        let currentOrder = DashboardCardID.sanitizedOrder(resolvedCardOrder)
        let reordered = reorderedCardIDs(from: currentOrder, moving: cardID, to: insertionIndex)

        guard reordered != currentOrder else {
            return false
        }

        resolvedCardOrder = reordered
        onCardOrderChange(reordered)
        return true
    }

    private func reorderedCardIDs(from order: [DashboardCardID], moving cardID: DashboardCardID, to insertionIndex: Int) -> [DashboardCardID] {
        guard let currentIndex = order.firstIndex(of: cardID) else {
            return order
        }

        var reordered = order
        reordered.remove(at: currentIndex)
        let adjustedIndex = insertionIndex > currentIndex ? insertionIndex - 1 : insertionIndex
        let clampedIndex = min(max(adjustedIndex, 0), reordered.count)
        reordered.insert(cardID, at: clampedIndex)
        return DashboardCardID.sanitizedOrder(reordered)
    }

    private func meteredDataSection(widthMode: DashboardCardWidthMode) -> some View {
        let metered = snapshot.meteredData
        let isCompact = widthMode == .narrow
        let presentation = DataGuardCardPresentation(snapshot: metered, now: .now)

        let networkSubtitle: String = {
            guard let name = metered.networkDisplayName else { return "No network" }
            if metered.networkNameSource == .cachedSSID {
                return "\(name) (last known)"
            }
            return name
        }()

        return DashboardCard(
            title: DashboardCardID.meteredData.displayTitle,
            subtitle: networkSubtitle,
            badge: metered.isMonitoringActive
                ? PillBadge(
                    title: metered.isCapReached ? "Cap reached" : "Monitoring",
                    symbolName: metered.isCapReached ? "exclamationmark.triangle.fill" : "arrow.up.arrow.down.circle.fill",
                    tint: metered.isCapReached ? NomadTheme.coral : NomadTheme.teal
                )
                : nil,
            accessory: cardControls(for: .meteredData),
            collapse: collapse(for: .meteredData),
            isCompact: isCompact
        ) {
            if !metered.isFeatureEnabled {
                Text("Turn on Data Guard in Settings to track capped hotspot usage.")
                    .font(.caption)
                    .foregroundStyle(NomadTheme.secondaryText)
                Button("Open Settings") { openSettingsForCard(.meteredData) }
                    .buttonStyle(.dashboardInline)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(presentation.leadText)
                        .font(.system(size: isCompact ? 20 : 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(presentation.level.tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    if let progress = presentation.progress {
                        UsageProgressBar(progress: progress, tint: presentation.level.tint, height: 6)
                    }

                    if let usageCaption = presentation.usageCaption {
                        Text(usageCaption)
                            .font(isCompact ? .caption2 : .caption)
                            .foregroundStyle(NomadTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(presentation.transferCaption)
                        .font(isCompact ? .caption2 : .caption)
                        .foregroundStyle(NomadTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if let statusMessage = metered.statusMessage {
                        Text(statusMessage)
                            .font(.caption2)
                            .foregroundStyle(metered.isCapReached ? NomadTheme.coral : NomadTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if metered.needsLocationForWiFiNames {
                        Button(wifiSSIDLocationButtonTitle) {
                            requestLocationForWiFiNamesAction()
                        }
                        .buttonStyle(.dashboardInline(isCompact: isCompact))
                    }

                    HStack(alignment: .center, spacing: 8) {
                        Text(presentation.statusText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NomadTheme.tertiaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .help(ifPresent: presentation.statusHelp)

                        Spacer(minLength: 4)

                        meteredActionsMenu(metered)
                    }

                    Toggle("Monitor manually", isOn: Binding(
                        get: { metered.manualSessionEnabled },
                        set: { setManualMeteredSessionEnabled($0) }
                    ))
                    .font(.caption)
                }
            }
        }
    }

    private func meteredActionsMenu(_ metered: MeteredUsageSnapshot) -> some View {
        Menu {
            Button("Remember as metered", systemImage: "bookmark") { markCurrentNetworkAsMetered() }
                .disabled(metered.networkKey == nil)

            if metered.isKnownMeteredNetwork {
                Button("Forget network", systemImage: "bookmark.slash") { forgetCurrentMeteredNetwork() }
            }

            Button("Reset counters", systemImage: "arrow.counterclockwise") { resetMeteredUsagePeriod() }
        } label: {
            DashboardIconChip(systemImage: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Data Guard actions")
        .accessibilityLabel("Data Guard actions")
    }

    private func connectivitySection(widthMode: DashboardCardWidthMode) -> some View {
        let isCompact = widthMode == .narrow
        let typography: MetricBlock.Typography = isCompact ? .compact : .standard
        let networkTint = snapshot.healthSummary.network.level.tint

        let download = TrendMetric(
            title: "Down",
            reading: metricReading(snapshot.network.throughput?.downloadMegabitsPerSecond, formatter: NomadFormatters.megabitsPerSecondParts),
            typography: typography,
            points: snapshot.network.downloadHistory,
            trendTint: NomadTheme.secondaryText,
            trendTitle: "Download",
            trendFormat: { NomadFormatters.megabitsPerSecond($0) }
        )
        let upload = TrendMetric(
            title: "Up",
            reading: metricReading(snapshot.network.throughput?.uploadMegabitsPerSecond, formatter: NomadFormatters.megabitsPerSecondParts),
            typography: typography,
            points: snapshot.network.uploadHistory,
            trendTint: NomadTheme.secondaryText,
            trendTitle: "Upload",
            trendFormat: { NomadFormatters.megabitsPerSecond($0) }
        )
        let latency = TrendMetric(
            title: "Latency",
            reading: metricReading(snapshot.network.latency?.milliseconds, formatter: NomadFormatters.latencyParts, fallback: "Waiting"),
            typography: typography,
            tone: networkTint,
            points: snapshot.network.latencyHistory,
            trendTint: networkTint,
            trendTitle: "Latency",
            trendFormat: { NomadFormatters.latency($0) }
        )

        return DashboardCard(
            title: DashboardCardID.connectivity.displayTitle,
            subtitle: snapshot.network.throughput?.activeInterface ?? "Interface unavailable",
            subtitleAccessory: AnyView(
                InternetStatusIndicator(
                    model: InternetStatusIndicatorModel(
                        connectivity: snapshot.network.connectivity,
                        style: isCompact ? .compactIcon : .wideInline
                    )
                )
            ),
            badge: badge(for: snapshot.healthSummary.network),
            accessory: cardControls(for: .connectivity),
            collapse: collapse(for: .connectivity),
            isCompact: isCompact
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if isCompact {
                    HStack(alignment: .top, spacing: 12) {
                        download
                        upload
                    }
                    latency
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        download
                        upload
                        latency
                    }
                }

                Text(jitterDescription)
                    .font(isCompact ? .caption2 : .caption)
                    .foregroundStyle(NomadTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private func powerSection(widthMode: DashboardCardWidthMode) -> some View {
        let isCompact = widthMode == .narrow
        let typography: MetricBlock.Typography = isCompact ? .compact : .standard
        let powerMetrics = PowerMetricsPresentation(snapshot: snapshot.power.snapshot)
        let powerTint = snapshot.healthSummary.power.level.tint
        let isOnBattery = snapshot.power.snapshot?.state == .battery

        let battery = TrendMetric(
            title: "Battery",
            value: metricValue(snapshot.power.snapshot?.chargePercent.map { $0 * 100 }, formatter: NomadFormatters.percentage, fallback: "Estimating"),
            typography: typography,
            tone: powerTint,
            points: snapshot.power.chargeHistory,
            trendTint: powerTint,
            trendTitle: "Charge",
            trendFormat: { NomadFormatters.percentage($0) }
        )
        let drain = powerMetrics.drainReading.map { drainReading in
            TrendMetric(
                title: powerMetrics.drainTitle,
                reading: drainReading,
                typography: typography,
                // Only the discharge rate has a history; the adapter wattage does not.
                points: isOnBattery ? snapshot.power.dischargeHistory : nil,
                trendTint: NomadTheme.secondaryText,
                trendTitle: "Drain",
                trendFormat: { NomadFormatters.watts($0) }
            )
        }
        let timeLeft = TrendMetric(
            title: powerMetrics.timeLeftTitle,
            value: powerMetrics.timeLeftValue,
            typography: typography
        )

        return DashboardCard(
            title: DashboardCardID.power.displayTitle,
            subtitle: snapshot.power.snapshot.map(powerSubtitle) ?? "Power source unavailable",
            badge: badge(for: snapshot.healthSummary.power),
            accessory: cardControls(for: .power),
            collapse: collapse(for: .power),
            isCompact: isCompact
        ) {
            if isCompact {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        battery
                        if let drain {
                            drain
                        }
                    }
                    timeLeft
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    battery
                    if let drain {
                        drain
                    }
                    timeLeft
                }
            }
        }
    }

    private func travelSection(widthMode: DashboardCardWidthMode) -> some View {
        let isCompact = widthMode == .narrow
        let context = travelContextPresentation

        return DashboardCard(
            title: DashboardCardID.travelContext.displayTitle,
            subtitle: travelSubtitle,
            badge: travelBadge,
            accessory: cardControls(for: .travelContext),
            collapse: collapse(for: .travelContext),
            isCompact: isCompact
        ) {
            VStack(alignment: .leading, spacing: 10) {
                DetailRow(
                    label: "Public IP",
                    value: context.publicIP,
                    isCompact: isCompact,
                    compactLineLimit: 1,
                    action: DetailRowAction(
                        title: "Copy Public IP",
                        systemImage: "document.on.document",
                        isEnabled: context.hasPublicIP,
                        action: copyIPAddressAction
                    )
                )
                DetailRow(label: "Wi-Fi", value: context.wifi, isCompact: isCompact, compactLineLimit: 2, help: context.wifiHelp)
                DetailRow(label: "VPN", value: context.vpn, isCompact: isCompact, compactLineLimit: 1)
                DetailRow(
                    label: "Location",
                    value: context.location,
                    isCompact: isCompact,
                    compactLineLimit: 2,
                    action: DetailRowAction(
                        title: "Open Visited Map",
                        systemImage: "map",
                        isEnabled: true,
                        action: openVisitedMapAction
                    )
                )
            }
        }
    }

    private func timeTrackingSection(widthMode: DashboardCardWidthMode) -> some View {
        let isCompact = widthMode == .narrow
        let summary = timeTrackingDashboardState.todaySummary
        let allocation = TimeTrackingAllocationPresentation(
            summary: summary,
            bucketTitle: timeTrackingBucketTitle
        )
        let today = MetricBlock(
            title: "Today",
            value: TimeTrackingDurationFormatting.text(summary.totalTrackedDuration),
            typography: .compact
        )
        let focus = MetricBlock(
            title: "Focus",
            value: TimeTrackingDurationFormatting.text(summary.focusAdjustedDuration),
            typography: .compact
        )
        let pending = MetricBlock(
            title: "Pending",
            value: TimeTrackingDurationFormatting.text(summary.unallocatedDuration),
            typography: .compact
        )

        return DashboardCard(
            title: DashboardCardID.timeTracking.displayTitle,
            subtitle: timeTrackingSubtitle,
            badge: timeTrackingBadge,
            accessory: cardControls(for: .timeTracking),
            collapse: collapse(for: .timeTracking),
            isCompact: isCompact
        ) {
            if timeTrackingDashboardState.isEnabled == false {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Track awake working time locally, then allocate today’s pending time into projects or Other.")
                        .font(.caption)
                        .foregroundStyle(NomadTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Open Settings") {
                        openSettingsForCard(.timeTracking)
                    }
                    .buttonStyle(.dashboardInline)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if isCompact {
                        HStack(alignment: .top, spacing: 12) {
                            today
                            focus
                        }
                        pending
                    } else {
                        HStack(alignment: .top, spacing: 12) {
                            today
                            focus
                            pending
                        }
                    }

                    TimeTrackingAllocationBar(presentation: allocation, isCompact: isCompact)

                    VStack(alignment: .leading, spacing: 6) {
                        TimeTrackingInterruptionButton(
                            title: isCompact ? "Interruption" : "Report interruption",
                            count: summary.interruptionCount,
                            lastReportedAt: summary.lastInterruptionAt,
                            isEnabled: true,
                            style: .standard,
                            action: reportTimeTrackingInterruptionAction
                        )
                        .frame(maxWidth: .infinity)

                        if let focusLossCaption = allocation.focusLossCaption {
                            Text(focusLossCaption)
                                .font(.caption2)
                                .foregroundStyle(NomadTheme.tertiaryText)
                        }
                    }

                    if timeTrackingDashboardState.activeProjects.isEmpty {
                        Text("Add at least one project in Settings to enable project allocations. Other is always available.")
                            .font(.caption)
                            .foregroundStyle(NomadTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    let controls = Group {
                        Button(timeTrackingPrimaryControlTitle, action: timeTrackingPrimaryControlAction)
                        Button("Stop", action: stopTimeTrackingAction)
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            controls
                            Spacer(minLength: 0)
                            Button("Open Time Tracking", action: openTimeTrackingAction)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) { controls }
                            Button("Open Time Tracking", action: openTimeTrackingAction)
                        }
                    }
                    .buttonStyle(.dashboardInline(role: .neutral))
                }
            }
        }
    }

    private func weatherSection(widthMode: DashboardCardWidthMode) -> some View {
        let isCompact = widthMode == .narrow
        let presentation = weatherSectionPresentation
        let forecastPresentation = WeatherForecastPresentation(
            settings: settings,
            weather: snapshot.weather,
            widthMode: widthMode
        )

        return DashboardCard(
            title: DashboardCardID.weather.displayTitle,
            subtitle: presentation.subtitle,
            badge: presentation.badge,
            accessory: cardControls(for: .weather),
            collapse: collapse(for: .weather),
            isCompact: isCompact
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if let weather = snapshot.weather {
                    weatherConditions(weather, forecast: forecastPresentation, isCompact: isCompact)
                } else {
                    WeatherEmptyState(
                        title: presentation.emptyTitle,
                        systemImage: presentation.emptySystemImage,
                        message: presentation.emptyMessage
                    )
                }

                // Calculated on the Mac from the location, so it does not depend on weather data.
                if let daylight = DaylightLinePresentation(travelContext: snapshot.travelContext, now: .now) {
                    DaylightLineView(presentation: daylight)
                }

                Divider()
                    .overlay(NomadTheme.cardBorder.opacity(0.9))

                surfSection(widthMode: widthMode)

                if isCompact == false {
                    Text(weatherAttributionLine)
                        .font(.caption2)
                        .foregroundStyle(NomadTheme.tertiaryText)
                }
            }
        }
    }

    /// Current conditions on one line, three small stats, the hourly strip (always visible) and
    /// the 7-day outlook behind the persisted disclosure.
    private func weatherConditions(
        _ weather: WeatherSnapshot,
        forecast: WeatherForecastPresentation,
        isCompact: Bool
    ) -> some View {
        let wind = WeatherWindMetricPresentation(snapshot: weather)
        let feelsLike = WeatherStatView(
            title: "Feels like",
            value: metricValue(weather.apparentTemperatureCelsius, formatter: NomadFormatters.celsius, fallback: "Estimating")
        )
        let windStat = WeatherStatView(title: "Wind", value: wind.primaryValue, secondaryValue: wind.secondaryValue)
        let rain = WeatherStatView(
            title: "Rain chance",
            value: weather.precipitationChance.map { NomadFormatters.precipitation($0) } ?? "n/a"
        )

        let uv = WeatherUVPresentation(
            weather: weather,
            travelContext: snapshot.travelContext,
            now: .now,
            calendar: .current,
            locale: .current
        )
        let uvStat = uv.map { WeatherStatView(title: "UV", value: $0.value, secondaryValue: $0.peak, tone: $0.tone) }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text(metricValue(weather.currentTemperatureCelsius, formatter: NomadFormatters.celsius, fallback: "Estimating"))
                    .font(.system(size: isCompact ? 28 : 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(NomadTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Image(systemName: weather.symbolName)
                    .font(.system(size: isCompact ? 20 : 24, weight: .medium))
                    .foregroundStyle(NomadTheme.secondaryText)
                    .accessibilityHidden(true)

                if isCompact == false {
                    Text(weather.conditionDescription)
                        .font(.callout)
                        .foregroundStyle(NomadTheme.secondaryText)
                        .lineLimit(1)
                }
            }

            if isCompact {
                HStack(alignment: .top, spacing: 12) {
                    feelsLike
                    rain
                }
                HStack(alignment: .top, spacing: 12) {
                    windStat
                    if let uvStat {
                        uvStat
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    feelsLike
                    windStat
                    rain
                    if let uvStat {
                        uvStat
                    }
                }
            }

            if let airQuality = WeatherAirQualityPresentation(
                airQuality: snapshot.airQuality,
                settings: settings,
                travelContext: snapshot.travelContext,
                now: .now,
                calendar: .current,
                locale: .current
            ) {
                WeatherAirQualityView(presentation: airQuality, isCompact: isCompact)
            }

            if forecast.hourlySlots.isEmpty == false {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: isCompact ? 4 : 8), count: 4),
                    spacing: isCompact ? 4 : 8
                ) {
                    ForEach(forecast.hourlySlots) { slot in
                        WeatherHourlyForecastChip(model: slot, isCompact: isCompact)
                    }
                }
            }

            if forecast.shouldShowTomorrowSummary, let tomorrow = weather.tomorrow {
                let range = Text(tomorrow.temperatureRangeText)
                    .font(.caption)
                    .foregroundStyle(NomadTheme.secondaryText)
                let label = Label(tomorrow.summary, systemImage: tomorrow.symbolName)
                    .font(.caption)
                    .foregroundStyle(NomadTheme.primaryText)

                if isCompact {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text("Tomorrow")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(NomadTheme.tertiaryText)
                            Spacer(minLength: 4)
                            range.fixedSize()
                        }
                        label.fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("Tomorrow")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NomadTheme.tertiaryText)
                        label.lineLimit(1)
                        Spacer(minLength: 8)
                        range.fixedSize()
                    }
                }
            }

            if forecast.showsForecastDisclosure {
                ForecastDisclosureSection(
                    title: "7-day outlook",
                    isExpanded: forecast.isForecastExpanded,
                    action: toggleWeatherForecastExpanded
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(forecast.dailyRows.enumerated()), id: \.offset) { _, row in
                            WeatherDailyForecastRow(summary: row)
                        }
                    }
                }
            }
        }
    }

    private func fuelPricesSection(widthMode: DashboardCardWidthMode, viewportHeight: CGFloat) -> some View {
        FuelPricesSectionView(
            presentation: fuelPricesSectionPresentation,
            widthMode: widthMode,
            viewportHeight: viewportHeight,
            accessory: cardControls(for: .fuelPrices),
            collapse: collapse(for: .fuelPrices),
            openSettingsAction: { openSettingsForCard(.fuelPrices) },
            previewMapAction: openFuelStationMapPreviewAction,
            openGoogleMapsAction: openFuelStationInGoogleMapsAction
        )
    }

    private func staysSection(widthMode: DashboardCardWidthMode) -> some View {
        StaysSectionView(
            presentation: StaysCardPresentation(
                settings: settings,
                countryDays: visitedCountryDays,
                currentCountryCode: snapshot.currentCountryCode
            ),
            widthMode: widthMode,
            accessory: cardControls(for: .stays),
            collapse: collapse(for: .stays),
            openCitizenshipSettingsAction: { openSettingsForCard(.embassy) },
            openSettingsAction: { openSettingsForCard(.stays) },
            reviewDaysAction: openVisitedMapAction,
            openTripPlannerAction: openTripPlannerAction
        )
    }

    private func localInfoSection(widthMode: DashboardCardWidthMode) -> some View {
        LocalInfoSectionView(
            presentation: localInfoSectionPresentation,
            widthMode: widthMode,
            accessory: cardControls(for: .localInfo),
            collapse: collapse(for: .localInfo),
            openSettingsAction: { openSettingsForCard(.localInfo) }
        )
    }

    private func emergencyCareSection(widthMode: DashboardCardWidthMode) -> some View {
        EmergencyCareSectionView(
            presentation: emergencyCareSectionPresentation,
            widthMode: widthMode,
            accessory: cardControls(for: .emergencyCare),
            collapse: collapse(for: .emergencyCare),
            openSettingsAction: { openSettingsForCard(.emergencyCare) },
            previewMapAction: openEmergencyHospitalMapPreviewAction,
            openGoogleMapsAction: openEmergencyHospitalInGoogleMapsAction
        )
    }

    private func embassySection(widthMode: DashboardCardWidthMode) -> some View {
        EmbassySectionView(
            presentation: EmbassyCardPresentation(settings: settings, snapshot: snapshot),
            widthMode: widthMode,
            accessory: cardControls(for: .embassy),
            collapse: collapse(for: .embassy),
            openCitizenshipSettingsAction: { openSettingsForCard(.embassy) },
            openSettingsAction: openSettingsAction,
            openURLAction: openExternalURLAction,
            copyTextAction: copyTextAction
        )
    }

    private func travelAlertsSection(widthMode: DashboardCardWidthMode) -> some View {
        DashboardCard(
            title: DashboardCardID.travelAlerts.displayTitle,
            subtitle: travelAlertsSubtitle,
            badge: travelAlertsBadge,
            accessory: cardControls(for: .travelAlerts),
            collapse: collapse(for: .travelAlerts),
            isCompact: widthMode == .narrow
        ) {
            if travelAlertPreferences.enabledKinds.isEmpty {
                WeatherEmptyState(
                    title: "Alerts Off",
                    systemImage: "bell.slash.fill",
                    message: "Enable traveller alerts in Settings."
                )
            } else if shouldShowTravelAlertsAllClearRow {
                CompactAlertRow(
                    title: "No current alerts",
                    summary: "No elevated alerts across enabled travel signals.",
                    sourceName: "Nomad",
                    count: nil,
                    tint: NomadTheme.teal,
                    symbolName: "checkmark.circle.fill"
                )
            } else if travelAlertRows.isEmpty {
                WeatherEmptyState(
                    title: "Checking alerts",
                    systemImage: "clock.badge.exclamationmark",
                    message: "Checking alerts…"
                )
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(travelAlertsPresentation.notices, id: \.text) { notice in
                        Label(notice.text, systemImage: notice.symbolName)
                            .font(.caption)
                            .foregroundStyle(NomadTheme.sand)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ForEach(travelAlertRows) { row in
                        TravelAlertSignalRow(
                            row: row,
                            showsChip: travelAlertsPresentation.showsSignalChips,
                            isCompact: widthMode == .narrow,
                            openSourceAction: openTravelAlertSourceAction
                        )
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.appState.updateState.detail ?? "Update channel idle")
                    .font(.caption)
                    .foregroundStyle(NomadTheme.secondaryText)

                if versionDescription.isEmpty == false {
                    Text(versionDescription)
                        .font(.caption2)
                        .foregroundStyle(NomadTheme.quaternaryText)
                }
            }

            Spacer(minLength: 12)

            if let appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 28, height: 28)
                    .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
                    .accessibilityHidden(true)
            }
        }
    }

    private var appearanceToggleSystemImage: String {
        colorScheme == .dark ? "sun.max.fill" : "moon.fill"
    }

    private var appearanceToggleTitle: String {
        colorScheme == .dark ? "Switch to Light Appearance" : "Switch to Dark Appearance"
    }

    private var refreshStatusTint: Color {
        switch refreshActivity {
        case .idle:
            NomadTheme.tertiaryText
        case .manualInProgress:
            NomadTheme.teal
        case .slowAutomaticInProgress:
            NomadTheme.teal.opacity(0.82)
        }
    }

    private var jitterDescription: String {
        if let jitter = snapshot.network.latency?.jitterMilliseconds {
            return "Jitter \(NomadFormatters.latency(jitter)) via \(snapshot.network.latency?.host ?? "n/a")"
        }

        return "Jitter will appear after the next slow refresh"
    }

    private var travelSubtitle: String {
        if let location = snapshot.travelContext.location,
           let formattedLocation = formattedLocation(location)
        {
            return formattedLocation
        }

        if let ssid = snapshot.travelContext.wifi?.ssid {
            return ssid
        }

        return "Network identity and environment"
    }

    private var travelBadge: PillBadge {
        if snapshot.travelContext.vpn?.isActive == true {
            return PillBadge(title: "VPN On", symbolName: "lock.shield.fill", tint: NomadTheme.primaryText)
        }

        return PillBadge(title: "VPN Off", symbolName: "lock.open.fill", tint: NomadTheme.primaryText)
    }

    private var travelContextPresentation: TravelContextPresentation {
        TravelContextPresentation(
            travelContext: snapshot.travelContext,
            issues: snapshot.appState.issues,
            isPublicIPLocationEnabled: isPublicIPLocationEnabled
        )
    }

    private func surfSection(widthMode: DashboardCardWidthMode) -> some View {
        let presentation = surfSectionPresentation
        let isCompact = widthMode == .narrow

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Surf Spot")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NomadTheme.primaryText)

                    Text(presentation.spotName ?? "One saved break for wave, swell, and wind.")
                        .font(.caption)
                        .foregroundStyle(NomadTheme.secondaryText)
                }

                Spacer(minLength: 12)

                if presentation.isActionable {
                    Button(action: openSurfSpotSettingsAction) {
                        BadgeView(badge: presentation.badge, isCompact: isCompact)
                    }
                    .buttonStyle(.plain)
                    .help("Open Surf Spot Settings")
                } else {
                    BadgeView(badge: presentation.badge, isCompact: isCompact)
                }
            }

            if let marine = presentation.marine {
                VStack(alignment: .leading, spacing: 10) {
                    // Current conditions: one row of single-line stats (two columns when narrow).
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .topLeading), count: isCompact ? 2 : 4),
                        alignment: .leading,
                        spacing: 8
                    ) {
                        WeatherStatView(title: "Wave", value: presentation.waveSummary)
                        WeatherStatView(title: "Swell", value: presentation.swellSummary)
                        WeatherStatView(title: "Wind", value: presentation.windSummary)
                        if let seaSurfaceTemperature = marine.seaSurfaceTemperatureCelsius {
                            WeatherStatView(title: "Sea", value: NomadFormatters.celsius(seaSurfaceTemperature))
                        }
                    }

                    if isCompact == false, presentation.forecastSlots.isEmpty == false {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                            spacing: 8
                        ) {
                            ForEach(presentation.forecastSlots) { slot in
                                MarineForecastChip(model: slot)
                            }
                        }
                    }
                }
            } else {
                WeatherEmptyState(
                    title: presentation.emptyTitle,
                    systemImage: presentation.emptySystemImage,
                    message: presentation.emptyMessage,
                    actionTitle: presentation.emptyActionTitle,
                    action: presentation.isActionable ? openSurfSpotSettingsAction : nil
                )
            }
        }
    }

    private var surfSectionPresentation: SurfSectionPresentation {
        SurfSectionPresentation(settings: settings, snapshot: snapshot)
    }

    private var weatherSectionPresentation: WeatherSectionPresentation {
        WeatherSectionPresentation(
            settings: settings,
            snapshot: snapshot,
            weatherAvailabilityExplanation: weatherAvailabilityExplanation,
            locationStatusDetail: locationStatusDetail
        )
    }

    private var fuelPricesSectionPresentation: FuelPricesSectionPresentation {
        FuelPricesSectionPresentation(
            settings: settings,
            snapshot: snapshot,
            locationStatusDetail: locationStatusDetail
        )
    }

    private var localInfoSectionPresentation: LocalInfoSectionPresentation {
        LocalInfoSectionPresentation(
            settings: settings,
            snapshot: snapshot,
            locationStatusDetail: locationStatusDetail
        )
    }

    private var emergencyCareSectionPresentation: EmergencyCareSectionPresentation {
        EmergencyCareSectionPresentation(
            settings: settings,
            snapshot: snapshot,
            locationStatusDetail: locationStatusDetail
        )
    }

    private var weatherAttributionLine: String {
        if settings.surfSpotConfiguration.isConfigured || snapshot.marine != nil {
            return "Weather: WeatherKit · Surf: Open-Meteo"
        }

        return "Weather: WeatherKit"
    }

    private var travelAlertsSubtitle: String {
        guard travelAlertPreferences.enabledKinds.isEmpty == false else {
            return "Traveller risk signals are disabled"
        }

        guard let alertsSnapshot = snapshot.travelAlerts else {
            return "Current country + bordering countries"
        }

        if let primaryCountryName = alertsSnapshot.primaryCountryName {
            let neighborCount = max(alertsSnapshot.coverageCountryCodes.count - 1, 0)
            if neighborCount > 0 {
                let label = neighborCount == 1 ? "bordering country" : "bordering countries"
                return "\(primaryCountryName) + \(neighborCount) \(label)"
            }

            return primaryCountryName
        }

        return "Current country unavailable"
    }

    private var travelAlertsBadge: PillBadge {
        travelAlertsPresentation.badge.pillBadge
    }

    private var shouldShowTravelAlertsAllClearRow: Bool {
        travelAlertsPresentation.showsAllClearRow
    }

    private var travelAlertRows: [TravelAlertRowModel] {
        travelAlertsPresentation.rows
    }

    private var compactTravelAlertRows: [TravelAlertCompactDisplayRow] {
        guard travelAlertRows.count > 3 else {
            return travelAlertRows.map { .alert($0) }
        }

        return Array(travelAlertRows.prefix(2)).map { .alert($0) } + [
            .overflow(count: travelAlertRows.count - 2)
        ]
    }

    private var travelAlertsPresentation: TravelAlertsCardPresentation {
        TravelAlertsCardPresentation(
            preferences: travelAlertPreferences,
            snapshot: snapshot.travelAlerts
        )
    }

    private var alertsSummaryTilePresentation: SummaryTilePresentation {
        SummaryTilePresentation(weather: snapshot.weather, alertsPresentation: travelAlertsPresentation)
    }

    private var networkSummaryTilePresentation: SummaryTilePresentation {
        SummaryTilePresentation(title: "Network", network: snapshot.network, health: snapshot.healthSummary.network)
    }

    private var powerSummaryTilePresentation: SummaryTilePresentation {
        SummaryTilePresentation(title: "Power", power: snapshot.power, health: snapshot.healthSummary.power)
    }

    private func badge(for health: SectionHealth) -> PillBadge {
        PillBadge(title: health.label, symbolName: health.symbolName, tint: health.level.tint)
    }

    private var timeTrackingHeaderPill: some View {
        TimeTrackingHeaderPillView(
            presentation: timeTrackingQuickActionsPresentation,
            chipsEnabled: timeTrackingDashboardState.todaySummary.unallocatedDuration > 0,
            primaryAction: timeTrackingPrimaryControlAction,
            stopAction: stopTimeTrackingAction,
            interruptionCount: timeTrackingDashboardState.todaySummary.interruptionCount,
            lastInterruptionAt: timeTrackingDashboardState.todaySummary.lastInterruptionAt,
            interruptionAction: reportTimeTrackingInterruptionAction,
            allocateAction: allocateTimeTrackingAction,
            openAction: openTimeTrackingAction
        )
    }

    private func collapse(for cardID: DashboardCardID) -> DashboardCardCollapse {
        let summary = DashboardCardSummaryPresentation(
            cardID: cardID,
            snapshot: snapshot,
            settings: settings,
            travelAlertPreferences: travelAlertPreferences,
            timeTracking: timeTrackingDashboardState,
            visitedCountryDays: visitedCountryDays
        )

        return DashboardCardCollapse(
            cardTitle: cardID.displayTitle,
            isCollapsed: resolvedCollapsedCards.contains(cardID),
            summary: summary.text,
            summaryHelp: summary.help,
            toggle: { setCollapsed(resolvedCollapsedCards.contains(cardID) == false, for: cardID) }
        )
    }

    private func setCollapsed(_ isCollapsed: Bool, for cardID: DashboardCardID) {
        var updated = resolvedCollapsedCards
        if isCollapsed {
            updated.insert(cardID)
        } else {
            updated.remove(cardID)
        }

        guard updated != resolvedCollapsedCards else {
            return
        }

        withAnimation(.snappy) {
            resolvedCollapsedCards = updated
        }
        onCollapsedCardsChange(updated)
    }

    /// Width toggle and drag handle, shown only while the layout is being customized.
    private func cardControls(for cardID: DashboardCardID) -> AnyView? {
        guard isCustomizingLayout else {
            return nil
        }

        return AnyView(
            HStack(spacing: 6) {
                // A collapsed card is always a full-width line, so its width cannot change.
                if resolvedCollapsedCards.contains(cardID) == false {
                    DashboardCardWidthToggleButton(
                        widthMode: resolvedCardWidthModes[cardID] ?? .wide,
                        title: cardID.displayTitle
                    ) {
                        toggleWidthMode(for: cardID)
                    }
                }

                DashboardCardDragHandle(cardID: cardID, title: cardID.displayTitle)
            }
        )
    }

    private func toggleWidthMode(for cardID: DashboardCardID) {
        let currentWidthModes = DashboardCardID.sanitizedWidthModes(resolvedCardWidthModes)
        let currentWidthMode = currentWidthModes[cardID] ?? .wide
        let nextWidthMode: DashboardCardWidthMode = currentWidthMode == .wide ? .narrow : .wide
        var updatedWidthModes = currentWidthModes
        updatedWidthModes[cardID] = nextWidthMode
        let sanitizedWidthModes = DashboardCardID.sanitizedWidthModes(updatedWidthModes)
        resolvedCardWidthModes = sanitizedWidthModes
        onCardWidthModesChange(sanitizedWidthModes)
    }

    private func toggleWeatherForecastExpanded() {
        onWeatherForecastExpandedChange(settings.weatherForecastExpanded == false)
    }

    /// A reading with its unit apart; a missing value shows `fallback` with no unit.
    private func metricReading(
        _ value: Double?,
        formatter: (Double?) -> FormattedMetric,
        fallback: String = "Collecting"
    ) -> FormattedMetric {
        value == nil ? FormattedMetric(number: fallback) : formatter(value)
    }

    private func metricValue(
        _ value: Double?,
        formatter: (Double?) -> String,
        fallback: String = "Collecting"
    ) -> String {
        guard value != nil else {
            return fallback
        }

        return formatter(value)
    }

    private func formattedLocation(_ location: IPLocationSnapshot) -> String? {
        location.cityCountryDescription
    }

    private func powerSubtitle(_ snapshot: PowerSnapshot) -> String {
        switch snapshot.state {
        case .battery:
            "Running on battery"
        case .charging:
            "Charging"
        case .charged:
            "Connected to power"
        case .unknown:
            "Power status unavailable"
        }
    }

    private var timeTrackingQuickActionsPresentation: TimeTrackingQuickActionsPresentation {
        TimeTrackingQuickActionsPresentation(
            activeProjects: timeTrackingDashboardState.activeProjects,
            recentProjects: timeTrackingDashboardState.recentProjects,
            pendingDurationText: TimeTrackingDurationFormatting.text(timeTrackingDashboardState.todaySummary.unallocatedDuration),
            activityState: timeTrackingDashboardState.activityState,
            openTitle: "Open Time Tracking"
        )
    }

    private var timeTrackingPrimaryControlTitle: String {
        switch timeTrackingDashboardState.activityState {
        case .running:
            "Pause"
        case .paused:
            "Resume"
        case .stopped:
            "Play"
        }
    }

    private var timeTrackingPrimaryControlAction: () -> Void {
        switch timeTrackingDashboardState.activityState {
        case .running:
            pauseTimeTrackingAction
        case .paused:
            resumeTimeTrackingAction
        case .stopped:
            playTimeTrackingAction
        }
    }

    private var timeTrackingActivityTitle: String {
        switch timeTrackingDashboardState.activityState {
        case .running:
            "Running"
        case .paused:
            "Paused"
        case .stopped:
            "Stopped"
        }
    }

    private var timeTrackingSubtitle: String {
        if timeTrackingDashboardState.isEnabled == false {
            return "Off in Settings"
        }

        return "\(timeTrackingActivityTitle) · \(timeTrackingDashboardState.activeProjects.count) project\(timeTrackingDashboardState.activeProjects.count == 1 ? "" : "s")"
    }

    private var timeTrackingBadge: PillBadge {
        if timeTrackingDashboardState.isEnabled == false {
            return PillBadge(title: "Off", symbolName: "clock.badge.xmark", tint: NomadTheme.primaryText)
        }

        switch timeTrackingDashboardState.activityState {
        case .running:
            return PillBadge(title: "Live", symbolName: "play.fill", tint: NomadTheme.teal)
        case .paused:
            return PillBadge(title: "Paused", symbolName: "pause.fill", tint: NomadTheme.sand)
        case .stopped:
            return PillBadge(title: "Stopped", symbolName: "stop.fill", tint: NomadTheme.primaryText)
        }
    }

    private func timeTrackingBucketTitle(_ bucket: TimeTrackingBucket) -> String {
        switch bucket {
        case let .project(id):
            timeTrackingDashboardState.activeProjects.first(where: { $0.id == id })?.trimmedName ?? "Archived Project"
        case .other:
            "Other"
        case .unallocated:
            "Unallocated"
        }
    }
}

struct PowerMetricsPresentation: Equatable {
    /// Title of the second metric: "Drain" on battery, "Adapter" on external power.
    let drainTitle: String
    /// Discharge rate, or adapter wattage on external power, with the unit apart. `nil` when
    /// there is nothing useful to show (the metric is omitted instead of repeating the card subtitle).
    let drainReading: FormattedMetric?
    let timeLeftTitle: String
    let timeLeftValue: String
    /// One-line summary for compact surfaces such as the glance power tile.
    let summary: String

    /// "11.4 W" as one string.
    var drainValue: String? {
        drainReading?.text
    }

    init(snapshot: PowerSnapshot?) {
        guard let snapshot else {
            drainTitle = "Drain"
            drainReading = FormattedMetric(number: "Estimating")
            timeLeftTitle = "Time Left"
            timeLeftValue = "Estimating"
            summary = "Estimating"
            return
        }

        switch snapshot.state {
        case .charging:
            drainTitle = "Adapter"
            drainReading = snapshot.adapterWatts.map { NomadFormatters.wattsParts($0) }
            timeLeftTitle = "To Full"
            timeLeftValue = snapshot.timeToFullChargeMinutes.map { NomadFormatters.minutes($0) } ?? "Estimating"
            summary = snapshot.timeToFullChargeMinutes.map { "Charging · \(NomadFormatters.minutes($0)) to full" } ?? "Charging"
        case .charged:
            drainTitle = "Adapter"
            drainReading = snapshot.adapterWatts.map { NomadFormatters.wattsParts($0) }
            timeLeftTitle = "Charge"
            timeLeftValue = "Full"
            summary = "Plugged in"
        case .battery:
            drainTitle = "Drain"
            drainReading = snapshot.dischargeRateWatts.map { NomadFormatters.wattsParts($0) } ?? FormattedMetric(number: "On battery")
            timeLeftTitle = "Time Left"
            timeLeftValue = snapshot.timeRemainingMinutes.map { NomadFormatters.minutes($0) } ?? "Estimating"
            summary = snapshot.timeRemainingMinutes.map { "\(NomadFormatters.minutes($0)) left" } ?? "On battery"
        case .unknown:
            drainTitle = "Drain"
            drainReading = FormattedMetric(number: "Estimating")
            timeLeftTitle = "Time Left"
            timeLeftValue = "Estimating"
            summary = "Estimating"
        }
    }
}

/// Collapse state of one card: when collapsed it shrinks to a single line (title, summary,
/// status badge, chevron).
struct DashboardCardCollapse {
    let cardTitle: String
    let isCollapsed: Bool
    let summary: String
    /// Longer wording for hover and VoiceOver (for example the hospital name).
    let summaryHelp: String
    let toggle: () -> Void
}

struct DashboardCard<Content: View>: View {
    let title: String
    let subtitle: String
    let isSubtitleSelectable: Bool
    let subtitleAccessory: AnyView?
    let badge: PillBadge?
    let accessory: AnyView?
    let backgroundDecoration: AnyView?
    let isCompact: Bool
    let collapse: DashboardCardCollapse?
    let content: Content

    init(
        title: String,
        subtitle: String,
        isSubtitleSelectable: Bool = false,
        subtitleAccessory: AnyView? = nil,
        badge: PillBadge? = nil,
        accessory: AnyView? = nil,
        collapse: DashboardCardCollapse? = nil,
        backgroundDecoration: AnyView? = nil,
        isCompact: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isSubtitleSelectable = isSubtitleSelectable
        self.subtitleAccessory = subtitleAccessory
        self.badge = badge
        self.accessory = accessory
        self.backgroundDecoration = backgroundDecoration
        self.isCompact = isCompact
        self.collapse = collapse
        self.content = content()
    }

    private var isCollapsed: Bool {
        collapse?.isCollapsed == true
    }

    var body: some View {
        let cardShape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        Group {
            if let collapse, collapse.isCollapsed {
                collapsedRow(collapse)
            } else {
                expandedBody
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 16)
        .padding(.vertical, isCollapsed ? 6 : 16)
        .background(
            ZStack {
                cardShape
                    .fill(NomadTheme.cardBackground)

                if let backgroundDecoration, isCollapsed == false {
                    backgroundDecoration
                        .clipShape(cardShape)
                }

                cardShape
                    .stroke(NomadTheme.cardBorder, lineWidth: 1)
            }
        )
        .clipped()
    }

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: isCompact ? .center : .top, spacing: isCompact ? 8 : 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: isCompact ? 15 : 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(NomadTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(isCompact ? 0.75 : 0.9)

                    HStack(spacing: isCompact ? 6 : 8) {
                        subtitleText

                        if let subtitleAccessory {
                            subtitleAccessory
                        }
                    }
                }
                .layoutPriority(1)

                Spacer(minLength: isCompact ? 6 : 12)

                HStack(spacing: isCompact ? 6 : 8) {
                    if let badge {
                        BadgeView(badge: badge, isCompact: isCompact)
                    }

                    if let accessory {
                        accessory
                    }

                    if let collapse {
                        DashboardCardChevronButton(collapse: collapse)
                    }
                }
            }

            content
        }
    }

    @ViewBuilder
    private var subtitleText: some View {
        let text = Text(subtitle)
            .font(isCompact ? .caption2 : .caption)
            .foregroundStyle(NomadTheme.secondaryText)
            .lineLimit(isCompact ? 3 : 2)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: true)

        if isSubtitleSelectable {
            text.textSelection(.enabled)
        } else {
            text
        }
    }

    /// One line of about 40 pt: title, summary, status badge, chevron. The whole line expands the
    /// card; in Customize Layout the drag handle sits beside the chevron.
    private func collapsedRow(_ collapse: DashboardCardCollapse) -> some View {
        HStack(spacing: 8) {
            Button(action: collapse.toggle) {
                HStack(spacing: 10) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(NomadTheme.primaryText)
                        .lineLimit(1)
                        .fixedSize()

                    Text(collapse.summary)
                        .font(.caption)
                        .foregroundStyle(NomadTheme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 4)

                    if let badge {
                        ViewThatFits(in: .horizontal) {
                            BadgeView(badge: badge)
                            BadgeView(badge: badge, isCompact: true)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(collapse.summaryHelp)
            .accessibilityLabel("\(title), \(collapse.summaryHelp)")
            .accessibilityHint("Expands the card")

            if let accessory {
                accessory
            }

            DashboardCardChevronButton(collapse: collapse)
        }
        .frame(minHeight: 28)
    }
}

private struct DashboardCardChevronButton: View {
    let collapse: DashboardCardCollapse

    var body: some View {
        Button(action: collapse.toggle) {
            Image(systemName: collapse.isCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(NomadTheme.tertiaryText)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(collapse.isCollapsed ? "Expand \(collapse.cardTitle)" : "Collapse \(collapse.cardTitle)")
        .accessibilityLabel(collapse.isCollapsed ? "Expand \(collapse.cardTitle)" : "Collapse \(collapse.cardTitle)")
    }
}

enum InternetStatusIndicatorStyle: Equatable {
    case wideInline
    case compactIcon
}

enum InternetStatusIndicatorTone: Equatable {
    case online
    case checking
    case offline
}

struct InternetStatusIndicatorModel: Equatable {
    let symbolName: String
    let iconTreatment: StatusSymbolTreatment
    let label: String?
    let accessibilityLabel: String
    let tone: InternetStatusIndicatorTone
    let style: InternetStatusIndicatorStyle

    init(connectivity: ConnectivitySnapshot, style: InternetStatusIndicatorStyle) {
        self.style = style

        switch connectivity.internetState {
        case .online:
            symbolName = "checkmark.circle.fill"
            iconTreatment = .plain
            label = style == .wideInline ? "Online" : nil
            accessibilityLabel = "Internet online"
            tone = .online
        case .checking:
            symbolName = "ellipsis.circle.fill"
            iconTreatment = .plain
            label = style == .wideInline ? "Checking" : nil
            accessibilityLabel = "Checking internet"
            tone = .checking
        case .offline:
            symbolName = "wifi.slash"
            iconTreatment = .warningBadge
            label = style == .wideInline ? "Offline" : nil
            accessibilityLabel = "Internet offline"
            tone = .offline
        }
    }
}

struct InternetStatusIndicator: View {
    let model: InternetStatusIndicatorModel

    var body: some View {
        Group {
            switch model.style {
            case .wideInline:
                HStack(spacing: 6) {
                    Text("•")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(NomadTheme.tertiaryText)

                    StatusSymbolView(
                        systemName: model.symbolName,
                        treatment: model.iconTreatment,
                        size: .panel,
                        foregroundColor: tint
                    )

                    if let label = model.label {
                        Text(label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(tint)
                            .lineLimit(1)
                    }
                }
            case .compactIcon:
                StatusSymbolView(
                    systemName: model.symbolName,
                    treatment: model.iconTreatment,
                    size: .panel,
                    foregroundColor: tint
                )
            }
        }
        .help(model.accessibilityLabel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
    }

    private var tint: Color {
        switch model.tone {
        case .online:
            NomadTheme.teal
        case .checking:
            NomadTheme.secondaryText
        case .offline:
            NomadTheme.coral
        }
    }
}

private struct DashboardCardDragHandle: View {
    let cardID: DashboardCardID
    let title: String

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(NomadTheme.tertiaryText)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(NomadTheme.inlineButtonBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(NomadTheme.cardBorder.opacity(0.9), lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .draggable(cardID.rawValue)
            .help("Drag to reorder \(title)")
            .accessibilityLabel("Drag to reorder \(title)")
    }
}

private struct DashboardCardWidthToggleButton: View {
    let widthMode: DashboardCardWidthMode
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: widthMode == .wide ? "rectangle.split.1x2" : "rectangle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NomadTheme.tertiaryText)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(NomadTheme.inlineButtonBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(NomadTheme.cardBorder.opacity(0.9), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .help(widthMode == .wide ? "Make \(title) narrow" : "Make \(title) wide")
        .accessibilityLabel(widthMode == .wide ? "Make \(title) narrow" : "Make \(title) wide")
    }
}

private struct DashboardCardDropTarget<Content: View>: View {
    let isHighlighted: Bool
    @ViewBuilder let content: () -> Content
    let onDrop: ([String], CGPoint, CGSize) -> Bool
    let isTargeted: (Bool) -> Void

    var body: some View {
        content()
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        isHighlighted ? NomadTheme.teal.opacity(0.9) : Color.clear,
                        style: StrokeStyle(lineWidth: 1.5, dash: [7, 4])
                    )
                    .padding(1)
                    .allowsHitTesting(false)
            }
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .dropDestination(for: String.self) { items, location in
                            onDrop(items, location, geometry.size)
                        } isTargeted: { value in
                            isTargeted(value)
                        }
                }
            }
    }
}

struct DashboardRefreshHeaderPresentation: Equatable {
    let statusText: String
    let buttonTitle: String
    let isButtonEnabled: Bool

    init(lastRefresh: Date?, refreshActivity: DashboardRefreshActivity) {
        switch refreshActivity {
        case .idle:
            statusText = "Last refresh \(NomadFormatters.relativeDate(lastRefresh))"
            buttonTitle = "Refresh"
            isButtonEnabled = true
        case .manualInProgress:
            statusText = "Refreshing dashboard…"
            buttonTitle = "Refreshing dashboard"
            isButtonEnabled = false
        case .slowAutomaticInProgress:
            statusText = "Background refresh…"
            buttonTitle = "Background refresh in progress"
            isButtonEnabled = false
        }
    }
}

private struct HeaderIconButton: View {
    let systemImage: String
    let title: String
    var isEnabled = true
    var activity: DashboardRefreshActivity = .idle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HeaderActionIcon(systemImage: systemImage, activity: activity)
        }
        .buttonStyle(.plain)
        .disabled(isEnabled == false)
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct HeaderActionIcon: View {
    let systemImage: String
    var activity: DashboardRefreshActivity = .idle
    /// Overrides the idle icon and border colors, for a persistent "on" state such as Keep Awake.
    var tint: Color?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 10.0, paused: activity == .idle)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            let rotation = rotationAngle(for: phase)
            let pulse = pulseValue(for: phase)

            ZStack {
                if activity != .idle {
                    Circle()
                        .stroke(activityTint.opacity(activity == .manualInProgress ? 0.26 : 0.18), lineWidth: 2)
                        .scaleEffect(1.02 + pulse * (activity == .manualInProgress ? 0.24 : 0.18))
                        .opacity(activity == .manualInProgress ? 0.65 - pulse * 0.22 : 0.45 - pulse * 0.16)
                }

                Circle()
                    .fill(backgroundTint)
                    .overlay(
                        Circle()
                            .stroke(borderTint, lineWidth: 1)
                    )

                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(foregroundTint)
                    .rotationEffect(rotation)
            }
            .frame(width: 34, height: 34)
        }
    }

    private var foregroundTint: Color {
        switch activity {
        case .idle:
            tint ?? NomadTheme.actionIconForeground
        case .manualInProgress:
            NomadTheme.teal
        case .slowAutomaticInProgress:
            NomadTheme.teal.opacity(0.82)
        }
    }

    private var backgroundTint: Color {
        switch activity {
        case .idle:
            NomadTheme.actionIconBackground
        case .manualInProgress:
            NomadTheme.actionIconBackground.opacity(0.96)
        case .slowAutomaticInProgress:
            NomadTheme.actionIconBackground.opacity(0.9)
        }
    }

    private var borderTint: Color {
        switch activity {
        case .idle:
            tint?.opacity(0.42) ?? NomadTheme.actionIconBorder
        case .manualInProgress:
            NomadTheme.teal.opacity(0.42)
        case .slowAutomaticInProgress:
            NomadTheme.teal.opacity(0.28)
        }
    }

    private var isSpinning: Bool {
        switch activity {
        case .idle:
            false
        case .manualInProgress, .slowAutomaticInProgress:
            true
        }
    }

    private var activityTint: Color {
        switch activity {
        case .idle:
            .clear
        case .manualInProgress:
            NomadTheme.teal
        case .slowAutomaticInProgress:
            NomadTheme.teal.opacity(0.82)
        }
    }

    private func rotationAngle(for phase: TimeInterval) -> Angle {
        guard isSpinning else {
            return .degrees(0)
        }

        let cycleDuration = activity == .manualInProgress ? 0.95 : 1.2
        let progress = phase.truncatingRemainder(dividingBy: cycleDuration) / cycleDuration
        return .degrees(progress * 360)
    }

    private func pulseValue(for phase: TimeInterval) -> Double {
        guard activity != .idle else {
            return 0
        }

        let cycleDuration = activity == .manualInProgress ? 1.05 : 1.35
        let progress = phase.truncatingRemainder(dividingBy: cycleDuration) / cycleDuration
        return (sin(progress * .pi * 2) + 1) / 2
    }
}

enum SummaryTileTone: Equatable {
    case ready
    case caution
    case attention
    case neutral
    case secondary
    case critical

    init(level: HealthLevel) {
        switch level {
        case .ready:
            self = .ready
        case .caution:
            self = .caution
        case .attention:
            self = .attention
        case .unavailable:
            self = .neutral
        }
    }

    init(severity: TravelAlertSeverity) {
        switch severity {
        case .clear:
            self = .ready
        case .info:
            self = .neutral
        case .caution:
            self = .caution
        case .warning:
            self = .attention
        case .critical:
            self = .critical
        }
    }

    var tint: Color {
        switch self {
        case .ready:
            NomadTheme.teal
        case .caution:
            NomadTheme.sand
        case .attention:
            NomadTheme.coral
        case .neutral:
            NomadTheme.primaryText
        case .secondary:
            NomadTheme.secondaryText
        case .critical:
            .red
        }
    }
}

struct SummaryTilePresentation: Equatable {
    let title: String
    let label: String
    let symbolName: String
    let detail: String
    let tone: SummaryTileTone

    init(title: String, health: SectionHealth, detail: String? = nil) {
        self.title = title
        label = health.label
        symbolName = health.symbolName
        self.detail = detail ?? health.reason
        tone = SummaryTileTone(level: health.level)
    }

    init(title: String, network: NetworkSectionSnapshot, health: SectionHealth) {
        let detail: String
        if let latency = network.latency {
            let latencyText = "Latency \(NomadFormatters.latency(latency.milliseconds))"
            if let jitter = latency.jitterMilliseconds {
                detail = "\(latencyText) · Jitter \(NomadFormatters.latency(jitter))"
            } else {
                detail = latencyText
            }
        } else {
            detail = health.reason
        }

        self.init(title: title, health: health, detail: detail)
    }

    init(title: String, power: PowerSectionSnapshot, health: SectionHealth) {
        let detail: String = if let chargePercent = power.snapshot?.chargePercent {
            "\(NomadFormatters.percentage(chargePercent * 100)) · \(health.reason)"
        } else {
            health.reason
        }

        self.init(title: title, health: health, detail: detail)
    }

    init(weather: WeatherSnapshot?, alertsPresentation: TravelAlertsCardPresentation) {
        title = "Alerts"

        let temperature = weather?.currentTemperatureCelsius.map(NomadFormatters.celsius) ?? "Weather estimating"
        let highestPriorityRow = alertsPresentation.rows.sorted(by: Self.summaryRowPriority).first

        switch alertsPresentation.badge {
        case .off:
            label = "Off"
            symbolName = "bell.slash.fill"
            detail = "\(temperature) · Alerts off"
            tone = .neutral
        case .checking:
            label = "Checking"
            symbolName = "clock.fill"
            detail = "\(temperature) · Checking alerts…"
            tone = .secondary
        case .limited:
            label = "Limited"
            symbolName = "exclamationmark.triangle.fill"
            detail = "\(temperature) · Some alert sources unavailable"
            tone = .caution
        case .stale:
            label = "Stale"
            symbolName = "clock.arrow.circlepath"
            detail = "\(temperature) · \(highestPriorityRow?.summary ?? "Last known alert status unavailable.")"
            tone = .neutral
        case let .severity(severity):
            label = severity.badgeTitle
            symbolName = severity.symbolName
            tone = SummaryTileTone(severity: severity)
            if severity == .clear {
                detail = "\(temperature) · No current alerts"
            } else {
                detail = "\(temperature) · \(highestPriorityRow?.summary ?? "Alerts active")"
            }
        }
    }

    private static func summaryRowPriority(lhs: TravelAlertRowModel, rhs: TravelAlertRowModel) -> Bool {
        if lhs.status != rhs.status {
            return lhs.status == .ready
        }

        if lhs.severity != rhs.severity {
            return lhs.severity > rhs.severity
        }

        return lhs.id.rawValue < rhs.id.rawValue
    }
}

private struct SummaryTile: View {
    let presentation: SummaryTilePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(presentation.title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(NomadTheme.tertiaryText)

            Label(presentation.label, systemImage: presentation.symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(presentation.tone.tint)
                .lineLimit(1)

            Text(presentation.detail)
                .font(.caption)
                .foregroundStyle(NomadTheme.secondaryText)
                .lineLimit(3)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(NomadTheme.tileBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(presentation.tone.tint.opacity(0.18), lineWidth: 1)
                )
        )
    }
}

private struct MetricBlock: View {
    enum Typography {
        case standard
        case compact

        var font: Font {
            switch self {
            case .standard:
                .system(size: 22, weight: .semibold, design: .rounded)
            case .compact:
                .system(size: 20, weight: .semibold, design: .rounded)
            }
        }

        var lineLimit: Int {
            switch self {
            case .standard:
                2
            case .compact:
                1
            }
        }

        var minimumScaleFactor: CGFloat {
            switch self {
            case .standard:
                0.65
            case .compact:
                0.75
            }
        }

        var secondaryFont: Font {
            switch self {
            case .standard:
                .caption
            case .compact:
                .caption2
            }
        }

        var unitFont: Font {
            switch self {
            case .standard:
                .system(size: 13, weight: .semibold, design: .rounded)
            case .compact:
                .system(size: 11, weight: .semibold, design: .rounded)
            }
        }
    }

    /// The unit draws small and secondary so a narrow column can show the number at full size.
    private var valueText: Text {
        guard let unit else {
            return Text(value)
                .font(typography.font)
                .foregroundStyle(tone)
        }

        return Text(value)
            .font(typography.font)
            .foregroundStyle(tone)
            + Text(" \(unit)")
            .font(typography.unitFont)
            .foregroundStyle(NomadTheme.secondaryText)
    }

    let title: String
    let value: String
    var unit: String?
    var secondaryValue: String?
    var typography: Typography = .standard
    /// Value color. Defaults to primary text; pass a status tint only when the value
    /// carries a good/caution/bad meaning (battery level, latency, data cap).
    var tone: Color = NomadTheme.primaryText

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(NomadTheme.tertiaryText)

            valueText
                .lineLimit(typography.lineLimit)
                .minimumScaleFactor(typography.minimumScaleFactor)

            if let secondaryValue {
                Text(secondaryValue)
                    .font(typography.secondaryFont)
                    .foregroundStyle(NomadTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A metric with its sparkline directly underneath. Without `points` the metric stands alone
/// (the sparkline slot stays empty so neighbouring columns keep their rhythm).
private struct TrendMetric: View {
    let title: String
    let value: String
    var unit: String?
    var typography: MetricBlock.Typography = .standard
    var tone: Color = NomadTheme.primaryText
    var points: [MetricPoint]?
    var trendTint: Color = NomadTheme.secondaryText
    var trendTitle = "Trend"
    var trendFormat: (Double) -> String = { String(format: "%.0f", $0) }

    init(
        title: String,
        reading: FormattedMetric,
        typography: MetricBlock.Typography = .standard,
        tone: Color = NomadTheme.primaryText,
        points: [MetricPoint]? = nil,
        trendTint: Color = NomadTheme.secondaryText,
        trendTitle: String = "Trend",
        trendFormat: @escaping (Double) -> String = { String(format: "%.0f", $0) }
    ) {
        self.title = title
        value = reading.number
        unit = reading.unit
        self.typography = typography
        self.tone = tone
        self.points = points
        self.trendTint = trendTint
        self.trendTitle = trendTitle
        self.trendFormat = trendFormat
    }

    init(
        title: String,
        value: String,
        typography: MetricBlock.Typography = .standard,
        tone: Color = NomadTheme.primaryText,
        points: [MetricPoint]? = nil,
        trendTint: Color = NomadTheme.secondaryText,
        trendTitle: String = "Trend",
        trendFormat: @escaping (Double) -> String = { String(format: "%.0f", $0) }
    ) {
        self.init(
            title: title,
            reading: FormattedMetric(number: value),
            typography: typography,
            tone: tone,
            points: points,
            trendTint: trendTint,
            trendTitle: trendTitle,
            trendFormat: trendFormat
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MetricBlock(title: title, value: value, unit: unit, typography: typography, tone: tone)

            if let points {
                SparklineView(points: points, tint: trendTint, title: trendTitle, format: trendFormat)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct TimeTrackingAllocationBar: View {
    let presentation: TimeTrackingAllocationPresentation
    let isCompact: Bool

    private static let segmentSpacing: CGFloat = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let segments = presentation.segments
                let gaps = CGFloat(max(segments.count - 1, 0)) * Self.segmentSpacing
                let available = max(proxy.size.width - gaps, 0)

                HStack(spacing: Self.segmentSpacing) {
                    ForEach(segments) { segment in
                        Capsule(style: .continuous)
                            .fill(Self.tint(for: segment.kind))
                            .frame(width: max(available * segment.fraction, 3))
                            .help(segment.helpText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 8)
            .background(Capsule(style: .continuous).fill(NomadTheme.cardBorder.opacity(0.6)))
            .clipShape(Capsule(style: .continuous))
            .help(presentation.barHelpText)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(presentation.barHelpText)

            if presentation.legend.isEmpty == false {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: 12, alignment: .leading),
                        count: isCompact ? 1 : 2
                    ),
                    alignment: .leading,
                    spacing: 4
                ) {
                    ForEach(presentation.legend) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Circle()
                                .fill(Self.tint(for: entry.kind))
                                .frame(width: 6, height: 6)
                                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }

                            Text(entry.title)
                                .font(.caption)
                                .foregroundStyle(NomadTheme.secondaryText)
                                .lineLimit(2)

                            Spacer(minLength: 4)

                            Text(entry.durationText)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(NomadTheme.primaryText)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .help(entry.helpText)
                    }
                }

                if presentation.hiddenLegendCount > 0 {
                    Text("+\(presentation.hiddenLegendCount) more")
                        .font(.caption2)
                        .foregroundStyle(NomadTheme.tertiaryText)
                }
            }
        }
    }

    /// Allocated time uses a ramp of teal and neutral tones; time still waiting for an
    /// allocation is the one caution-colored segment.
    private static func tint(for kind: TimeTrackingAllocationPresentation.SegmentKind) -> Color {
        switch kind {
        case .pending:
            return NomadTheme.sand
        case let .allocated(toneIndex):
            let ramp: [Color] = [
                NomadTheme.teal,
                NomadTheme.teal.opacity(0.7),
                NomadTheme.teal.opacity(0.5),
                NomadTheme.secondaryText.opacity(0.55),
                NomadTheme.tertiaryText.opacity(0.55)
            ]
            return ramp[toneIndex % ramp.count]
        }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String
    let isCompact: Bool
    let compactLineLimit: Int
    let action: DetailRowAction?
    let help: String?

    init(
        label: String,
        value: String,
        isCompact: Bool = false,
        compactLineLimit: Int = 1,
        action: DetailRowAction? = nil,
        help: String? = nil
    ) {
        self.label = label
        self.value = value
        self.isCompact = isCompact
        self.compactLineLimit = compactLineLimit
        self.action = action
        self.help = help
    }

    var body: some View {
        content.help(ifPresent: help)
    }

    @ViewBuilder
    private var content: some View {
        if isCompact {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NomadTheme.tertiaryText)

                HStack(alignment: .top, spacing: 6) {
                    Text(value)
                        .font(.caption)
                        .foregroundStyle(NomadTheme.primaryText)
                        .lineLimit(compactLineLimit)
                        .minimumScaleFactor(0.8)
                        .truncationMode(compactLineLimit == 1 ? .middle : .tail)

                    Spacer(minLength: 0)

                    if let action {
                        DetailRowActionButton(action: action)
                    }
                }
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NomadTheme.tertiaryText)

                Spacer(minLength: 12)

                HStack(alignment: .top, spacing: 6) {
                    Text(value)
                        .font(.caption)
                        .foregroundStyle(NomadTheme.primaryText)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)

                    if let action {
                        DetailRowActionButton(action: action)
                    }
                }
            }
        }
    }
}

private struct DetailRowAction {
    let title: String
    let systemImage: String
    let isEnabled: Bool
    let action: () -> Void
}

private struct DetailRowActionButton: View {
    let action: DetailRowAction

    var body: some View {
        Button(action: action.action) {
            Image(systemName: action.systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(NomadTheme.actionIconForeground.opacity(action.isEnabled ? 1 : 0.55))
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(NomadTheme.inlineButtonBackground.opacity(action.isEnabled ? 1 : 0.7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(NomadTheme.cardBorder.opacity(action.isEnabled ? 1 : 0.7), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(action.isEnabled == false)
        .help(action.title)
        .accessibilityLabel(action.title)
    }
}

private struct CompactAlertRow: View {
    let title: String
    let summary: String
    let sourceName: String
    let count: Int?
    let tint: Color
    let symbolName: String
    var isCompact: Bool = false

    var body: some View {
        Group {
            if isCompact {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: symbolName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tint)
                            .frame(width: 18, alignment: .center)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(NomadTheme.primaryText)
                                .lineLimit(1)

                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(NomadTheme.secondaryText)
                                .lineLimit(2)
                        }
                    }

                    HStack(spacing: 8) {
                        Text(sourceName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(NomadTheme.tertiaryText)
                            .lineLimit(1)

                        if let count, count > 1 {
                            countBadge
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 28)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: symbolName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                        .frame(width: 18, alignment: .center)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NomadTheme.primaryText)

                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(NomadTheme.secondaryText)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(sourceName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(NomadTheme.tertiaryText)
                            .lineLimit(1)

                        if let count, count > 1 {
                            countBadge
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var countBadge: some View {
        Text("\(count ?? 0)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            )
    }
}

struct EmergencyHospitalRowModel: Identifiable, Equatable {
    let id: String
    let hospitalName: String
    let hospitalDetail: String
    let distanceText: String
    let ownershipTitle: String?
    let destination: EmergencyHospitalMapDestination?

    var hasPreviewMapAction: Bool {
        destination?.isCoordinateValid == true
    }

    var hasGoogleMapsAction: Bool {
        destination?.googleMapsURL != nil
    }

    var hasMapActions: Bool {
        hasPreviewMapAction || hasGoogleMapsAction
    }
}

/// A list row that opens the map preview when tapped (or Google Maps when the coordinates
/// are unusable) and keeps the secondary map actions in a trailing "more" menu.
private struct MapActionRow<Content: View>: View {
    let accessibilityTitle: String
    let hasPreviewMapAction: Bool
    let hasGoogleMapsAction: Bool
    let previewMapAction: () -> Void
    let openGoogleMapsAction: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if hasPreviewMapAction || hasGoogleMapsAction {
                Button(action: hasPreviewMapAction ? previewMapAction : openGoogleMapsAction) {
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityTitle)
                .accessibilityHint(hasPreviewMapAction ? "Shows the location on a map" : "Opens the location in Google Maps")

                moreMenu
            } else {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(NomadTheme.chartBackground.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(NomadTheme.cardBorder.opacity(0.9), lineWidth: 1)
                )
        )
    }

    private var moreMenu: some View {
        Menu {
            if hasPreviewMapAction {
                Button("Show map preview", systemImage: "map", action: previewMapAction)
            }

            if hasGoogleMapsAction {
                Button("Open in Google Maps", systemImage: "arrow.up.right.square", action: openGoogleMapsAction)
            }
        } label: {
            DashboardIconChip(systemImage: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More actions")
        .accessibilityLabel("More actions for \(accessibilityTitle)")
    }
}

private struct EmergencyHospitalRow: View {
    let model: EmergencyHospitalRowModel
    var isCompact: Bool = false
    let previewMapAction: (EmergencyHospitalMapDestination) -> Void
    let openGoogleMapsAction: (EmergencyHospitalMapDestination) -> Void

    var body: some View {
        MapActionRow(
            accessibilityTitle: "\(model.hospitalName), \(model.distanceText)",
            hasPreviewMapAction: model.hasPreviewMapAction,
            hasGoogleMapsAction: model.hasGoogleMapsAction,
            previewMapAction: { model.destination.map(previewMapAction) },
            openGoogleMapsAction: { model.destination.map(openGoogleMapsAction) }
        ) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.hospitalName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NomadTheme.primaryText)
                        .lineLimit(2)

                    if model.hospitalDetail.isEmpty == false {
                        Text(model.hospitalDetail)
                            .font(.caption2)
                            .foregroundStyle(NomadTheme.secondaryText)
                            .lineLimit(2)
                    }

                    if let ownershipTitle = model.ownershipTitle {
                        NeutralChip(title: ownershipTitle)
                    }
                }

                Spacer(minLength: 8)

                Text(model.distanceText)
                    .font(.system(size: isCompact ? 16 : 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(NomadTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}

/// A fact about the item (Public/Private hospital, Embassy/Consulate), not a status, so it gets a neutral chip.
struct NeutralChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(NomadTheme.tertiaryText)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(NomadTheme.tileBackground)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(NomadTheme.cardBorder.opacity(0.9), lineWidth: 1)
                    )
            )
    }
}

struct FuelPriceRowModel: Identifiable, Equatable {
    let id: FuelType
    let title: String
    let stationName: String
    let stationDetail: String
    /// The pump price in the locale's currency style ("1,429 €"); the unit is drawn apart.
    let priceValue: String
    let priceUnit = "/L"
    let updatedText: String?
    let stationDestination: FuelStationMapDestination?

    var hasPreviewMapAction: Bool {
        stationDestination?.isCoordinateValid == true
    }

    var hasGoogleMapsAction: Bool {
        stationDestination?.googleMapsURL != nil
    }

    var hasMapActions: Bool {
        hasPreviewMapAction || hasGoogleMapsAction
    }
}

private struct FuelPriceRow: View {
    let model: FuelPriceRowModel
    var isCompact: Bool = false
    let previewMapAction: (FuelStationMapDestination) -> Void
    let openGoogleMapsAction: (FuelStationMapDestination) -> Void

    var body: some View {
        MapActionRow(
            accessibilityTitle: "\(model.title), \(model.stationName), \(model.priceValue) per liter",
            hasPreviewMapAction: model.hasPreviewMapAction,
            hasGoogleMapsAction: model.hasGoogleMapsAction,
            previewMapAction: { model.stationDestination.map(previewMapAction) },
            openGoogleMapsAction: { model.stationDestination.map(openGoogleMapsAction) }
        ) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NomadTheme.tertiaryText)

                    Text(model.stationName)
                        .font(.caption)
                        .foregroundStyle(NomadTheme.primaryText)
                        .lineLimit(2)

                    if isCompact == false {
                        Text(model.stationDetail)
                            .font(.caption2)
                            .foregroundStyle(NomadTheme.secondaryText)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    (Text(model.priceValue)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(NomadTheme.primaryText)
                        + Text(model.priceUnit)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(NomadTheme.secondaryText))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if let updatedText = model.updatedText {
                        Text(updatedText)
                            .font(.caption2)
                            .foregroundStyle(NomadTheme.tertiaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
        }
        .help(ifPresent: isCompact ? model.stationDetail : nil)
    }
}

private enum DashboardScrollCoordinateSpace {
    static let name = "DashboardPanelScrollSpace"
}

private struct FuelCardFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect {
        .null
    }

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let nextFrame = nextValue()
        if nextFrame.isNull == false {
            value = nextFrame
        }
    }
}

enum FuelCardVisualMode: Equatable {
    case animatedCamper
    case ambient
    case staticScene
}

struct FuelBackdropAnimationState: Equatable {
    let visibilityRatio: Double
    let isAnimating: Bool
}

func fuelCardVisibilityRatio(frame: CGRect, viewportHeight: CGFloat) -> Double {
    guard frame.isNull == false, frame.height > 0, viewportHeight > 0 else {
        return 0
    }

    let visibleMinY = max(frame.minY, 0)
    let visibleMaxY = min(frame.maxY, viewportHeight)
    let visibleHeight = max(visibleMaxY - visibleMinY, 0)
    return min(max(visibleHeight / frame.height, 0), 1)
}

func fuelBackdropAnimationState(
    frame: CGRect,
    viewportHeight: CGFloat,
    visualMode: FuelCardVisualMode,
    reduceMotion: Bool,
    threshold: Double = 0.35
) -> FuelBackdropAnimationState {
    let visibilityRatio = fuelCardVisibilityRatio(frame: frame, viewportHeight: viewportHeight)
    return FuelBackdropAnimationState(
        visibilityRatio: visibilityRatio,
        isAnimating: visualMode == .animatedCamper && reduceMotion == false && visibilityRatio >= threshold
    )
}

private struct EmergencyCareSectionView: View {
    let presentation: EmergencyCareSectionPresentation
    let widthMode: DashboardCardWidthMode
    let accessory: AnyView?
    let collapse: DashboardCardCollapse
    let openSettingsAction: () -> Void
    let previewMapAction: (EmergencyHospitalMapDestination) -> Void
    let openGoogleMapsAction: (EmergencyHospitalMapDestination) -> Void

    var body: some View {
        DashboardCard(
            title: DashboardCardID.emergencyCare.displayTitle,
            subtitle: presentation.subtitle,
            isSubtitleSelectable: presentation.emergencyNumbers != nil,
            badge: presentation.badge,
            accessory: accessory,
            collapse: collapse,
            isCompact: widthMode == .narrow
        ) {
            if presentation.rows.isEmpty == false {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(presentation.rows) { row in
                        EmergencyHospitalRow(
                            model: row,
                            isCompact: widthMode == .narrow,
                            previewMapAction: previewMapAction,
                            openGoogleMapsAction: openGoogleMapsAction
                        )
                    }
                }
            } else {
                WeatherEmptyState(
                    title: presentation.emptyTitle,
                    systemImage: presentation.emptySystemImage,
                    message: presentation.emptyMessage,
                    actionTitle: presentation.emptyActionTitle,
                    action: presentation.isActionable ? openSettingsAction : nil
                )
            }
        }
    }
}

struct LocalInfoSectionView: View {
    let presentation: LocalInfoSectionPresentation
    let widthMode: DashboardCardWidthMode
    let accessory: AnyView?
    let collapse: DashboardCardCollapse
    let openSettingsAction: () -> Void

    var body: some View {
        DashboardCard(
            title: DashboardCardID.localInfo.displayTitle,
            subtitle: presentation.subtitle,
            badge: presentation.badge,
            accessory: accessory,
            collapse: collapse,
            isCompact: widthMode == .narrow
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if presentation.rows.isEmpty {
                    WeatherEmptyState(
                        title: presentation.emptyTitle,
                        systemImage: presentation.emptySystemImage,
                        message: presentation.emptyMessage
                    )

                    if let emptyActionTitle = presentation.emptyActionTitle {
                        Button(emptyActionTitle, action: openSettingsAction)
                            .buttonStyle(.dashboardInline)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(presentation.rows) { row in
                            LocalInfoRowView(row: row, isCompact: widthMode == .narrow)
                        }
                    }
                }

                if presentation.rhythm.isEmpty == false {
                    Divider()
                        .overlay(NomadTheme.cardBorder.opacity(0.9))

                    LocalRhythmSectionView(rows: presentation.rhythm)
                }

                if let note = presentation.note {
                    Divider()
                        .overlay(NomadTheme.cardBorder.opacity(0.9))

                    Text(note)
                        .font(.caption)
                        .foregroundStyle(NomadTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let sourceLine = presentation.sourceLine {
                    Text(sourceLine)
                        .font(.caption2)
                        .foregroundStyle(NomadTheme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// "Local rhythm": the periods that change daily life in the country, with their dates and what to expect.
private struct LocalRhythmSectionView: View {
    let rows: [LocalRhythmRowModel]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LocalRhythmRowModel.sectionTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NomadTheme.tertiaryText)

            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(row.name)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(NomadTheme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        NeutralChip(title: row.timing)
                            .fixedSize()
                    }

                    Text(row.dates)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(NomadTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(row.guidance)
                        .font(.caption)
                        .foregroundStyle(NomadTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Title on the left, the answer on the right with what it refers to right under it.
private struct LocalInfoRowView: View {
    let row: LocalInfoRowModel
    let isCompact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if isCompact {
                    VStack(alignment: .leading, spacing: 3) {
                        titleText
                        answer(alignment: .leading)
                    }
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        titleText

                        Spacer(minLength: 12)

                        answer(alignment: .trailing)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(ifPresent: row.help)

            if let comparison = row.homeComparison {
                homeComparison(comparison)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func homeComparison(_ comparison: LocalInfoRowModel.HomeComparison) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(comparison.lines, id: \.self) { line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(NomadTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(comparison.caption)
                .font(.caption2)
                .foregroundStyle(NomadTheme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var titleText: some View {
        Text(row.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(NomadTheme.tertiaryText)
            .lineLimit(1)
            .fixedSize()
    }

    private func answer(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                valueText

                if let badge = row.badge {
                    BadgeView(badge: badge, isCompact: isCompact)
                }
            }

            if row.detail.isEmpty == false {
                Text(row.detail)
                    .font(.caption)
                    .foregroundStyle(NomadTheme.secondaryText)
                    .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelectionIfNeeded(row.isValueSelectable)
            }
        }
    }

    @ViewBuilder
    private var valueText: some View {
        let text = Text(row.value)
            .font(.system(size: isCompact ? 14 : 15, weight: .semibold, design: .rounded))
            .foregroundStyle(NomadTheme.primaryText)
            .multilineTextAlignment(isCompact ? .leading : .trailing)
            .fixedSize(horizontal: false, vertical: true)

        if row.isValueSelectable {
            text.textSelection(.enabled)
        } else {
            text
        }
    }
}

private struct FuelPricesSectionView: View {
    let presentation: FuelPricesSectionPresentation
    let widthMode: DashboardCardWidthMode
    let viewportHeight: CGFloat
    let accessory: AnyView?
    let collapse: DashboardCardCollapse
    let openSettingsAction: () -> Void
    let previewMapAction: (FuelStationMapDestination) -> Void
    let openGoogleMapsAction: (FuelStationMapDestination) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.nomadLowImpact) private var lowImpact
    @State private var cardFrame: CGRect = .null

    var body: some View {
        let animationState = fuelBackdropAnimationState(
            frame: cardFrame,
            viewportHeight: viewportHeight,
            visualMode: presentation.visualMode,
            reduceMotion: reduceMotion || lowImpact
        )

        DashboardCard(
            title: DashboardCardID.fuelPrices.displayTitle,
            subtitle: presentation.subtitle,
            badge: presentation.badge,
            accessory: accessory,
            collapse: collapse,
            backgroundDecoration: AnyView(
                FuelCardBackdrop(
                    visualMode: presentation.visualMode,
                    badgeTint: presentation.badge.tint,
                    isAnimating: animationState.isAnimating,
                    isCompact: widthMode == .narrow
                )
                .opacity(FuelCardBackdrop.restingOpacity)
            ),
            isCompact: widthMode == .narrow
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if presentation.rows.isEmpty == false {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(presentation.rows) { row in
                            FuelPriceRow(
                                model: row,
                                isCompact: widthMode == .narrow,
                                previewMapAction: previewMapAction,
                                openGoogleMapsAction: openGoogleMapsAction
                            )
                        }
                    }
                } else {
                    WeatherEmptyState(
                        title: presentation.emptyTitle,
                        systemImage: presentation.emptySystemImage,
                        message: presentation.emptyMessage,
                        actionTitle: presentation.emptyActionTitle,
                        action: presentation.isActionable ? openSettingsAction : nil
                    )
                }

                if widthMode != .narrow, let note = presentation.note {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(NomadTheme.tertiaryText)
                }
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .preference(
                        key: FuelCardFramePreferenceKey.self,
                        value: geometry.frame(in: .named(DashboardScrollCoordinateSpace.name))
                    )
            }
        )
        .onPreferenceChange(FuelCardFramePreferenceKey.self) { frame in
            cardFrame = frame
        }
    }
}

private struct FuelCardBackdrop: View {
    /// The scene is atmosphere, not content: at half strength text never sits on visible blobs.
    static let restingOpacity = 0.5
    /// Below the card header the art fades to this share of `restingOpacity`; 0 removes it, so it
    /// never sits behind the station rows' text.
    static let rowAreaShare = 0.0
    private static let headerHeight: CGFloat = 64
    private static let fadeLength: CGFloat = 24

    let visualMode: FuelCardVisualMode
    let badgeTint: Color
    let isAnimating: Bool
    let isCompact: Bool

    @State private var lastResolvedPhase = 0.18

    var body: some View {
        GeometryReader { geometry in
            Group {
                if isAnimating {
                    TimelineView(.animation) { context in
                        let phase = context.date.timeIntervalSinceReferenceDate
                        backdropContents(size: geometry.size, phase: phase)
                            .onAppear {
                                lastResolvedPhase = phase
                            }
                            .onChange(of: phase) { _, newPhase in
                                lastResolvedPhase = newPhase
                            }
                    }
                } else {
                    backdropContents(size: geometry.size, phase: resolvedStaticPhase)
                }
            }
            .mask(rowAreaFade(height: geometry.size.height))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func rowAreaFade(height: CGFloat) -> some View {
        let height = max(height, 1)
        let solid = min(Self.headerHeight / height, 1)
        let faded = min((Self.headerHeight + Self.fadeLength) / height, 1)

        return LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: solid),
                .init(color: .black.opacity(Self.rowAreaShare), location: faded),
                .init(color: .black.opacity(Self.rowAreaShare), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    @ViewBuilder
    private func backdropContents(size: CGSize, phase: Double) -> some View {
        let metrics = FuelBackdropMetrics(size: size, isCompact: isCompact)

        ZStack {
            FuelCardGlowLayer(phase: phase, visualMode: visualMode, badgeTint: badgeTint, metrics: metrics)

            VStack {
                Spacer(minLength: 0)

                ZStack(alignment: .bottomLeading) {
                    FuelRoadScene(phase: phase, visualMode: visualMode, metrics: metrics)

                    if visualMode == .animatedCamper {
                        FuelCamperTrack(phase: phase, metrics: metrics)
                            .transition(.opacity)
                    }
                }
                .frame(width: metrics.roadWidth, height: metrics.roadHeight)
                .frame(maxWidth: .infinity)
            }

            FuelAtmosphereLayer(phase: phase, visualMode: visualMode, metrics: metrics)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .mask(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    private var resolvedStaticPhase: Double {
        switch visualMode {
        case .animatedCamper:
            lastResolvedPhase
        case .ambient, .staticScene:
            0.18
        }
    }
}

private struct FuelBackdropMetrics {
    let width: CGFloat
    let height: CGFloat
    let roadWidth: CGFloat
    let roadHeight: CGFloat
    let laneMarkerCount: Int
    let laneMarkerSpacing: CGFloat
    let camperInset: CGFloat

    init(size: CGSize, isCompact: Bool) {
        width = max(size.width, 1)
        height = max(size.height, 1)
        roadWidth = width * 0.94
        roadHeight = max(height * (isCompact ? 0.24 : 0.34), isCompact ? 54 : 72)
        laneMarkerSpacing = max(12, roadWidth * 0.032)
        laneMarkerCount = max(isCompact ? 4 : 7, Int((roadWidth * 0.72) / (18 + laneMarkerSpacing)))
        camperInset = roadWidth * 0.08
    }
}

private struct FuelCardGlowLayer: View {
    let phase: Double
    let visualMode: FuelCardVisualMode
    let badgeTint: Color
    let metrics: FuelBackdropMetrics

    var body: some View {
        ZStack {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            NomadTheme.fuelGlow.opacity(visualMode == .staticScene ? 0.08 : 0.12),
                            badgeTint.opacity(0.05),
                            .clear
                        ],
                        center: .center,
                        startRadius: 6,
                        endRadius: max(metrics.width * 0.34, 120)
                    )
                )
                .frame(width: max(metrics.width * 0.58, 180), height: max(metrics.height * 0.26, 88))
                .offset(x: -metrics.width * 0.12, y: metrics.height * 0.08)
                .blur(radius: 10)

            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            badgeTint.opacity(visualMode == .ambient ? 0.05 : 0.07),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: max(metrics.width * 0.82, 220), height: max(metrics.height * 0.15, 52))
                .offset(x: CGFloat(sin(phase / 4.7)) * metrics.width * 0.08, y: metrics.height * 0.02)
                .blur(radius: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FuelAtmosphereLayer: View {
    let phase: Double
    let visualMode: FuelCardVisualMode
    let metrics: FuelBackdropMetrics

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                let drift = visualMode == .staticScene ? 0 : sin(phase / (6.5 + Double(index)))
                let xFractions: [CGFloat] = [0.18, 0.5, 0.82]
                let capsuleWidth: CGFloat = max(22, metrics.width * (0.11 - CGFloat(index) * 0.018))
                let offsetX: CGFloat = metrics.width * (xFractions[index] - 0.5) + CGFloat(drift) * metrics.width * 0.04
                let offsetY: CGFloat = -metrics.height * 0.15 + CGFloat(index) * 10
                Capsule(style: .continuous)
                    .fill(index == 1 ? NomadTheme.teal.opacity(0.06) : NomadTheme.fuelGlow.opacity(0.05))
                    .frame(width: capsuleWidth, height: 7)
                    .rotationEffect(.degrees(Double(index * 6) - 7))
                    .offset(x: offsetX, y: offsetY)
                    .blur(radius: 1.2)
            }
        }
    }
}

private struct FuelRoadScene: View {
    let phase: Double
    let visualMode: FuelCardVisualMode
    let metrics: FuelBackdropMetrics

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            .clear,
                            NomadTheme.fuelRoad.opacity(0.38),
                            NomadTheme.fuelRoad.opacity(0.62)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: metrics.roadWidth, height: metrics.roadHeight)
                .offset(y: metrics.roadHeight * 0.2)

            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            .clear,
                            NomadTheme.cardBorder.opacity(0.22),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: metrics.roadWidth * 0.28, height: 3)
                .offset(x: laneOffset, y: -metrics.roadHeight * 0.24)
                .blur(radius: 0.6)

            HStack(spacing: metrics.laneMarkerSpacing) {
                ForEach(0..<metrics.laneMarkerCount, id: \.self) { _ in
                    Capsule(style: .continuous)
                        .fill(NomadTheme.cardBorder.opacity(0.24))
                        .frame(width: 18, height: 2)
                }
            }
            .frame(width: metrics.roadWidth * 0.84)
            .offset(x: laneOffset * 0.8, y: -metrics.roadHeight * 0.24)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            .clear,
                            NomadTheme.cardBackground.opacity(0.08),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: metrics.roadWidth, height: metrics.roadHeight * 0.32)
                .offset(y: -metrics.roadHeight * 0.6)
        }
        .frame(width: metrics.roadWidth, height: metrics.roadHeight)
        .mask(horizontalSoftMask)
    }

    private var laneOffset: CGFloat {
        guard visualMode != .staticScene else {
            return 0
        }

        let loop = phase.truncatingRemainder(dividingBy: 8.5) / 8.5
        return CGFloat((loop - 0.5) * Double(metrics.roadWidth * 0.42))
    }

    private var horizontalSoftMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.08),
                .init(color: .black, location: 0.92),
                .init(color: .clear, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

private struct FuelCamperTrack: View {
    let phase: Double
    let metrics: FuelBackdropMetrics

    var body: some View {
        let loopDuration = 12.4
        let loop = phase.truncatingRemainder(dividingBy: loopDuration) / loopDuration
        let travelWidth = max(metrics.roadWidth - (metrics.camperInset * 2) - 66, 1)
        let x = metrics.camperInset + travelWidth * CGFloat(loop)
        let bounce = sin(loop * .pi * 10) * 1.2

        FuelCamperVan()
            .frame(width: 66, height: 32)
            .offset(x: x, y: CGFloat(-10 + bounce))
            .shadow(color: NomadTheme.primaryText.opacity(0.08), radius: 6, y: 2)
            .frame(width: metrics.roadWidth, height: metrics.roadHeight, alignment: .leading)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.1),
                        .init(color: .black, location: 0.9),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
    }
}

private struct FuelCamperVan: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            FuelCamperShadow()
                .offset(y: 9)

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            NomadTheme.cardBackground.opacity(0.92),
                            NomadTheme.cardBackground.opacity(0.62)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(NomadTheme.cardBorder.opacity(0.7), lineWidth: 1)
                )
                .frame(width: 42, height: 18)
                .offset(x: 12, y: -7)

            FuelCamperCabShape()
                .fill(
                    LinearGradient(
                        colors: [
                            NomadTheme.fuelGlow.opacity(0.95),
                            NomadTheme.sand.opacity(0.82)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 24, height: 18)
                .offset(x: 34, y: -7)

            FuelCamperStripe()
                .fill(
                    LinearGradient(
                        colors: [NomadTheme.teal.opacity(0.78), NomadTheme.coral.opacity(0.52)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 30, height: 4)
                .offset(x: 16, y: -1)

            HStack(spacing: 6) {
                Circle()
                    .fill(NomadTheme.primaryText.opacity(0.9))
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(NomadTheme.cardBackground.opacity(0.85), lineWidth: 1.8)
                    )
                Circle()
                    .fill(NomadTheme.primaryText.opacity(0.9))
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(NomadTheme.cardBackground.opacity(0.85), lineWidth: 1.8)
                    )
            }
            .offset(x: 18, y: 6)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(NomadTheme.teal.opacity(0.22))
                .frame(width: 12, height: 7)
                .offset(x: 18, y: -10)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(NomadTheme.teal.opacity(0.18))
                .frame(width: 8, height: 7)
                .offset(x: 41, y: -10)

            Circle()
                .fill(NomadTheme.fuelGlow.opacity(0.42))
                .frame(width: 3, height: 3)
                .offset(x: 56, y: -2)
                .blur(radius: 0.6)
        }
        .frame(width: 66, height: 32)
    }
}

private struct FuelCamperShadow: View {
    var body: some View {
        Capsule(style: .continuous)
            .fill(NomadTheme.primaryText.opacity(0.12))
            .frame(width: 38, height: 6)
            .blur(radius: 2)
    }
}

private struct FuelCamperCabShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.04, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.04, y: rect.minY + rect.height * 0.42))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.4, y: rect.minY + rect.height * 0.08),
            control: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.1)
        )
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.16, y: rect.minY + rect.height * 0.08))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.44),
            control: CGPoint(x: rect.maxX - rect.width * 0.04, y: rect.minY + rect.height * 0.1)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct FuelCamperStripe: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY - 1),
            control: CGPoint(x: rect.midX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct TravelAlertRowModel: Identifiable, Equatable {
    let id: TravelAlertKind
    let title: String
    let statusLabel: String
    let impactText: String
    let summary: String
    let detailSummary: String?
    let freshnessText: String
    let metadataText: String
    let sourceName: String
    let sourceURL: URL?
    let count: Int?
    let severity: TravelAlertSeverity
    let tint: Color
    let symbolName: String
    let status: TravelAlertSignalStatus

    /// The uppercase impact line only earns its place when it says something the status chip
    /// does not: "Exercise caution" next to a "Caution" chip, or "Last known signal" next to a
    /// "Stale" chip, just repeats it.
    var showsImpactText: Bool {
        status == .ready && (severity == .info || severity >= .warning)
    }

    static func == (lhs: TravelAlertRowModel, rhs: TravelAlertRowModel) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.statusLabel == rhs.statusLabel
            && lhs.impactText == rhs.impactText
            && lhs.summary == rhs.summary
            && lhs.detailSummary == rhs.detailSummary
            && lhs.freshnessText == rhs.freshnessText
            && lhs.metadataText == rhs.metadataText
            && lhs.sourceName == rhs.sourceName
            && lhs.sourceURL == rhs.sourceURL
            && lhs.count == rhs.count
            && lhs.severity == rhs.severity
            && lhs.symbolName == rhs.symbolName
            && lhs.status == rhs.status
    }
}

private enum TravelAlertCompactDisplayRow: Identifiable {
    case alert(TravelAlertRowModel)
    case overflow(count: Int)

    var id: String {
        switch self {
        case let .alert(row):
            row.id.rawValue
        case let .overflow(count):
            "overflow-\(count)"
        }
    }
}

struct TravelAlertsCardPresentation: Equatable {
    struct Notice: Equatable {
        let text: String
        let symbolName: String
    }

    let badge: TravelAlertsBadgePresentation
    let rows: [TravelAlertRowModel]
    let showsAllClearRow: Bool
    /// "Updated 12 Oct · may be outdated": shown beside the level badge when any signal is stale.
    let staleNotice: Notice?
    /// "Some sources unavailable": shown when a source could not be reached at all.
    let limitedNotice: Notice?
    /// Whether each signal block repeats its level in a chip. With a single ready signal the
    /// header badge already says it.
    let showsSignalChips: Bool

    var notices: [Notice] {
        [staleNotice, limitedNotice].compactMap(\.self)
    }

    init(preferences: TravelAlertPreferences, snapshot: TravelAlertsSnapshot?) {
        guard preferences.enabledKinds.isEmpty == false else {
            badge = .off
            rows = []
            showsAllClearRow = false
            staleNotice = nil
            limitedNotice = nil
            showsSignalChips = true
            return
        }

        guard let snapshot else {
            badge = .checking
            rows = []
            showsAllClearRow = false
            staleNotice = nil
            limitedNotice = nil
            showsSignalChips = true
            return
        }

        staleNotice = Self.staleNotice(for: snapshot, enabledKinds: preferences.enabledKinds)
        limitedNotice = snapshot.hasUnavailableStates
            ? Notice(text: "Some sources unavailable", symbolName: "exclamationmark.triangle.fill")
            : nil

        rows = preferences.enabledKinds.compactMap { kind in
            guard let state = snapshot.state(for: kind) else {
                return nil
            }

            return TravelAlertRowModel(state: state)
        }

        showsAllClearRow = snapshot.allResolvedClear
        let resolvedBadge = TravelAlertsBadgePresentation.resolve(for: snapshot)
        badge = resolvedBadge
        showsSignalChips = !(rows.count == 1
            && rows[0].status == .ready
            && resolvedBadge == .severity(rows[0].severity))
    }

    private static func staleNotice(for snapshot: TravelAlertsSnapshot, enabledKinds: [TravelAlertKind]) -> Notice? {
        let staleStates = snapshot.states.filter { enabledKinds.contains($0.kind) && $0.status == .stale }
        guard staleStates.isEmpty == false else {
            return nil
        }

        // The oldest good refresh is the one that bounds how outdated the card can be.
        let text = if let oldest = staleStates.compactMap(\.lastSuccessAt).min() {
            "Updated \(travelAlertDateText(oldest)) · may be outdated"
        } else {
            "May be outdated"
        }

        return Notice(text: text, symbolName: "clock.arrow.circlepath")
    }
}

enum TravelAlertsBadgePresentation: Equatable {
    case off
    case checking
    case limited
    case stale
    case severity(TravelAlertSeverity)

    var pillBadge: PillBadge {
        switch self {
        case .off:
            PillBadge(title: "Off", symbolName: "bell.slash.fill", tint: NomadTheme.primaryText)
        case .checking:
            PillBadge(title: "Checking", symbolName: "clock.fill", tint: NomadTheme.secondaryText)
        case .limited:
            PillBadge(title: "Limited", symbolName: "exclamationmark.triangle.fill", tint: NomadTheme.sand)
        case .stale:
            PillBadge(title: "Stale", symbolName: "clock.arrow.circlepath", tint: NomadTheme.primaryText)
        case let .severity(severity):
            PillBadge(title: severity.badgeTitle, symbolName: severity.symbolName, tint: severity.tint)
        }
    }

    /// The header badge names the highest alert level. Staleness and unavailable sources are
    /// reported next to it (see `TravelAlertsCardPresentation`) and only take the badge over
    /// when no level is known at all.
    fileprivate static func resolve(for snapshot: TravelAlertsSnapshot) -> TravelAlertsBadgePresentation {
        if let highestSeverity = snapshot.states.compactMap(\.highestSeverity).max() {
            return .severity(highestSeverity)
        }

        if snapshot.hasStaleStates {
            return .stale
        }

        if snapshot.hasUnavailableStates {
            return .limited
        }

        return .checking
    }
}

private extension TravelAlertRowModel {
    init(state: TravelAlertSignalState) {
        let title = state.kind.displayName
        let sourceName = state.signal?.sourceName ?? state.sourceName
        let statusLabel = Self.statusLabel(for: state)
        let impactText = Self.impactText(for: state)
        let freshnessText = Self.freshnessText(for: state)

        switch state.status {
        case .checking:
            self.init(
                id: state.kind,
                title: title,
                statusLabel: statusLabel,
                impactText: impactText,
                summary: "Checking alerts…",
                detailSummary: nil,
                freshnessText: freshnessText,
                metadataText: [sourceName, freshnessText].filter { $0.isEmpty == false }.joined(separator: " · "),
                sourceName: sourceName,
                sourceURL: nil,
                count: nil,
                severity: .info,
                tint: NomadTheme.secondaryText,
                symbolName: "clock.fill",
                status: .checking
            )
        case .ready:
            let signal = state.signal
            self.init(
                id: state.kind,
                title: title,
                statusLabel: statusLabel,
                impactText: impactText,
                summary: signal?.summary ?? "No current alerts.",
                detailSummary: signal?.detailSummary,
                freshnessText: freshnessText,
                metadataText: [sourceName, freshnessText].filter { $0.isEmpty == false }.joined(separator: " · "),
                sourceName: sourceName,
                sourceURL: signal?.sourceURL,
                count: signal?.itemCount,
                severity: signal?.severity ?? .clear,
                tint: (signal?.severity ?? .clear).tint,
                symbolName: (signal?.severity ?? .clear).symbolName,
                status: .ready
            )
        case .stale:
            let signal = state.signal
            let severity = signal?.severity ?? .info
            let summary = signal.map { "Last known: \($0.summary)" } ?? "Last known alert status unavailable."
            self.init(
                id: state.kind,
                title: title,
                statusLabel: statusLabel,
                impactText: impactText,
                summary: summary,
                detailSummary: nil,
                freshnessText: freshnessText,
                metadataText: [sourceName, freshnessText].filter { $0.isEmpty == false }.joined(separator: " · "),
                sourceName: sourceName,
                sourceURL: signal?.sourceURL,
                count: signal?.itemCount,
                severity: severity,
                tint: severity.tint,
                symbolName: severity.symbolName,
                status: .stale
            )
        case .unavailable:
            self.init(
                id: state.kind,
                title: title,
                statusLabel: statusLabel,
                impactText: impactText,
                summary: state.diagnosticSummary ?? state.reason?.summary ?? "Source unavailable",
                detailSummary: nil,
                freshnessText: freshnessText,
                metadataText: [sourceName, freshnessText].filter { $0.isEmpty == false }.joined(separator: " · "),
                sourceName: sourceName,
                sourceURL: nil,
                count: nil,
                severity: .info,
                tint: NomadTheme.sand,
                symbolName: "exclamationmark.triangle.fill",
                status: .unavailable
            )
        }
    }

    private static func statusLabel(for state: TravelAlertSignalState) -> String {
        switch state.status {
        case .checking:
            "Checking"
        case .ready:
            state.signal?.severity.badgeTitle ?? "Ready"
        case .stale:
            "Stale"
        case .unavailable:
            "Unavailable"
        }
    }

    private static func impactText(for state: TravelAlertSignalState) -> String {
        switch state.status {
        case .checking:
            "Live check"
        case .ready:
            switch state.signal?.severity {
            case .clear:
                "No elevated signal"
            case .info:
                "Nearby watch"
            case .caution:
                "Exercise caution"
            case .warning:
                "Review before travel"
            case .critical:
                "Immediate attention"
            case nil:
                "Signal ready"
            }
        case .stale:
            "Last known signal"
        case .unavailable:
            "Source issue"
        }
    }

    private static func freshnessText(for state: TravelAlertSignalState) -> String {
        switch state.status {
        case .checking:
            "Refreshing now"
        case .ready:
            (state.signal?.updatedAt).map { "Updated \(travelAlertDateText($0))" } ?? "Updated recently"
        case .stale:
            state.lastSuccessAt.map { "Last good refresh \(travelAlertDateText($0))" } ?? "Last good refresh unavailable"
        case .unavailable:
            state.lastAttemptedAt.map { "Checked \(travelAlertDateText($0))" } ?? "Check attempted"
        }
    }
}

private struct TravelAlertSignalRow: View {
    let row: TravelAlertRowModel
    var showsChip = true
    var isCompact: Bool = false
    var openSourceAction: (URL) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 8 : 10) {
            HStack(alignment: .top, spacing: 12) {
                Text(row.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NomadTheme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if showsChip {
                    BadgeView(
                        badge: PillBadge(
                            title: row.statusLabel,
                            symbolName: row.symbolName,
                            tint: row.tint
                        )
                    )
                }
            }

            if row.showsImpactText {
                Text(row.impactText.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(row.tint.opacity(0.92))
                    .tracking(0.4)
            }

            Text(row.summary)
                .font(isCompact ? .caption : .caption)
                .foregroundStyle(NomadTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let detailSummary = detailSummaryText {
                Text(detailSummary)
                    .font(.caption)
                    .foregroundStyle(NomadTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let sourceURL = advisorySourceURL {
                Button("More details") {
                    openSourceAction(sourceURL)
                }
                .buttonStyle(.dashboardInline)
            }

            HStack(alignment: .center, spacing: 8) {
                Text(row.metadataText)
                    .font(.caption2)
                    .foregroundStyle(NomadTheme.tertiaryText)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if let count = row.count, count > 1 {
                    Text("\(count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(row.tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(row.tint.opacity(0.12))
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(isCompact ? 12 : 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(row.tint.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(row.tint.opacity(0.14), lineWidth: 1)
        )
    }

    private var detailSummaryText: String? {
        guard let detailSummary = row.detailSummary?.nilIfEmpty else {
            return nil
        }

        return detailSummary == row.summary ? nil : detailSummary
    }

    private var advisorySourceURL: URL? {
        guard row.id == .advisory else {
            return nil
        }

        return row.sourceURL
    }
}

private struct BadgeView: View {
    let badge: PillBadge
    var isCompact: Bool = false

    var body: some View {
        if isCompact {
            Image(systemName: badge.symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(badge.tint)
                .frame(width: 28, height: 28)
                .background(
                    Capsule(style: .continuous)
                        .fill(badge.tint.opacity(0.12))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(badge.tint.opacity(0.18), lineWidth: 1)
                )
                .help(badge.title)
                .accessibilityLabel(badge.title)
        } else {
            Label(badge.title, systemImage: badge.symbolName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(badge.tint)
                .background(
                    Capsule(style: .continuous)
                        .fill(badge.tint.opacity(0.12))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(badge.tint.opacity(0.18), lineWidth: 1)
                )
        }
    }
}

struct WeatherEmptyState: View {
    let title: String
    let systemImage: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 22))
                .foregroundStyle(NomadTheme.tertiaryText)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NomadTheme.primaryText)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(NomadTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.dashboardInline)
                        .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(NomadTheme.chartBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(NomadTheme.cardBorder.opacity(0.9), lineWidth: 1)
                )
        )
    }
}

struct WeatherSectionPresentation {
    let badge: PillBadge
    let subtitle: String
    let emptyTitle: String
    let emptySystemImage: String
    let emptyMessage: String

    init(
        settings: AppSettings,
        snapshot: DashboardSnapshot,
        weatherAvailabilityExplanation: String?,
        locationStatusDetail: String?
    ) {
        if let weather = snapshot.weather {
            badge = PillBadge(title: "Live", symbolName: "cloud.sun.fill", tint: NomadTheme.teal)
            // The condition itself sits next to the big temperature; the subtitle says how fresh it is.
            subtitle = "Updated \(NomadFormatters.compactClockTime(weather.fetchedAt))"
            emptyTitle = ""
            emptySystemImage = "cloud.sun.fill"
            emptyMessage = ""
            return
        }

        if let weatherAvailabilityExplanation {
            badge = PillBadge(title: "Build Issue", symbolName: "hammer.fill", tint: NomadTheme.sand)
            subtitle = "WeatherKit unavailable in this build"
            emptyTitle = "WeatherKit Unavailable"
            emptySystemImage = "hammer.fill"
            emptyMessage = weatherAvailabilityExplanation
            return
        }

        if snapshot.appState.issues.contains(.weatherLocationRequired) {
            badge = PillBadge(title: "Location Needed", symbolName: "location.slash.fill", tint: NomadTheme.sand)
            subtitle = "Location permission required"
            emptyTitle = "Location Needed"
            emptySystemImage = "location.slash.fill"
            emptyMessage = locationStatusDetail ?? "Allow current location to load local weather."
            return
        }

        badge = PillBadge(title: "Unavailable", symbolName: "cloud.slash.fill", tint: NomadTheme.primaryText)
        subtitle = "Weather data unavailable"

        if settings.useCurrentLocationForWeather, let locationStatusDetail {
            emptyTitle = "Unavailable"
            emptySystemImage = "cloud.slash.fill"
            emptyMessage = locationStatusDetail
        } else {
            emptyTitle = "Unavailable"
            emptySystemImage = "cloud.slash.fill"
            emptyMessage = "Weather data is not available yet."
        }
    }
}

struct WeatherForecastPresentation {
    /// The strip of upcoming hours. Always visible, whatever the disclosure state.
    let hourlySlots: [WeatherHourlyForecastSlotPresentation]
    let dailyRows: [WeatherDaySummary]
    /// Whether the 7-day outlook is expanded. Only the outlook folds away.
    let isForecastExpanded: Bool
    /// Whether the 7-day outlook disclosure is offered (wide cards with daily data).
    let showsForecastDisclosure: Bool
    let shouldShowTomorrowSummary: Bool

    init(settings: AppSettings, weather: WeatherSnapshot?, widthMode: DashboardCardWidthMode) {
        guard let weather else {
            hourlySlots = []
            dailyRows = []
            isForecastExpanded = false
            showsForecastDisclosure = false
            shouldShowTomorrowSummary = false
            return
        }

        hourlySlots = weather.hourlyForecastSlots.enumerated().map { index, slot in
            WeatherHourlyForecastSlotPresentation(index: index, slot: slot, referenceDate: weather.fetchedAt)
        }
        dailyRows = weather.dailyForecast
        let canShowOutlook = widthMode != .narrow
        showsForecastDisclosure = canShowOutlook && dailyRows.isEmpty == false
        isForecastExpanded = showsForecastDisclosure && settings.weatherForecastExpanded
        shouldShowTomorrowSummary = weather.tomorrow != nil && (showsForecastDisclosure == false || isForecastExpanded == false)
    }
}

struct WeatherHourlyForecastSlotPresentation: Identifiable, Equatable {
    let id: String
    let title: String
    let symbolName: String
    let temperatureValue: String
    /// Rain chance and wind as one string, for hover and accessibility.
    let detailValue: String
    /// The same detail split into the lines a chip shows, so a value never wraps mid-way.
    let detailLines: [String]

    init(index: Int, slot: WeatherHourlyForecastSlot, referenceDate: Date) {
        id = "\(index)-\(slot.date.timeIntervalSinceReferenceDate)"
        let hourOffset = max(0, Int((slot.date.timeIntervalSince(referenceDate) / 3_600).rounded()))
        title = "+\(hourOffset)h"
        symbolName = slot.symbolName
        temperatureValue = NomadFormatters.celsius(slot.temperatureCelsius)
        let lines = Self.detailLines(for: slot)
        detailLines = lines
        detailValue = lines.joined(separator: " · ")
    }

    private static func detailLines(for slot: WeatherHourlyForecastSlot) -> [String] {
        let rainValue = slot.precipitationChance.map { "Rain \(NomadFormatters.precipitation($0))" }
        let windSummary = WeatherWindMetricPresentation.summary(
            speedKph: slot.windSpeedKph,
            directionDegrees: slot.windDirectionDegrees
        )
        let windValue = windSummary == "n/a" ? nil : windSummary
        let parts = [rainValue, windValue].compactMap(\.self)

        return parts.isEmpty ? [slot.conditionDescription] : parts
    }
}

struct WeatherWindMetricPresentation: Equatable {
    let primaryValue: String
    let secondaryValue: String?

    init(snapshot: WeatherSnapshot) {
        primaryValue = Self.summary(
            speedKph: snapshot.windSpeedKph,
            directionDegrees: snapshot.windDirectionDegrees
        )
        secondaryValue = snapshot.windSpeedKph.map { NomadFormatters.metersPerSecond($0) }
    }

    static func summary(speedKph: Double?, directionDegrees: Double?) -> String {
        let speed = speedKph.map { NomadFormatters.kilometersPerHour($0) } ?? "n/a"
        let direction = NomadFormatters.compassDirection(directionDegrees)

        if speed == "n/a", direction == "n/a" {
            return "n/a"
        }

        if speed == "n/a" {
            return direction
        }

        if direction == "n/a" {
            return speed
        }

        return "\(speed) \(direction)"
    }
}

private struct ForecastDisclosureSection<Content: View>: View {
    let title: String
    let isExpanded: Bool
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: action) {
                HStack(spacing: 10) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NomadTheme.primaryText)

                    Spacer(minLength: 8)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(NomadTheme.tertiaryText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(NomadTheme.chartBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(NomadTheme.cardBorder.opacity(0.9), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                content
            }
        }
    }
}

private struct WeatherHourlyForecastChip: View {
    let model: WeatherHourlyForecastSlotPresentation
    var isCompact = false

    var body: some View {
        Group {
            if isCompact {
                // Half-width cards only have room for the hour, symbol and temperature; the
                // rain and wind detail moves to the hover help.
                VStack(spacing: 3) {
                    Text(model.title)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(NomadTheme.tertiaryText)

                    Image(systemName: model.symbolName)
                        .font(.caption)
                        .foregroundStyle(NomadTheme.secondaryText)
                        .accessibilityHidden(true)

                    Text(model.temperatureValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NomadTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .padding(.horizontal, 2)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.title)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(NomadTheme.tertiaryText)

                    Label(model.temperatureValue, systemImage: model.symbolName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NomadTheme.primaryText)
                        .lineLimit(1)

                    ForEach(model.detailLines, id: \.self) { line in
                        Text(line)
                            .font(.caption2)
                            .foregroundStyle(NomadTheme.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(NomadTheme.chartBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(NomadTheme.cardBorder.opacity(0.9), lineWidth: 1)
                )
        )
        .help("\(model.title): \(model.temperatureValue), \(model.detailValue)")
    }
}

/// A small labeled stat for the current weather and surf conditions: caption label, one-line
/// value that scales down instead of wrapping, optional secondary caption.
private struct WeatherStatView: View {
    let title: String
    let value: String
    var secondaryValue: String?
    /// Tints the value for a status (sand, coral); neutral keeps the primary text color.
    var tone: SummaryTileTone = .neutral

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(NomadTheme.tertiaryText)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(tone.statusTint(neutral: NomadTheme.primaryText))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let secondaryValue {
                Text(secondaryValue)
                    .font(.caption2)
                    .foregroundStyle(NomadTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "Sunrise 07:45 · Sunset 18:12" (or "Midnight sun" / "Polar night") as one quiet caption line.
/// "AQI 38 · Fair · mostly PM10" with a bar per hour of the 12 hour outlook.
private struct WeatherAirQualityView: View {
    let presentation: WeatherAirQualityPresentation
    let isCompact: Bool

    var body: some View {
        Group {
            if isCompact {
                VStack(alignment: .leading, spacing: 8) {
                    summary
                    outlook
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    summary
                    Spacer(minLength: 8)
                    outlook
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(NomadTheme.chartBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(NomadTheme.cardBorder.opacity(0.9), lineWidth: 1)
                )
        )
        .help(presentation.help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Air quality")
        .accessibilityValue([presentation.headline, presentation.outlookCaption].compactMap(\.self).joined(separator: ". "))
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("AIR QUALITY")
                .font(.caption2.weight(.bold))
                .foregroundStyle(NomadTheme.tertiaryText)
                .lineLimit(1)

            Text(presentation.headline)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(presentation.tone.statusTint(neutral: NomadTheme.primaryText))
                .lineLimit(isCompact ? 2 : 1)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var outlook: some View {
        if presentation.bars.isEmpty == false {
            VStack(alignment: isCompact ? .leading : .trailing, spacing: 3) {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(presentation.bars) { bar in
                        Capsule()
                            .fill(bar.tone.statusTint(neutral: NomadTheme.teal).opacity(0.85))
                            .frame(width: 5, height: 22 * bar.height)
                            .help(bar.help)
                    }
                }
                .frame(height: 22, alignment: .bottom)

                if let caption = presentation.outlookCaption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(NomadTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }
}

private struct DaylightLineView: View {
    let presentation: DaylightLinePresentation

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(presentation.segments.enumerated()), id: \.element.id) { index, segment in
                if index > 0 {
                    Text("\u{B7}")
                        .foregroundStyle(NomadTheme.tertiaryText)
                        .accessibilityHidden(true)
                }
                Label(segment.text, systemImage: segment.symbolName)
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .foregroundStyle(NomadTheme.secondaryText)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.summary)
    }
}

private struct WeatherDailyForecastRow: View {
    let summary: WeatherDaySummary

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Label(dayLabel, systemImage: summary.symbolName)
                .foregroundStyle(NomadTheme.primaryText)

            Spacer(minLength: 10)

            Text(summary.summary)
                .font(.caption)
                .foregroundStyle(NomadTheme.secondaryText)
                .lineLimit(1)

            Text(temperatureRange)
                .foregroundStyle(NomadTheme.secondaryText)
                .multilineTextAlignment(.trailing)
        }
    }

    private var dayLabel: String {
        summary.date.formatted(.dateTime.weekday(.abbreviated))
    }

    private var temperatureRange: String {
        let minimum = summary.temperatureMinCelsius.map { NomadFormatters.celsius($0) } ?? "Estimating"
        let maximum = summary.temperatureMaxCelsius.map { NomadFormatters.celsius($0) } ?? "Estimating"
        return "\(minimum) / \(maximum)"
    }
}

struct FuelPricesSectionPresentation {
    let badge: PillBadge
    let visualMode: FuelCardVisualMode
    let subtitle: String
    let rows: [FuelPriceRowModel]
    let emptyTitle: String
    let emptySystemImage: String
    let emptyMessage: String
    let emptyActionTitle: String?
    let note: String?

    init(
        settings: AppSettings,
        snapshot: DashboardSnapshot,
        locationStatusDetail: String?
    ) {
        guard settings.fuelPricesEnabled else {
            badge = PillBadge(title: "Off", symbolName: "fuelpump.slash.fill", tint: NomadTheme.primaryText)
            visualMode = .staticScene
            subtitle = "Nearby fuel prices are disabled"
            rows = []
            emptyTitle = "Fuel Prices Off"
            emptySystemImage = "fuelpump.slash.fill"
            emptyMessage = "Enable nearby fuel prices in Settings."
            emptyActionTitle = "Open Settings"
            note = nil
            return
        }

        guard let fuelPrices = snapshot.fuelPrices else {
            badge = PillBadge(title: "Checking", symbolName: "fuelpump.fill", tint: NomadTheme.secondaryText)
            visualMode = .ambient
            subtitle = "Looking for nearby prices"
            rows = []
            emptyTitle = "Checking Fuel Prices"
            emptySystemImage = "fuelpump.fill"
            emptyMessage = "Looking for nearby diesel and gasoline prices."
            emptyActionTitle = nil
            note = nil
            return
        }

        note = fuelPrices.note

        switch fuelPrices.status {
        case .ready:
            badge = FuelPricesSectionPresentation.readyBadge(for: fuelPrices)
            visualMode = .animatedCamper
            subtitle = fuelPrices.countryName.map { "\($0) · within \(Int(fuelPrices.searchRadiusKilometers)) km" }
                ?? "Within \(Int(fuelPrices.searchRadiusKilometers)) km"
            rows = [fuelPrices.diesel, fuelPrices.gasoline].compactMap { station in
                guard let station else {
                    return nil
                }

                return FuelPriceRowModel(
                    id: station.fuelType,
                    title: station.fuelType.displayName,
                    stationName: station.stationName,
                    stationDetail: Self.stationDetail(for: station),
                    priceValue: FuelPriceFormatting.price(station.pricePerLiter, currencyCode: station.currencyCode),
                    updatedText: station.updatedAt.map { "Updated \(NomadFormatters.compactClockTime($0))" },
                    stationDestination: FuelStationMapDestination(
                        fuelType: station.fuelType,
                        stationName: station.stationName,
                        address: station.address,
                        locality: station.locality,
                        pricePerLiter: station.pricePerLiter,
                        currencyCode: station.currencyCode,
                        latitude: station.latitude,
                        longitude: station.longitude,
                        updatedAt: station.updatedAt
                    )
                )
            }
            emptyTitle = ""
            emptySystemImage = "fuelpump.fill"
            emptyMessage = ""
            emptyActionTitle = nil
        case .unsupported:
            badge = PillBadge(title: "Unsupported", symbolName: "globe.badge.chevron.backward", tint: NomadTheme.primaryText)
            visualMode = .ambient
            subtitle = fuelPrices.countryName ?? "Unsupported country"
            rows = []
            emptyTitle = "Country Unsupported"
            emptySystemImage = "globe.badge.chevron.backward"
            emptyMessage = fuelPrices.detail ?? "Nearby fuel prices are not supported in this country yet."
            emptyActionTitle = nil
        case .locationRequired:
            badge = PillBadge(title: "Location Needed", symbolName: "location.slash.fill", tint: NomadTheme.sand)
            visualMode = .ambient
            subtitle = "Precise location is required"
            rows = []
            emptyTitle = "Current Location Needed"
            emptySystemImage = "location.slash.fill"
            emptyMessage = locationStatusDetail ?? fuelPrices.detail ?? "Allow current location to look up nearby fuel prices."
            emptyActionTitle = "Open Settings"
        case .configurationRequired:
            badge = PillBadge(title: "Setup", symbolName: "key.fill", tint: NomadTheme.sand)
            visualMode = .ambient
            subtitle = fuelPrices.sourceName
            rows = []
            emptyTitle = "Source Setup Needed"
            emptySystemImage = "key.fill"
            emptyMessage = fuelPrices.detail ?? "This source needs extra configuration."
            emptyActionTitle = "Open Settings"
        case .unavailable:
            badge = PillBadge(title: "Unavailable", symbolName: "wifi.exclamationmark", tint: NomadTheme.primaryText)
            visualMode = .ambient
            subtitle = fuelPrices.sourceName
            rows = []
            emptyTitle = "Fuel Prices Unavailable"
            emptySystemImage = "wifi.exclamationmark"
            emptyMessage = fuelPrices.detail ?? "Nearby fuel prices are unavailable right now."
            emptyActionTitle = nil
        case .noStationsFound:
            badge = PillBadge(title: "No Matches", symbolName: "mappin.slash", tint: NomadTheme.primaryText)
            visualMode = .ambient
            subtitle = fuelPrices.countryName.map { "\($0) · within \(Int(fuelPrices.searchRadiusKilometers)) km" }
                ?? "Within \(Int(fuelPrices.searchRadiusKilometers)) km"
            rows = []
            emptyTitle = "No Nearby Prices"
            emptySystemImage = "mappin.slash"
            emptyMessage = fuelPrices.detail ?? "No priced stations were found nearby."
            emptyActionTitle = nil
        }
    }

    var isActionable: Bool {
        emptyActionTitle != nil
    }

    private static func stationDetail(for station: FuelStationPrice) -> String {
        let pieces = [
            station.locality,
            NomadFormatters.kilometers(station.distanceKilometers),
            station.isSelfService == true ? "Self-service" : nil
        ].compactMap(\.self)

        if let address = station.address, pieces.isEmpty == false {
            return "\(address) · \(pieces.joined(separator: " · "))"
        }

        if let address = station.address {
            return address
        }

        return pieces.joined(separator: " · ")
    }

    private static func readyBadge(for snapshot: FuelPriceSnapshot) -> PillBadge {
        if snapshot.sourceName == "MIMIT Fuel Prices" {
            return PillBadge(title: "Daily", symbolName: "calendar", tint: NomadTheme.teal)
        }

        return PillBadge(title: "Live", symbolName: "fuelpump.fill", tint: NomadTheme.teal)
    }
}

struct LocalInfoRowModel: Identifiable {
    let id: String
    let title: String
    /// The answer the row exists to give ("24 Oct · in 12 days", "Moderate").
    let value: String
    /// What the answer refers to ("Labour Day", "Meals −4% · Groceries −4%").
    let detail: String
    let badge: PillBadge?
    /// Provenance and other fine print for hover.
    let help: String?
    /// Whether the value can be selected and copied (phone numbers).
    let isValueSelectable: Bool
    /// Lines under the row that compare the answer with the user's home country; nil when there is none.
    let homeComparison: HomeComparison?

    /// "Groceries ~30% cheaper than Finland" per category, with where the comparison comes from. Neutral text:
    /// cheaper or pricier is information, not a status.
    struct HomeComparison: Equatable {
        let lines: [String]
        /// "Compared with Finland (your home)".
        let caption: String

        /// Nil when the snapshot has no comparison with a home country.
        init?(level: LocalPriceLevelSnapshot, locale: Locale) {
            guard let differences = level.homeComparison, differences.isEmpty == false,
                  let homeCountryCode = level.homeCountryCode
            else {
                return nil
            }

            lines = differences.map {
                PriceLevelComparison.text(for: $0, homeCountryCode: homeCountryCode, locale: locale)
            }
            caption = "Compared with \(CountryNames.displayName(forCode: homeCountryCode, locale: locale)) (your home)"
        }
    }

    init(
        id: String,
        title: String,
        value: String,
        detail: String,
        badge: PillBadge? = nil,
        help: String? = nil,
        isValueSelectable: Bool = false,
        homeComparison: HomeComparison? = nil
    ) {
        self.id = id
        self.title = title
        self.value = value
        self.detail = detail
        self.badge = badge
        self.help = help
        self.isValueSelectable = isValueSelectable
        self.homeComparison = homeComparison
    }

    /// A single price indicator that stands on its own (the US HUD 1-bedroom rent benchmark).
    init(priceRow row: LocalPriceIndicatorRow) {
        id = "price-\(row.kind.rawValue)"
        title = row.kind.displayName
        value = row.value
        detail = row.detail
        badge = nil
        help = row.source.name
        isValueSelectable = false
        homeComparison = nil
    }
}

struct LocalInfoSectionPresentation {
    let badge: PillBadge
    let subtitle: String
    let rows: [LocalInfoRowModel]
    let emptyTitle: String
    let emptySystemImage: String
    let emptyMessage: String
    let emptyActionTitle: String?
    let sourceLine: String?
    let note: String?
    /// Periods of the current country that are on or start soon; empty when there are none.
    private(set) var rhythm: [LocalRhythmRowModel] = []

    init(
        settings: AppSettings,
        snapshot: DashboardSnapshot,
        locationStatusDetail: String?,
        now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) {
        guard settings.localInfoEnabled else {
            badge = PillBadge(title: "Off", symbolName: "mappin.slash.circle.fill", tint: NomadTheme.primaryText)
            subtitle = "Local context is disabled"
            rows = []
            emptyTitle = "Local Info Off"
            emptySystemImage = "mappin.slash.circle.fill"
            emptyMessage = "Enable Local Info in Settings."
            emptyActionTitle = "Open Settings"
            sourceLine = nil
            note = nil
            return
        }

        guard let localInfo = snapshot.localInfo else {
            badge = PillBadge(title: "Checking", symbolName: "calendar.badge.clock", tint: NomadTheme.secondaryText)
            subtitle = "Looking up local context"
            rows = []
            emptyTitle = "Checking Local Info"
            emptySystemImage = "calendar.badge.clock"
            emptyMessage = "Looking up local context and holiday calendar."
            emptyActionTitle = nil
            sourceLine = nil
            note = nil
            return
        }

        var builtRows: [LocalInfoRowModel] = []

        // Safety information leads.
        if localInfo.status != .locationRequired,
           let numbers = EmergencyNumberDirectory.numbers(forCountryCode: snapshot.currentCountryCode)
        {
            builtRows.insert(
                LocalInfoRowModel(
                    id: "emergency-numbers",
                    title: "Emergency",
                    value: numbers.general,
                    detail: numbers.othersText ?? "",
                    isValueSelectable: true
                ),
                at: 0
            )
        }

        if localInfo.status != .locationRequired {
            builtRows.append(Self.publicHolidayRow(from: localInfo.publicHolidayStatus, now: now, calendar: calendar))

            if let schoolHolidayStatus = localInfo.schoolHolidayStatus {
                builtRows.append(Self.schoolHolidayRow(from: schoolHolidayStatus))
            }
        }

        if let localPriceLevel = localInfo.localPriceLevel {
            builtRows.append(contentsOf: Self.priceRows(from: localPriceLevel, locale: locale))
        }

        rows = builtRows
        if localInfo.status != .locationRequired {
            rhythm = LocalRhythmRowModel.rows(snapshot: snapshot, now: now, calendar: calendar, locale: locale)
        }
        sourceLine = localInfo.sources.isEmpty ? nil : "Sources: " + localInfo.sources.map(\.name).joined(separator: " · ")
        // A healthy snapshot has nothing to explain; only degraded states carry their detail.
        note = (localInfo.status == .ready ? [localInfo.note] : [localInfo.detail, localInfo.note])
            .compactMap(\.self)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
            .nilIfEmpty

        let resolvedSubtitle = Self.locationSubtitle(for: localInfo)

        switch localInfo.status {
        case .ready:
            badge = PillBadge(title: "Live", symbolName: "mappin.and.ellipse", tint: NomadTheme.teal)
            subtitle = resolvedSubtitle
            emptyTitle = ""
            emptySystemImage = "mappin.and.ellipse"
            emptyMessage = ""
            emptyActionTitle = nil
        case .partial:
            badge = PillBadge(title: "Partial", symbolName: "ellipsis.circle.fill", tint: NomadTheme.sand)
            subtitle = resolvedSubtitle
            emptyTitle = ""
            emptySystemImage = "ellipsis.circle.fill"
            emptyMessage = ""
            emptyActionTitle = nil
        case .locationRequired:
            badge = PillBadge(title: "Location Needed", symbolName: "location.slash.fill", tint: NomadTheme.sand)
            subtitle = "Country context is required"
            emptyTitle = "Location Needed"
            emptySystemImage = "location.slash.fill"
            emptyMessage = locationStatusDetail ?? localInfo.detail ?? "Allow location access or enable external IP location."
            emptyActionTitle = "Open Settings"
        case .unsupported:
            badge = PillBadge(title: "Unsupported", symbolName: "globe.badge.chevron.backward", tint: NomadTheme.primaryText)
            subtitle = resolvedSubtitle
            emptyTitle = "Region Unsupported"
            emptySystemImage = "globe.badge.chevron.backward"
            emptyMessage = localInfo.detail ?? "Local info is not supported here yet."
            emptyActionTitle = nil
        case .unavailable:
            badge = PillBadge(title: "Unavailable", symbolName: "wifi.exclamationmark", tint: NomadTheme.primaryText)
            subtitle = resolvedSubtitle
            emptyTitle = "Local Info Unavailable"
            emptySystemImage = "wifi.exclamationmark"
            emptyMessage = localInfo.detail ?? "Local info is unavailable right now."
            emptyActionTitle = nil
        }
    }

    /// "Valencia · Valencian Community, Spain · Europe/Madrid": where the data applies.
    private static func locationSubtitle(for localInfo: LocalInfoSnapshot) -> String {
        let locality = localInfo.locality
        let area = [
            localInfo.administrativeRegion == locality ? nil : localInfo.administrativeRegion,
            localInfo.countryName
        ]
        .compactMap(\.self)
        .joined(separator: ", ")
        .nilIfEmpty

        return [locality, area, localInfo.timeZoneIdentifier]
            .compactMap(\.self)
            .joined(separator: " · ")
            .nilIfEmpty ?? "Current area"
    }

    private static func publicHolidayRow(
        from status: LocalHolidayStatus,
        now: Date,
        calendar: Calendar
    ) -> LocalInfoRowModel {
        switch status.state {
        case .current:
            LocalInfoRowModel(
                id: "public-holiday",
                title: "Public Holiday",
                value: "Today",
                detail: status.currentPeriod?.name ?? "Holiday today",
                badge: PillBadge(
                    title: "Busy Today",
                    symbolName: "exclamationmark.triangle.fill",
                    tint: NomadTheme.sand
                )
            )
        case .tomorrow, .upcoming:
            LocalInfoRowModel(
                id: "public-holiday",
                title: "Public Holiday",
                value: status.nextPeriod.map {
                    "\(formattedDay($0.startDate)) · \(relativeDayText(to: $0.startDate, from: now, calendar: calendar))"
                } ?? (status.state == .tomorrow ? "Tomorrow" : "Next"),
                detail: status.nextPeriod?.name ?? (status.state == .tomorrow ? "Holiday tomorrow" : "Upcoming holiday")
            )
        case .unavailable:
            LocalInfoRowModel(
                id: "public-holiday",
                title: "Public Holiday",
                value: "Unavailable",
                detail: status.note ?? "Holiday data is unavailable right now."
            )
        case .unsupported:
            LocalInfoRowModel(
                id: "public-holiday",
                title: "Public Holiday",
                value: "Not Available",
                detail: status.note ?? "Holiday data is not supported here yet."
            )
        }
    }

    private static func schoolHolidayRow(from status: LocalHolidayStatus) -> LocalInfoRowModel {
        switch status.state {
        case .current:
            LocalInfoRowModel(
                id: "school-holiday",
                title: "School Break",
                value: "On Break",
                detail: status.currentPeriod.map { "\($0.name) · \(formattedRange($0))" } ?? "School break is active",
                badge: PillBadge(
                    title: "Busy Period",
                    symbolName: "exclamationmark.triangle.fill",
                    tint: NomadTheme.sand
                )
            )
        case .tomorrow, .upcoming:
            LocalInfoRowModel(
                id: "school-holiday",
                title: "School Break",
                value: status.nextPeriod.map(formattedRange) ?? (status.state == .tomorrow ? "Tomorrow" : "Next Break"),
                detail: status.nextPeriod?.name ?? (status.state == .tomorrow ? "School break starts tomorrow" : "Upcoming school break")
            )
        case .unavailable:
            LocalInfoRowModel(
                id: "school-holiday",
                title: "School Break",
                value: "Unavailable",
                detail: status.note ?? "School-break data is unavailable right now."
            )
        case .unsupported:
            LocalInfoRowModel(
                id: "school-holiday",
                title: "School Break",
                value: "Not Available",
                detail: status.note ?? "School-break data is not supported here yet."
            )
        }
    }

    /// The Eurostat indicators (meals, groceries, overall) collapse into one "Prices vs EU" row:
    /// the overall level word as the answer and the three deltas as the detail. Any other
    /// indicator (the US 1-bedroom rent benchmark) keeps its own value/detail row.
    static func priceRows(from level: LocalPriceLevelSnapshot, locale: Locale) -> [LocalInfoRowModel] {
        let comparison: [(label: String, kind: LocalPriceIndicatorKind)] = [
            ("Meals", .mealOut),
            ("Groceries", .groceries),
            ("Overall", .overall)
        ]
        let comparisonKinds = Set(comparison.map(\.kind))
        let comparisonRows = comparison.compactMap { entry in
            level.rows.first(where: { $0.kind == entry.kind }).map { (label: entry.label, row: $0) }
        }

        var result: [LocalInfoRowModel] = []

        if let first = comparisonRows.first?.row {
            let overall = comparisonRows.first(where: { $0.row.kind == .overall })?.row
            result.append(
                LocalInfoRowModel(
                    id: "prices-vs-eu",
                    title: "Prices vs EU",
                    value: overall?.value ?? level.summaryBand?.displayName ?? first.value,
                    detail: comparisonRows
                        .map { "\($0.label) \(relativeDeltaText($0.row))" }
                        .joined(separator: " · "),
                    help: "\(first.precision.displayName) · \(first.source.name)",
                    homeComparison: LocalInfoRowModel.HomeComparison(level: level, locale: locale)
                )
            )
        }

        result.append(
            contentsOf: level.rows
                .filter { comparisonKinds.contains($0.kind) == false }
                .map(LocalInfoRowModel.init(priceRow:))
        )
        return result
    }

    /// "−4%" below the EU average, "+3%" above, "≈ EU" within one percent (the provider's
    /// "Around EU average"). Rows without a numeric difference fall back to their level word.
    private static func relativeDeltaText(_ row: LocalPriceIndicatorRow) -> String {
        guard let percent = row.differenceFromEUPercent else {
            return row.value
        }

        let rounded = Int(percent.rounded())
        if abs(rounded) <= 1 {
            return "≈ EU"
        }

        return rounded > 0 ? "+\(rounded)%" : "\u{2212}\(abs(rounded))%"
    }

    private static func relativeDayText(to date: Date, from now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: date)
        ).day ?? 0

        switch days {
        case ..<1:
            return "today"
        case 1:
            return "tomorrow"
        default:
            return "in \(days) days"
        }
    }

    static func formattedDay(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    private static func formattedRange(_ period: HolidayPeriodSnapshot) -> String {
        let start = formattedDay(period.startDate)
        let end = formattedDay(period.endDate)
        return start == end ? start : "\(start) – \(end)"
    }
}

struct EmergencyCareSectionPresentation {
    let badge: PillBadge
    /// "Within 25 km · Emergency 112": the number is the offline emergency number of the current
    /// country and is left out when it is not known.
    let subtitle: String
    let emergencyNumbers: EmergencyNumbers?
    let rows: [EmergencyHospitalRowModel]
    let emptyTitle: String
    let emptySystemImage: String
    let emptyMessage: String
    let emptyActionTitle: String?

    init(
        settings: AppSettings,
        snapshot: DashboardSnapshot,
        locationStatusDetail: String?
    ) {
        guard settings.emergencyCareEnabled else {
            badge = PillBadge(title: "Off", symbolName: "cross.case", tint: NomadTheme.primaryText)
            subtitle = "Nearby emergency hospitals are disabled"
            emergencyNumbers = nil
            rows = []
            emptyTitle = "Emergency Care Off"
            emptySystemImage = "cross.case"
            emptyMessage = "Enable nearby emergency hospitals in Settings."
            emptyActionTitle = "Open Settings"
            return
        }

        let numbers = EmergencyNumberDirectory.numbers(forCountryCode: snapshot.currentCountryCode)
        emergencyNumbers = numbers

        func withNumber(_ base: String) -> String {
            [base, numbers?.headline].compactMap(\.self).joined(separator: " · ")
        }

        guard let emergencyCare = snapshot.emergencyCare else {
            badge = PillBadge(title: "Checking", symbolName: "cross.case.fill", tint: NomadTheme.secondaryText)
            subtitle = withNumber("Looking for nearby hospitals")
            rows = []
            emptyTitle = "Checking Emergency Care"
            emptySystemImage = "cross.case.fill"
            emptyMessage = "Looking for nearby emergency hospitals."
            emptyActionTitle = nil
            return
        }

        switch emergencyCare.status {
        case .ready:
            badge = PillBadge(title: "Nearby", symbolName: "cross.case.fill", tint: NomadTheme.teal)
            subtitle = withNumber("Within \(Int(emergencyCare.searchRadiusKilometers)) km")
            rows = emergencyCare.hospitals.map { hospital in
                EmergencyHospitalRowModel(
                    id: hospital.id,
                    hospitalName: hospital.name,
                    hospitalDetail: Self.hospitalDetail(for: hospital),
                    distanceText: NomadFormatters.kilometers(hospital.distanceKilometers),
                    ownershipTitle: hospital.ownership == .unknown ? nil : hospital.ownership.displayName,
                    destination: EmergencyHospitalMapDestination(
                        hospitalName: hospital.name,
                        address: hospital.address,
                        locality: hospital.locality,
                        ownership: hospital.ownership,
                        latitude: hospital.latitude,
                        longitude: hospital.longitude
                    )
                )
            }
            emptyTitle = ""
            emptySystemImage = "cross.case.fill"
            emptyMessage = ""
            emptyActionTitle = nil
        case .locationRequired:
            badge = PillBadge(title: "Location Needed", symbolName: "location.slash.fill", tint: NomadTheme.sand)
            subtitle = withNumber("Precise location is required")
            rows = []
            emptyTitle = "Current Location Needed"
            emptySystemImage = "location.slash.fill"
            emptyMessage = locationStatusDetail ?? emergencyCare.detail ?? "Allow current location to look up nearby emergency hospitals."
            emptyActionTitle = "Open Settings"
        case .unavailable:
            badge = PillBadge(title: "Unavailable", symbolName: "wifi.exclamationmark", tint: NomadTheme.primaryText)
            subtitle = withNumber(emergencyCare.sourceName)
            rows = []
            emptyTitle = "Emergency Care Unavailable"
            emptySystemImage = "wifi.exclamationmark"
            emptyMessage = emergencyCare.detail ?? "Nearby emergency hospitals are unavailable right now."
            emptyActionTitle = nil
        case .noHospitalsFound:
            badge = PillBadge(title: "No Matches", symbolName: "mappin.slash", tint: NomadTheme.primaryText)
            subtitle = withNumber("Within \(Int(emergencyCare.searchRadiusKilometers)) km")
            rows = []
            emptyTitle = "No Nearby Hospitals"
            emptySystemImage = "mappin.slash"
            emptyMessage = emergencyCare.detail ?? "No nearby emergency hospitals were found."
            emptyActionTitle = nil
        }
    }

    var isActionable: Bool {
        emptyActionTitle != nil
    }

    private static func hospitalDetail(for hospital: EmergencyHospital) -> String {
        let pieces = [
            hospital.address,
            hospital.locality
        ].compactMap(\.self)
        return pieces.joined(separator: " · ")
    }
}

struct SurfSectionPresentation {
    enum State: Equatable {
        case notConfigured
        case invalid
        case unavailable
        case ready
    }

    let state: State
    let spotName: String?
    let badge: PillBadge
    let marine: MarineSnapshot?
    let waveSummary: String
    let swellSummary: String
    let windSummary: String
    let forecastSlots: [SurfForecastSlotPresentation]
    let emptyTitle: String
    let emptySystemImage: String
    let emptyMessage: String
    let emptyActionTitle: String?

    init(settings: AppSettings, snapshot: DashboardSnapshot) {
        let surfConfiguration = settings.surfSpotConfiguration

        if let marine = snapshot.marine {
            state = .ready
            spotName = marine.spotName
            badge = PillBadge(
                title: "\(marine.sourceName) · \(NomadFormatters.compactClockTime(marine.fetchedAt))",
                symbolName: "water.waves",
                tint: NomadTheme.teal
            )
            self.marine = marine
            waveSummary = Self.waveSummary(for: marine)
            swellSummary = Self.swellSummary(for: marine)
            windSummary = Self.windSummary(for: marine)
            forecastSlots = marine.forecastSlots.enumerated().map { index, slot in
                SurfForecastSlotPresentation(index: index, slot: slot, referenceDate: marine.fetchedAt)
            }
            emptyTitle = ""
            emptySystemImage = "water.waves"
            emptyMessage = ""
            emptyActionTitle = nil
            return
        }

        spotName = surfConfiguration.name
        marine = nil
        waveSummary = "n/a"
        swellSummary = "n/a"
        windSummary = "n/a"
        forecastSlots = []

        if surfConfiguration.isConfigured == false {
            state = .notConfigured
            badge = PillBadge(title: "Not Set", symbolName: "water.waves.slash", tint: NomadTheme.primaryText)
            emptyTitle = "Surf Spot"
            emptySystemImage = "water.waves.slash"
            emptyMessage = "Add a surf spot in Settings."
            emptyActionTitle = "Set Surf Spot"
        } else if surfConfiguration.isValid == false {
            state = .invalid
            badge = PillBadge(title: "Fix Spot", symbolName: "exclamationmark.triangle.fill", tint: NomadTheme.sand)
            emptyTitle = "Surf Spot"
            emptySystemImage = "exclamationmark.triangle.fill"
            emptyMessage = "Fix surf spot coordinates in Settings."
            emptyActionTitle = "Open Surf Settings"
        } else {
            state = .unavailable
            badge = PillBadge(title: "Unavailable", symbolName: "water.waves.slash", tint: NomadTheme.primaryText)
            emptyTitle = "Surf Spot"
            emptySystemImage = "water.waves.slash"
            emptyMessage = "Surf check unavailable."
            emptyActionTitle = nil
        }
    }

    var isActionable: Bool {
        switch state {
        case .notConfigured, .invalid:
            true
        case .unavailable, .ready:
            false
        }
    }

    private static func waveSummary(for marine: MarineSnapshot) -> String {
        summary(primary: NomadFormatters.meters(marine.waveHeightMeters), secondary: NomadFormatters.seconds(marine.wavePeriodSeconds))
    }

    private static func swellSummary(for marine: MarineSnapshot) -> String {
        summary(primary: NomadFormatters.meters(marine.swellHeightMeters), secondary: NomadFormatters.compassDirection(marine.swellDirectionDegrees))
    }

    private static func windSummary(for marine: MarineSnapshot) -> String {
        summary(primary: NomadFormatters.kilometersPerHour(marine.windSpeedKph), secondary: NomadFormatters.compassDirection(marine.windDirectionDegrees))
    }

    private static func summary(primary: String, secondary: String) -> String {
        if primary == "n/a" {
            return secondary
        }

        if secondary == "n/a" {
            return primary
        }

        return "\(primary) · \(secondary)"
    }
}

struct SurfForecastSlotPresentation: Identifiable, Equatable {
    let id: String
    let title: String
    let waveValue: String
    let windValue: String

    init(index: Int, slot: MarineForecastSlot, referenceDate: Date) {
        id = "\(index)-\(slot.date.timeIntervalSinceReferenceDate)"
        let hourOffset = max(0, Int((slot.date.timeIntervalSince(referenceDate) / 3_600).rounded()))
        title = "+\(hourOffset)h"
        waveValue = NomadFormatters.meters(slot.waveHeightMeters)
        windValue = slot.windSpeedKph.map {
            WeatherWindMetricPresentation.summary(speedKph: $0, directionDegrees: slot.windDirectionDegrees)
        } ?? "n/a"
    }
}

private struct MarineForecastChip: View {
    let model: SurfForecastSlotPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(NomadTheme.tertiaryText)

            Text(model.waveValue)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NomadTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(model.windValue)
                .font(.caption2)
                .foregroundStyle(NomadTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(NomadTheme.chartBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(NomadTheme.cardBorder.opacity(0.9), lineWidth: 1)
                )
        )
        .help("\(model.title): wave \(model.waveValue), wind \(model.windValue)")
    }
}

struct PillBadge {
    let title: String
    let symbolName: String
    let tint: Color
}

public extension HealthLevel {
    /// The status colour: teal ready, sand caution, coral attention, neutral while there is no reading.
    /// Public so the widgets colour status exactly like the dashboard.
    var tint: Color {
        switch self {
        case .ready:
            NomadTheme.teal
        case .caution:
            NomadTheme.sand
        case .attention:
            NomadTheme.coral
        case .unavailable:
            NomadTheme.primaryText
        }
    }
}

private extension TravelAlertSeverity {
    var tint: Color {
        switch self {
        case .clear:
            NomadTheme.teal
        case .info:
            NomadTheme.primaryText
        case .caution:
            NomadTheme.sand
        case .warning:
            NomadTheme.coral
        case .critical:
            .red
        }
    }

    var symbolName: String {
        switch self {
        case .clear:
            "checkmark.circle.fill"
        case .info:
            "info.circle.fill"
        case .caution:
            "exclamationmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .critical:
            "exclamationmark.octagon.fill"
        }
    }

    var badgeTitle: String {
        switch self {
        case .clear:
            "Clear"
        case .info:
            "Info"
        case .caution:
            "Caution"
        case .warning:
            "Warning"
        case .critical:
            "Critical"
        }
    }
}

private extension TravelAlertKind {
    var displayName: String {
        switch self {
        case .advisory:
            "Travel Advisory"
        case .weather:
            "Weather Alerts"
        case .security:
            "Regional Security"
        }
    }
}

private extension TravelAlertUnavailableReason {
    var summary: String {
        switch self {
        case .countryRequired:
            "Country needed for nearby alerts"
        case .locationRequired:
            "Location needed for local alerts"
        case .sourceUnavailable:
            "Source unavailable"
        case .sourceConfigurationRequired:
            "Source setup required"
        }
    }
}

private func travelAlertDateText(_ value: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "d MMM"
    return formatter.string(from: value)
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

extension View {
    /// `.help` that adds no (empty) tooltip when there is nothing to say.
    @ViewBuilder
    func help(ifPresent text: String?) -> some View {
        if let text, text.isEmpty == false {
            help(text)
        } else {
            self
        }
    }
}

extension View {
    @ViewBuilder
    func textSelectionIfNeeded(_ isSelectable: Bool) -> some View {
        if isSelectable {
            textSelection(.enabled)
        } else {
            self
        }
    }
}
