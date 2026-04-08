import AppKit
import Charts
import NomadCore
import SwiftUI

public struct DashboardPanelView: View {
    private let snapshot: DashboardSnapshot
    private let refreshActivity: DashboardRefreshActivity
    private let settings: AppSettings
    private let dashboardCardOrder: [DashboardCardID]
    private let dashboardCardWidthModes: [DashboardCardID: DashboardCardWidthMode]
    private let isPublicIPLocationEnabled: Bool
    private let travelAlertPreferences: TravelAlertPreferences
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
    private let copyIPAddressAction: () -> Void
    private let openVisitedMapAction: () -> Void
    private let openNetworkSettingsAction: () -> Void
    private let openFuelStationMapPreviewAction: (FuelStationMapDestination) -> Void
    private let openFuelStationInGoogleMapsAction: (FuelStationMapDestination) -> Void
    private let openEmergencyHospitalMapPreviewAction: (EmergencyHospitalMapDestination) -> Void
    private let openEmergencyHospitalInGoogleMapsAction: (EmergencyHospitalMapDestination) -> Void
    private let checkForUpdatesAction: (() -> Void)?
    private let openSettingsAction: () -> Void
    private let openSurfSpotSettingsAction: () -> Void
    private let openAboutAction: () -> Void
    private let quitAction: () -> Void
    private let onCardOrderChange: ([DashboardCardID]) -> Void
    private let onCardWidthModesChange: ([DashboardCardID: DashboardCardWidthMode]) -> Void
    private let onWeatherForecastExpandedChange: (Bool) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var resolvedCardOrder: [DashboardCardID]
    @State private var resolvedCardWidthModes: [DashboardCardID: DashboardCardWidthMode]
    @State private var activeDropCardID: DashboardCardID?

    public init(
        snapshot: DashboardSnapshot,
        refreshActivity: DashboardRefreshActivity,
        settings: AppSettings,
        dashboardCardOrder: [DashboardCardID],
        dashboardCardWidthModes: [DashboardCardID: DashboardCardWidthMode],
        isPublicIPLocationEnabled: Bool,
        travelAlertPreferences: TravelAlertPreferences,
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
        copyIPAddressAction: @escaping () -> Void,
        openVisitedMapAction: @escaping () -> Void,
        openNetworkSettingsAction: @escaping () -> Void,
        openFuelStationMapPreviewAction: @escaping (FuelStationMapDestination) -> Void = { _ in },
        openFuelStationInGoogleMapsAction: @escaping (FuelStationMapDestination) -> Void = { _ in },
        openEmergencyHospitalMapPreviewAction: @escaping (EmergencyHospitalMapDestination) -> Void = { _ in },
        openEmergencyHospitalInGoogleMapsAction: @escaping (EmergencyHospitalMapDestination) -> Void = { _ in },
        checkForUpdatesAction: (() -> Void)? = nil,
        openSettingsAction: @escaping () -> Void,
        openSurfSpotSettingsAction: @escaping () -> Void,
        openAboutAction: @escaping () -> Void,
        quitAction: @escaping () -> Void,
        onCardOrderChange: @escaping ([DashboardCardID]) -> Void = { _ in },
        onCardWidthModesChange: @escaping ([DashboardCardID: DashboardCardWidthMode]) -> Void = { _ in },
        onWeatherForecastExpandedChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.snapshot = snapshot
        self.refreshActivity = refreshActivity
        self.settings = settings
        self.dashboardCardOrder = DashboardCardID.sanitizedOrder(dashboardCardOrder)
        self.dashboardCardWidthModes = DashboardCardID.sanitizedWidthModes(dashboardCardWidthModes)
        self.isPublicIPLocationEnabled = isPublicIPLocationEnabled
        self.travelAlertPreferences = travelAlertPreferences
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
        self.copyIPAddressAction = copyIPAddressAction
        self.openVisitedMapAction = openVisitedMapAction
        self.openNetworkSettingsAction = openNetworkSettingsAction
        self.openFuelStationMapPreviewAction = openFuelStationMapPreviewAction
        self.openFuelStationInGoogleMapsAction = openFuelStationInGoogleMapsAction
        self.openEmergencyHospitalMapPreviewAction = openEmergencyHospitalMapPreviewAction
        self.openEmergencyHospitalInGoogleMapsAction = openEmergencyHospitalInGoogleMapsAction
        self.checkForUpdatesAction = checkForUpdatesAction
        self.openSettingsAction = openSettingsAction
        self.openSurfSpotSettingsAction = openSurfSpotSettingsAction
        self.openAboutAction = openAboutAction
        self.quitAction = quitAction
        self.onCardOrderChange = onCardOrderChange
        self.onCardWidthModesChange = onCardWidthModesChange
        self.onWeatherForecastExpandedChange = onWeatherForecastExpandedChange
        _resolvedCardOrder = State(initialValue: DashboardCardID.sanitizedOrder(dashboardCardOrder))
        _resolvedCardWidthModes = State(initialValue: DashboardCardID.sanitizedWidthModes(dashboardCardWidthModes))
    }

    public var body: some View {
        GeometryReader { viewport in
            let contentWidth = max(viewport.size.width - 36, 0)

            ZStack {
                NomadTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        summaryStrip
                        orderedCardSections(viewportHeight: viewport.size.height)
                        footer
                    }
                    .frame(width: contentWidth, alignment: .topLeading)
                    .padding(18)
                }
                .coordinateSpace(name: DashboardScrollCoordinateSpace.name)
            }
        }
        .frame(width: 430, height: 640)
        .onChange(of: dashboardCardOrder) { _, newValue in
            let sanitizedOrder = DashboardCardID.sanitizedOrder(newValue)
            guard resolvedCardOrder != sanitizedOrder else {
                return
            }

            resolvedCardOrder = sanitizedOrder
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

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 14) {
                HStack(spacing: 8) {
                    Text("Nomad Dashboard")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(NomadTheme.primaryText)

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
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    HeaderIconButton(
                        systemImage: "arrow.clockwise",
                        title: refreshHeader.buttonTitle,
                        isEnabled: refreshHeader.isButtonEnabled,
                        activity: refreshActivity,
                        action: refreshAction
                    )
                    HeaderIconButton(systemImage: appearanceToggleSystemImage, title: appearanceToggleTitle, action: toggleAppearanceAction)

                    Menu {
                        Button("Open Visited Map", systemImage: "globe.europe.africa.fill") {
                            openVisitedMapAction()
                        }

                        Button("Open Time Tracking", systemImage: "clock.badge.checkmark") {
                            openTimeTrackingAction()
                        }

                        Button("Open Network Settings", systemImage: "gearshape.2") {
                            openNetworkSettingsAction()
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
            }

            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Text(snapshot.travelContext.location.flatMap(formattedLocation) ?? "Travel-ready system telemetry")
                    .font(.subheadline)
                    .foregroundStyle(NomadTheme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 12)

                Text(refreshHeader.statusText)
                    .font(.caption)
                    .foregroundStyle(refreshStatusTint)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if timeTrackingDashboardState.isEnabled {
                timeTrackingHeaderPill
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            ForEach(packedCardRows) { row in
                if row.items.count == 2 {
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
        }
    }

    private var packedCardRows: [DashboardCardRow] {
        let orderedCards = DashboardCardID.sanitizedOrder(resolvedCardOrder)
        let widthModes = DashboardCardID.sanitizedWidthModes(resolvedCardWidthModes)
        var rows: [DashboardCardRow] = []
        var index = 0

        while index < orderedCards.count {
            let cardID = orderedCards[index]
            let widthMode = widthModes[cardID] ?? .wide

            if widthMode == .narrow,
               index + 1 < orderedCards.count
            {
                let nextCardID = orderedCards[index + 1]
                let nextWidthMode = widthModes[nextCardID] ?? .wide

                if nextWidthMode == .narrow {
                    rows.append(
                        DashboardCardRow(items: [
                            DashboardCardRowItem(
                                cardID: cardID,
                                preferredWidthMode: .narrow,
                                renderWidth: .half
                            ),
                            DashboardCardRowItem(
                                cardID: nextCardID,
                                preferredWidthMode: .narrow,
                                renderWidth: .half
                            )
                        ])
                    )
                    index += 2
                    continue
                }
            }

            rows.append(
                DashboardCardRow(items: [
                    DashboardCardRowItem(
                        cardID: cardID,
                        preferredWidthMode: widthMode,
                        renderWidth: .full
                    )
                ])
            )
            index += 1
        }

        return rows
    }

    private func dashboardCardItem(_ item: DashboardCardRowItem, viewportHeight: CGFloat) -> some View {
        interactiveCard(
            cardID: item.cardID,
            renderWidth: item.renderWidth
        ) {
            dashboardCard(for: item.cardID, widthMode: item.preferredWidthMode, viewportHeight: viewportHeight)
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
        case .power:
            powerSection(widthMode: widthMode)
        case .timeTracking:
            timeTrackingSection(widthMode: widthMode)
        case .travelContext:
            travelSection(widthMode: widthMode)
        case .localPriceLevel:
            localPriceLevelSection(widthMode: widthMode)
        case .fuelPrices:
            fuelPricesSection(widthMode: widthMode, viewportHeight: viewportHeight)
        case .emergencyCare:
            emergencyCareSection(widthMode: widthMode)
        case .travelAlerts:
            travelAlertsSection(widthMode: widthMode)
        case .weather:
            weatherSection(widthMode: widthMode)
        }
    }

    private func interactiveCard<Content: View>(
        cardID: DashboardCardID,
        renderWidth: DashboardCardRenderWidth,
        @ViewBuilder content: @escaping () -> Content
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

    private func connectivitySection(widthMode: DashboardCardWidthMode) -> some View {
        DashboardCard(
            title: "Connectivity",
            subtitle: snapshot.network.throughput?.activeInterface ?? "Interface unavailable",
            subtitleAccessory: AnyView(
                InternetStatusIndicator(
                    model: InternetStatusIndicatorModel(
                        connectivity: snapshot.network.connectivity,
                        style: widthMode == .narrow ? .compactIcon : .wideInline
                    )
                )
            ),
            badge: badge(for: snapshot.healthSummary.network),
            accessory: cardControls(for: .connectivity, title: "Connectivity"),
            isCompact: widthMode == .narrow
        ) {
            if widthMode == .narrow {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        MetricBlock(
                            title: "Down",
                            value: metricValue(snapshot.network.throughput?.downloadMegabitsPerSecond, formatter: NomadFormatters.megabitsPerSecond),
                            typography: .compact
                        )
                        MetricBlock(
                            title: "Up",
                            value: metricValue(snapshot.network.throughput?.uploadMegabitsPerSecond, formatter: NomadFormatters.megabitsPerSecond),
                            typography: .compact
                        )
                    }

                    MetricBlock(
                        title: "Latency",
                        value: metricValue(snapshot.network.latency?.milliseconds, formatter: NomadFormatters.latency, fallback: "Waiting"),
                        typography: .compact
                    )

                    MiniTrendChart(
                        points: snapshot.network.latencyHistory,
                        color: NomadTheme.coral,
                        yLabel: "Latency",
                        unitLabel: "ms",
                        isCompact: true
                    )

                    Text(compactThroughputSummary)
                        .font(.caption2)
                        .foregroundStyle(NomadTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(jitterDescription)
                        .font(.caption2)
                        .foregroundStyle(NomadTheme.secondaryText)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        MetricBlock(
                            title: "Down",
                            value: metricValue(snapshot.network.throughput?.downloadMegabitsPerSecond, formatter: NomadFormatters.megabitsPerSecond)
                        )
                        MetricBlock(
                            title: "Up",
                            value: metricValue(snapshot.network.throughput?.uploadMegabitsPerSecond, formatter: NomadFormatters.megabitsPerSecond)
                        )
                        MetricBlock(
                            title: "Latency",
                            value: metricValue(snapshot.network.latency?.milliseconds, formatter: NomadFormatters.latency, fallback: "Waiting")
                        )
                    }

                    HStack(spacing: 12) {
                        ThroughputTrendChart(
                            downloadPoints: snapshot.network.downloadHistory,
                            uploadPoints: snapshot.network.uploadHistory
                        )
                        MiniTrendChart(
                            points: snapshot.network.latencyHistory,
                            color: NomadTheme.coral,
                            yLabel: "Latency",
                            unitLabel: "ms"
                        )
                    }

                    Text(jitterDescription)
                        .font(.caption)
                        .foregroundStyle(NomadTheme.secondaryText)
                }
            }
        }
    }

    private func powerSection(widthMode: DashboardCardWidthMode) -> some View {
        DashboardCard(
            title: "Power",
            subtitle: snapshot.power.snapshot.map(powerSubtitle) ?? "Power source unavailable",
            badge: badge(for: snapshot.healthSummary.power),
            accessory: cardControls(for: .power, title: "Power"),
            isCompact: widthMode == .narrow
        ) {
            let powerMetrics = PowerMetricsPresentation(snapshot: snapshot.power.snapshot)

            if widthMode == .narrow {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        MetricBlock(
                            title: "Battery",
                            value: metricValue(snapshot.power.snapshot?.chargePercent.map { $0 * 100 }, formatter: NomadFormatters.percentage, fallback: "Estimating"),
                            typography: .compact
                        )
                        MetricBlock(title: "Drain", value: powerMetrics.drainValue, typography: .compact)
                    }

                    MetricBlock(title: "Time Left", value: powerMetrics.timeLeftValue, typography: .compact)

                    MiniTrendChart(
                        points: snapshot.power.chargeHistory,
                        color: NomadTheme.sand,
                        yLabel: "Charge",
                        unitLabel: "%",
                        isCompact: true
                    )

                    Text(compactDrainSummary(powerMetrics))
                        .font(.caption2)
                        .foregroundStyle(NomadTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        MetricBlock(
                            title: "Battery",
                            value: metricValue(snapshot.power.snapshot?.chargePercent.map { $0 * 100 }, formatter: NomadFormatters.percentage, fallback: "Estimating")
                        )
                        MetricBlock(title: "Drain", value: powerMetrics.drainValue)
                        MetricBlock(title: "Time Left", value: powerMetrics.timeLeftValue)
                    }

                    HStack(spacing: 12) {
                        MiniTrendChart(
                            points: snapshot.power.chargeHistory,
                            color: NomadTheme.sand,
                            yLabel: "Charge",
                            unitLabel: "%"
                        )
                        MiniTrendChart(
                            points: snapshot.power.dischargeHistory,
                            color: NomadTheme.coral,
                            yLabel: "Drain",
                            unitLabel: "W",
                            placeholderText: snapshot.power.snapshot?.state == .battery ? "Collecting trend…" : "Plugged in"
                        )
                    }
                }
            }
        }
    }

    private func travelSection(widthMode: DashboardCardWidthMode) -> some View {
        DashboardCard(
            title: "Travel Context",
            subtitle: travelSubtitle,
            badge: travelBadge,
            accessory: cardControls(for: .travelContext, title: "Travel Context"),
            isCompact: widthMode == .narrow
        ) {
            VStack(alignment: .leading, spacing: 10) {
                DetailRow(
                    label: "Public IP",
                    value: publicIPValue,
                    isCompact: widthMode == .narrow,
                    compactLineLimit: 1,
                    action: DetailRowAction(
                        title: "Copy Public IP",
                        systemImage: "document.on.document",
                        isEnabled: snapshot.travelContext.publicIP != nil,
                        action: copyIPAddressAction
                    )
                )
                DetailRow(label: "Wi-Fi", value: snapshot.travelContext.wifi?.ssid ?? "Not connected", isCompact: widthMode == .narrow, compactLineLimit: 1)
                DetailRow(label: "Signal", value: signalDescription(snapshot.travelContext.wifi), isCompact: widthMode == .narrow, compactLineLimit: 2)
                DetailRow(label: "VPN", value: vpnDescription, isCompact: widthMode == .narrow, compactLineLimit: 1)
                DetailRow(label: "Time Zone", value: snapshot.travelContext.timeZoneIdentifier, isCompact: widthMode == .narrow, compactLineLimit: 1)
                DetailRow(
                    label: "Location",
                    value: locationValue,
                    isCompact: widthMode == .narrow,
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
        let unallocatedDuration = timeTrackingDashboardState.todaySummary.unallocatedDuration
        let quickProjects = timeTrackingQuickActionsPresentation.latestProjects(maxCount: isCompact ? 3 : 4)

        return DashboardCard(
            title: "Time Tracking",
            subtitle: timeTrackingSubtitle,
            badge: timeTrackingBadge,
            accessory: cardControls(for: .timeTracking, title: "Time Tracking"),
            isCompact: isCompact
        ) {
            if timeTrackingDashboardState.isEnabled == false {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Track awake working time locally, then allocate today’s pending time into projects or Other.")
                        .font(.caption)
                        .foregroundStyle(NomadTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Open Settings") {
                        openSettingsAction()
                    }
                    .modifier(timeTrackingActionButtonModifier(role: .highlighted, isEnabled: true))
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if isCompact {
                        HStack(spacing: 12) {
                            MetricBlock(title: "Today", value: formattedTrackingDuration(timeTrackingDashboardState.todaySummary.totalTrackedDuration), typography: .compact)
                            MetricBlock(title: "Focus", value: formattedTrackingDuration(timeTrackingDashboardState.todaySummary.focusAdjustedDuration), typography: .compact)
                        }
                    } else {
                        HStack(spacing: 12) {
                            MetricBlock(title: "Today", value: formattedTrackingDuration(timeTrackingDashboardState.todaySummary.totalTrackedDuration), typography: .compact)
                            MetricBlock(title: "Focus", value: formattedTrackingDuration(timeTrackingDashboardState.todaySummary.focusAdjustedDuration), typography: .compact)
                            MetricBlock(title: "Allocated", value: formattedTrackingDuration(timeTrackingDashboardState.todaySummary.totalAllocatedDuration), typography: .compact)
                            MetricBlock(title: "Pending", value: formattedTrackingDuration(unallocatedDuration), typography: .compact)
                        }
                    }

                    HStack(spacing: 10) {
                        TimeTrackingInterruptionButton(
                            title: "Report interruption",
                            count: timeTrackingDashboardState.todaySummary.interruptionCount,
                            lastReportedAt: timeTrackingDashboardState.todaySummary.lastInterruptionAt,
                            isEnabled: true,
                            style: isCompact ? .standard : .prominent,
                            action: reportTimeTrackingInterruptionAction
                        )

                        if isCompact == false {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Estimated focus lost")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(NomadTheme.secondaryText)

                                Text(formattedTrackingDuration(timeTrackingDashboardState.todaySummary.estimatedFocusLossDuration))
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(NomadTheme.primaryText)

                                Text("\(timeTrackingDashboardState.todaySummary.interruptionCount) interruption\(timeTrackingDashboardState.todaySummary.interruptionCount == 1 ? "" : "s") today")
                                    .font(.caption2)
                                    .foregroundStyle(NomadTheme.tertiaryText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(timeTrackingDashboardState.todaySummary.bucketDurations.prefix(isCompact ? 2 : 4)) { bucketDuration in
                            DetailRow(
                                label: timeTrackingBucketTitle(bucketDuration.bucket),
                                value: timeTrackingBucketSummary(bucketDuration),
                                isCompact: isCompact,
                                compactLineLimit: 2
                            )
                        }
                    }

                    if timeTrackingDashboardState.activeProjects.isEmpty == false {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Quick Allocate")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(NomadTheme.tertiaryText)

                            if isCompact {
                                VStack(alignment: .leading, spacing: 6) {
                                    quickAllocateButton(title: timeTrackingQuickActionsPresentation.otherChipTitle, bucket: .other, isCompact: true, isEnabled: unallocatedDuration > 0)
                                    ForEach(quickProjects) { project in
                                        quickAllocateButton(title: project.trimmedName, bucket: .project(project.id), isCompact: true, isEnabled: unallocatedDuration > 0)
                                    }
                                }
                            } else {
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                    quickAllocateButton(title: timeTrackingQuickActionsPresentation.otherChipTitle, bucket: .other, isCompact: false, isEnabled: unallocatedDuration > 0)
                                    ForEach(quickProjects) { project in
                                        quickAllocateButton(title: project.trimmedName, bucket: .project(project.id), isCompact: false, isEnabled: unallocatedDuration > 0)
                                    }
                                }
                            }
                        }
                    } else {
                        Text("Add at least one project in Settings to enable project allocations. Other is always available.")
                            .font(.caption)
                            .foregroundStyle(NomadTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 8) {
                        timeTrackingControlButton(title: timeTrackingPrimaryControlTitle, action: timeTrackingPrimaryControlAction)
                        timeTrackingControlButton(title: "Stop", action: stopTimeTrackingAction)

                        Spacer(minLength: 0)

                        timeTrackingControlButton(title: "Open Time Tracking", action: openTimeTrackingAction)
                    }
                }
            }
        }
    }

    private func weatherSection(widthMode: DashboardCardWidthMode) -> some View {
        let presentation = weatherSectionPresentation
        let forecastPresentation = WeatherForecastPresentation(
            settings: settings,
            weather: snapshot.weather,
            widthMode: widthMode
        )

        return DashboardCard(
            title: "Weather",
            subtitle: presentation.subtitle,
            badge: presentation.badge,
            accessory: cardControls(for: .weather, title: "Weather"),
            isCompact: widthMode == .narrow
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if let weather = snapshot.weather {
                    VStack(alignment: .leading, spacing: 10) {
                        let windPresentation = WeatherWindMetricPresentation(snapshot: weather)

                        if widthMode == .narrow {
                            HStack(spacing: 12) {
                                MetricBlock(
                                    title: "Current",
                                    value: metricValue(weather.currentTemperatureCelsius, formatter: NomadFormatters.celsius, fallback: "Estimating"),
                                    typography: .compact
                                )
                                MetricBlock(
                                    title: "Feels Like",
                                    value: metricValue(weather.apparentTemperatureCelsius, formatter: NomadFormatters.celsius, fallback: "Estimating"),
                                    typography: .compact
                                )
                            }

                            HStack(alignment: .top, spacing: 12) {
                                MetricBlock(
                                    title: "Wind",
                                    value: windPresentation.primaryValue,
                                    typography: .compact
                                )
                                MetricBlock(
                                    title: "Rain Chance",
                                    value: weather.precipitationChance.map { NomadFormatters.precipitation($0) } ?? "n/a",
                                    typography: .compact
                                )
                            }
                        } else {
                            HStack(alignment: .top, spacing: 12) {
                                MetricBlock(
                                    title: "Current",
                                    value: metricValue(weather.currentTemperatureCelsius, formatter: NomadFormatters.celsius, fallback: "Estimating"),
                                    typography: .compact
                                )
                                MetricBlock(
                                    title: "Feels Like",
                                    value: metricValue(weather.apparentTemperatureCelsius, formatter: NomadFormatters.celsius, fallback: "Estimating"),
                                    typography: .compact
                                )
                            }

                            HStack(alignment: .top, spacing: 12) {
                                MetricBlock(
                                    title: "Wind",
                                    value: windPresentation.primaryValue,
                                    secondaryValue: windPresentation.secondaryValue,
                                    typography: .compact
                                )
                                MetricBlock(
                                    title: "Rain Chance",
                                    value: weather.precipitationChance.map { NomadFormatters.precipitation($0) } ?? "n/a",
                                    typography: .compact
                                )
                            }
                        }

                        if forecastPresentation.shouldShowTomorrowSummary,
                           let tomorrow = weather.tomorrow
                        {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Tomorrow")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(NomadTheme.secondaryText)

                                HStack(alignment: .top, spacing: 10) {
                                    Label(tomorrow.summary, systemImage: tomorrow.symbolName)
                                        .foregroundStyle(NomadTheme.primaryText)

                                    Spacer()

                                    Text(temperatureRangeText(for: tomorrow))
                                        .foregroundStyle(NomadTheme.secondaryText)
                                        .multilineTextAlignment(.trailing)
                                }
                            }
                        }

                        if forecastPresentation.showsForecastDisclosure {
                            ForecastDisclosureSection(
                                title: "Forecast",
                                summary: "Next 24h + 7 days",
                                isExpanded: forecastPresentation.isForecastExpanded,
                                action: toggleWeatherForecastExpanded
                            ) {
                                VStack(alignment: .leading, spacing: 10) {
                                    if forecastPresentation.hourlySlots.isEmpty == false {
                                        HStack(spacing: 8) {
                                            ForEach(forecastPresentation.hourlySlots) { slot in
                                                WeatherHourlyForecastChip(model: slot)
                                            }
                                        }
                                    }

                                    if forecastPresentation.hourlySlots.isEmpty == false,
                                       forecastPresentation.dailyRows.isEmpty == false
                                    {
                                        Divider()
                                            .overlay(NomadTheme.cardBorder.opacity(0.8))
                                    }

                                    if forecastPresentation.dailyRows.isEmpty == false {
                                        VStack(alignment: .leading, spacing: 8) {
                                            ForEach(Array(forecastPresentation.dailyRows.enumerated()), id: \.offset) { _, row in
                                                WeatherDailyForecastRow(summary: row)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    WeatherEmptyState(
                        title: presentation.emptyTitle,
                        systemImage: presentation.emptySystemImage,
                        message: presentation.emptyMessage
                    )
                }

                Divider()
                    .overlay(NomadTheme.cardBorder.opacity(0.9))

                surfSection(widthMode: widthMode)

                if widthMode != .narrow {
                    Text(weatherAttributionLine)
                        .font(.caption2)
                        .foregroundStyle(NomadTheme.tertiaryText)
                }
            }
        }
    }

    private func fuelPricesSection(widthMode: DashboardCardWidthMode, viewportHeight: CGFloat) -> some View {
        FuelPricesSectionView(
            presentation: fuelPricesSectionPresentation,
            widthMode: widthMode,
            viewportHeight: viewportHeight,
            accessory: cardControls(for: .fuelPrices, title: "Fuel Prices"),
            openSettingsAction: openSettingsAction,
            previewMapAction: openFuelStationMapPreviewAction,
            openGoogleMapsAction: openFuelStationInGoogleMapsAction
        )
    }

    private func localPriceLevelSection(widthMode: DashboardCardWidthMode) -> some View {
        LocalPriceLevelSectionView(
            presentation: localPriceLevelSectionPresentation,
            widthMode: widthMode,
            accessory: cardControls(for: .localPriceLevel, title: "Local Price Level"),
            openSettingsAction: openSettingsAction
        )
    }

    private func emergencyCareSection(widthMode: DashboardCardWidthMode) -> some View {
        EmergencyCareSectionView(
            presentation: emergencyCareSectionPresentation,
            widthMode: widthMode,
            accessory: cardControls(for: .emergencyCare, title: "Emergency Care"),
            openSettingsAction: openSettingsAction,
            previewMapAction: openEmergencyHospitalMapPreviewAction,
            openGoogleMapsAction: openEmergencyHospitalInGoogleMapsAction
        )
    }

    private func travelAlertsSection(widthMode: DashboardCardWidthMode) -> some View {
        DashboardCard(
            title: "Travel Alerts",
            subtitle: travelAlertsSubtitle,
            badge: travelAlertsBadge,
            accessory: cardControls(for: .travelAlerts, title: "Travel Alerts"),
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
                    ForEach(travelAlertRows) { row in
                        TravelAlertSignalRow(
                            row: row,
                            isCompact: widthMode == .narrow
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

    private var publicIPValue: String {
        if let address = snapshot.travelContext.publicIP?.address {
            return address
        }

        if snapshot.appState.issues.contains(.publicIPLookupUnavailable) {
            return "Lookup unavailable"
        }

        return "Refreshing…"
    }

    private var vpnDescription: String {
        if snapshot.travelContext.vpn?.isActive == true {
            if let serviceNames = snapshot.travelContext.vpn?.serviceNames, serviceNames.isEmpty == false {
                return serviceNames.joined(separator: ", ")
            }

            if let interfaceNames = snapshot.travelContext.vpn?.interfaceNames, interfaceNames.isEmpty == false {
                return interfaceNames.joined(separator: ", ")
            }

            return "Active"
        }

        return "Inactive"
    }

    private var locationValue: String {
        if let location = snapshot.travelContext.location,
           let formattedLocation = formattedLocation(location)
        {
            return formattedLocation
        }

        if snapshot.appState.issues.contains(.ipLocationUnavailable) {
            return "Lookup unavailable"
        }

        if isPublicIPLocationEnabled == false {
            return "Location off"
        }

        return "Refreshing…"
    }

    private func surfSection(widthMode: DashboardCardWidthMode) -> some View {
        let presentation = surfSectionPresentation

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
                        BadgeView(badge: presentation.badge)
                    }
                    .buttonStyle(.plain)
                    .help("Open Surf Spot Settings")
                } else {
                    BadgeView(badge: presentation.badge)
                }
            }

            if let marine = presentation.marine {
                VStack(alignment: .leading, spacing: 10) {
                    if widthMode == .narrow {
                        HStack(spacing: 12) {
                            MetricBlock(title: "Wave", value: presentation.waveSummary, typography: .compact)
                            MetricBlock(title: "Swell", value: presentation.swellSummary, typography: .compact)
                        }

                        MetricBlock(title: "Wind", value: presentation.windSummary, typography: .compact)
                    } else {
                        HStack(spacing: 12) {
                            MetricBlock(title: "Wave", value: presentation.waveSummary, typography: .compact)
                            MetricBlock(title: "Swell", value: presentation.swellSummary, typography: .compact)
                            MetricBlock(title: "Wind", value: presentation.windSummary, typography: .compact)
                        }

                        HStack(spacing: 8) {
                            ForEach(presentation.forecastSlots) { slot in
                                MarineForecastChip(model: slot)
                            }
                        }
                    }

                    if let seaSurfaceTemperature = marine.seaSurfaceTemperatureCelsius {
                        Text("Sea \(NomadFormatters.celsius(seaSurfaceTemperature))")
                            .font(.caption)
                            .foregroundStyle(NomadTheme.secondaryText)
                            .frame(maxWidth: widthMode == .narrow ? .infinity : nil, alignment: widthMode == .narrow ? .center : .leading)
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

    private var localPriceLevelSectionPresentation: LocalPriceLevelSectionPresentation {
        LocalPriceLevelSectionPresentation(
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

    private var compactThroughputSummary: String {
        let download = metricValue(
            snapshot.network.throughput?.downloadMegabitsPerSecond,
            formatter: NomadFormatters.megabitsPerSecond,
            fallback: "Waiting"
        )
        let upload = metricValue(
            snapshot.network.throughput?.uploadMegabitsPerSecond,
            formatter: NomadFormatters.megabitsPerSecond,
            fallback: "Waiting"
        )
        return "Throughput \(download) down · \(upload) up"
    }

    private func compactDrainSummary(_ metrics: PowerMetricsPresentation) -> String {
        "Drain status: \(metrics.drainValue)"
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

    private func cardControls(for cardID: DashboardCardID, title: String) -> AnyView {
        AnyView(
            HStack(spacing: 6) {
                DashboardCardWidthToggleButton(
                    widthMode: resolvedCardWidthModes[cardID] ?? .wide,
                    title: title
                ) {
                    toggleWidthMode(for: cardID)
                }

                DashboardCardDragHandle(cardID: cardID, title: title)
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
        let parts = [location.city, location.country]
            .compactMap { value -> String? in
                guard let value else {
                    return nil
                }

                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }

        guard parts.isEmpty == false else {
            return nil
        }

        return parts.joined(separator: ", ")
    }

    private func temperatureRangeText(for summary: WeatherDaySummary) -> String {
        let minimum = summary.temperatureMinCelsius.map { NomadFormatters.celsius($0) } ?? "Estimating"
        let maximum = summary.temperatureMaxCelsius.map { NomadFormatters.celsius($0) } ?? "Estimating"
        return "\(minimum) / \(maximum)"
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

    private func signalDescription(_ snapshot: WiFiSnapshot?) -> String {
        guard let snapshot else {
            return "Unavailable"
        }

        let pieces = [
            snapshot.rssi.map { "RSSI \($0)" },
            snapshot.noise.map { "Noise \($0)" },
            snapshot.transmitRateMbps.map { String(format: "%.0f Mbps", $0) }
        ]

        let description = pieces.compactMap(\.self).joined(separator: " · ")
        return description.isEmpty ? "Connected" : description
    }

    private var timeTrackingQuickActionsPresentation: TimeTrackingQuickActionsPresentation {
        TimeTrackingQuickActionsPresentation(
            activeProjects: timeTrackingDashboardState.activeProjects,
            recentProjects: timeTrackingDashboardState.recentProjects,
            pendingDurationText: formattedTrackingDuration(timeTrackingDashboardState.todaySummary.unallocatedDuration),
            activityState: timeTrackingDashboardState.activityState
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

    private func quickAllocateButton(title: String, bucket: TimeTrackingBucket, isCompact: Bool, isEnabled: Bool) -> some View {
        Button(title) {
            allocateTimeTrackingAction(bucket)
        }
        .disabled(isEnabled == false)
        .modifier(timeTrackingActionButtonModifier(
            role: .highlighted,
            isEnabled: isEnabled,
            isCompact: isCompact,
            fillsAvailableWidth: true
        ))
    }

    private func timeTrackingControlButton(title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .modifier(timeTrackingActionButtonModifier(role: .neutral, isEnabled: true))
    }

    private func timeTrackingBucketSummary(_ bucketDuration: TimeTrackingBucketDuration) -> String {
        if bucketDuration.interruptionCount == 0 {
            return formattedTrackingDuration(bucketDuration.duration)
        }

        return "\(formattedTrackingDuration(bucketDuration.duration)) · \(bucketDuration.interruptionCount) int · focus \(formattedTrackingDuration(bucketDuration.focusAdjustedDuration))"
    }

    private func timeTrackingActionButtonModifier(
        role: TimeTrackingDashboardActionRole,
        isEnabled: Bool,
        isCompact: Bool = false,
        fillsAvailableWidth: Bool = false
    ) -> some ViewModifier {
        TimeTrackingDashboardActionButtonModifier(
            style: TimeTrackingDashboardActionButtonStyle.make(role: role, isEnabled: isEnabled),
            layout: TimeTrackingDashboardActionButtonLayout.make(
                isCompact: isCompact,
                fillsAvailableWidth: fillsAvailableWidth
            )
        )
    }

    private func formattedTrackingDuration(_ duration: TimeInterval) -> String {
        let totalMinutes = Int((duration / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours == 0 {
            return "\(minutes)m"
        }

        if minutes == 0 {
            return "\(hours)h"
        }

        return "\(hours)h \(minutes)m"
    }

    private func timeTrackingBucketTitle(_ bucket: TimeTrackingBucket) -> String {
        switch bucket {
        case let .project(id):
            return timeTrackingDashboardState.activeProjects.first(where: { $0.id == id })?.trimmedName ?? "Archived Project"
        case .other:
            return "Other"
        case .unallocated:
            return "Unallocated"
        }
    }

}

enum TimeTrackingDashboardActionRole {
    case highlighted
    case neutral
}

struct TimeTrackingDashboardActionButtonStyle: Equatable {
    let foreground: Color
    let background: Color
    let border: Color

    static func make(
        role: TimeTrackingDashboardActionRole,
        isEnabled: Bool
    ) -> TimeTrackingDashboardActionButtonStyle {
        let foreground: Color
        switch role {
        case .highlighted:
            foreground = NomadTheme.teal
        case .neutral:
            foreground = NomadTheme.primaryText
        }

        return TimeTrackingDashboardActionButtonStyle(
            foreground: foreground.opacity(isEnabled ? 1 : 0.72),
            background: NomadTheme.inlineButtonBackground.opacity(isEnabled ? 1 : 0.76),
            border: NomadTheme.cardBorder.opacity(isEnabled ? 1 : 0.76)
        )
    }
}

struct TimeTrackingDashboardActionButtonLayout: Equatable {
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let fillsAvailableWidth: Bool

    static func make(
        isCompact: Bool,
        fillsAvailableWidth: Bool
    ) -> TimeTrackingDashboardActionButtonLayout {
        TimeTrackingDashboardActionButtonLayout(
            horizontalPadding: isCompact ? 10 : 12,
            verticalPadding: isCompact ? 6 : 7,
            fillsAvailableWidth: fillsAvailableWidth
        )
    }
}

private struct TimeTrackingDashboardActionButtonModifier: ViewModifier {
    let style: TimeTrackingDashboardActionButtonStyle
    let layout: TimeTrackingDashboardActionButtonLayout

    func body(content: Content) -> some View {
        if layout.fillsAvailableWidth {
            decorated(content)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            decorated(content)
        }
    }

    private func decorated(_ content: Content) -> some View {
        content
            .font(.caption.weight(.semibold))
            .foregroundStyle(style.foreground)
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.vertical, layout.verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(style.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(style.border, lineWidth: 1)
                    )
            )
            .buttonStyle(.plain)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

struct PowerMetricsPresentation {
    let drainValue: String
    let timeLeftValue: String

    init(snapshot: PowerSnapshot?) {
        guard let snapshot else {
            drainValue = "Estimating"
            timeLeftValue = "Estimating"
            return
        }

        switch snapshot.state {
        case .charging:
            drainValue = "Charging"
            timeLeftValue = snapshot.timeToFullChargeMinutes.map { NomadFormatters.minutes($0) } ?? "Plugged in"
        case .charged:
            drainValue = "Plugged in"
            timeLeftValue = "Plugged in"
        case .battery:
            drainValue = snapshot.dischargeRateWatts.map { NomadFormatters.watts($0) } ?? "On battery"
            timeLeftValue = snapshot.timeRemainingMinutes.map { NomadFormatters.minutes($0) } ?? "Estimating"
        case .unknown:
            drainValue = "Estimating"
            timeLeftValue = "Estimating"
        }
    }
}

private struct DashboardCard<Content: View>: View {
    let title: String
    let subtitle: String
    let subtitleAccessory: AnyView?
    let badge: PillBadge?
    let accessory: AnyView?
    let backgroundDecoration: AnyView?
    let isCompact: Bool
    let content: Content

    init(
        title: String,
        subtitle: String,
        subtitleAccessory: AnyView? = nil,
        badge: PillBadge? = nil,
        accessory: AnyView? = nil,
        backgroundDecoration: AnyView? = nil,
        isCompact: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.subtitleAccessory = subtitleAccessory
        self.badge = badge
        self.accessory = accessory
        self.backgroundDecoration = backgroundDecoration
        self.isCompact = isCompact
        self.content = content()
    }

    var body: some View {
        let cardShape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: isCompact ? .center : .top, spacing: isCompact ? 8 : 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: isCompact ? 15 : 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(NomadTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(isCompact ? 0.75 : 0.9)

                    HStack(spacing: isCompact ? 6 : 8) {
                        Text(subtitle)
                            .font(isCompact ? .caption2 : .caption)
                            .foregroundStyle(NomadTheme.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

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
                }
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: isCompact ? DashboardCompactLayout.cardHeight : nil, alignment: .topLeading)
        .padding(16)
        .background(
            ZStack {
                cardShape
                    .fill(NomadTheme.cardBackground)

                if let backgroundDecoration {
                    backgroundDecoration
                        .clipShape(cardShape)
                }

                cardShape
                    .stroke(NomadTheme.cardBorder, lineWidth: 1)
            }
        )
        .clipped()
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

private enum DashboardCardRenderWidth {
    case full
    case half
}

private enum DashboardCompactLayout {
    static let cardHeight: CGFloat = 320
}

private struct DashboardCardRowItem: Identifiable {
    let cardID: DashboardCardID
    let preferredWidthMode: DashboardCardWidthMode
    let renderWidth: DashboardCardRenderWidth

    var id: DashboardCardID { cardID }
}

private struct DashboardCardRow: Identifiable {
    let items: [DashboardCardRowItem]

    var id: String {
        items.map { $0.cardID.rawValue }.joined(separator: "|")
    }
}

private struct DashboardCardDropTarget<Content: View>: View {
    let isHighlighted: Bool
    let content: () -> Content
    let onDrop: ([String], CGPoint, CGSize) -> Bool
    let isTargeted: (Bool) -> Void

    init(
        isHighlighted: Bool,
        @ViewBuilder content: @escaping () -> Content,
        onDrop: @escaping ([String], CGPoint, CGSize) -> Bool,
        isTargeted: @escaping (Bool) -> Void
    ) {
        self.isHighlighted = isHighlighted
        self.content = content
        self.onDrop = onDrop
        self.isTargeted = isTargeted
    }

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

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: activity == .idle)) { context in
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
            NomadTheme.actionIconForeground
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
            NomadTheme.actionIconBorder
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
        let detail: String
        if let chargePercent = power.snapshot?.chargePercent {
            detail = "\(NomadFormatters.percentage(chargePercent * 100)) · \(health.reason)"
        } else {
            detail = health.reason
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
                .fixedSize(horizontal: false, vertical: true)
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
    }

    let title: String
    let value: String
    var secondaryValue: String?
    var typography: Typography = .standard

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(NomadTheme.tertiaryText)

            Text(value)
                .font(typography.font)
                .foregroundStyle(metricTint)
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

    private var metricTint: Color {
        switch title {
        case "Down", "Time Left", "Current", "Wave":
            NomadTheme.teal
        case "Up", "Battery", "Feels Like", "Swell":
            NomadTheme.sand
        default:
            NomadTheme.coral
        }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String
    let isCompact: Bool
    let compactLineLimit: Int
    let action: DetailRowAction?

    init(
        label: String,
        value: String,
        isCompact: Bool = false,
        compactLineLimit: Int = 1,
        action: DetailRowAction? = nil
    ) {
        self.label = label
        self.value = value
        self.isCompact = isCompact
        self.compactLineLimit = compactLineLimit
        self.action = action
    }

    var body: some View {
        Group {
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
    let ownershipTint: Color?
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

private struct EmergencyHospitalRow: View {
    let model: EmergencyHospitalRowModel
    var isCompact: Bool = false
    let previewMapAction: (EmergencyHospitalMapDestination) -> Void
    let openGoogleMapsAction: (EmergencyHospitalMapDestination) -> Void

    var body: some View {
        Group {
            if isCompact {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.hospitalName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(NomadTheme.primaryText)
                                .lineLimit(2)

                            Text(model.hospitalDetail)
                                .font(.caption2)
                                .foregroundStyle(NomadTheme.secondaryText)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 8)

                        Text(model.distanceText)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(NomadTheme.teal)
                            .lineLimit(1)
                    }

                    HStack(spacing: 8) {
                        if let ownershipTitle = model.ownershipTitle,
                           let ownershipTint = model.ownershipTint
                        {
                            OwnershipBadge(title: ownershipTitle, tint: ownershipTint)
                        }

                        Spacer(minLength: 0)

                        mapActions
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.hospitalName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NomadTheme.primaryText)
                            .lineLimit(2)

                        Text(model.hospitalDetail)
                            .font(.caption2)
                            .foregroundStyle(NomadTheme.secondaryText)
                            .lineLimit(2)

                        if let ownershipTitle = model.ownershipTitle,
                           let ownershipTint = model.ownershipTint
                        {
                            OwnershipBadge(title: ownershipTitle, tint: ownershipTint)
                        }
                    }

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 6) {
                        Text(model.distanceText)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(NomadTheme.teal)
                            .lineLimit(1)

                        mapActions
                    }
                }
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

    @ViewBuilder
    private var mapActions: some View {
        if let destination = model.destination, model.hasMapActions {
            HStack(spacing: isCompact ? 4 : 6) {
                if model.hasPreviewMapAction {
                    FuelRowActionButton(
                        title: "Map",
                        systemImage: "map.fill",
                        isCompact: isCompact
                    ) {
                        previewMapAction(destination)
                    }
                }

                if model.hasGoogleMapsAction {
                    FuelRowActionButton(
                        title: "Google",
                        systemImage: "arrow.up.right.square.fill",
                        isCompact: isCompact
                    ) {
                        openGoogleMapsAction(destination)
                    }
                }
            }
        }
    }
}

private struct OwnershipBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            )
    }
}

struct FuelPriceRowModel: Identifiable, Equatable {
    let id: FuelType
    let title: String
    let stationName: String
    let stationDetail: String
    let priceValue: String
    let updatedText: String?
    let tint: Color
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

    var compactPriceValue: String {
        let filtered = priceValue.filter { $0.isNumber || $0 == "." || $0 == "," }
        return filtered.isEmpty ? priceValue : filtered
    }
}

private struct FuelPriceRow: View {
    let model: FuelPriceRowModel
    var isCompact: Bool = false
    let previewMapAction: (FuelStationMapDestination) -> Void
    let openGoogleMapsAction: (FuelStationMapDestination) -> Void

    var body: some View {
        Group {
            if isCompact {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(NomadTheme.primaryText)

                            Text(model.stationName)
                                .font(.caption)
                                .foregroundStyle(NomadTheme.primaryText)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 8)

                        Text(model.compactPriceValue)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(model.tint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    HStack(alignment: .center, spacing: 8) {
                        if let updatedText = model.updatedText {
                            Text(updatedText)
                                .font(.caption2)
                                .foregroundStyle(NomadTheme.tertiaryText)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)

                        mapActions
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NomadTheme.primaryText)

                        Text(model.stationName)
                            .font(.caption)
                            .foregroundStyle(NomadTheme.primaryText)
                            .lineLimit(1)

                        Text(model.stationDetail)
                            .font(.caption2)
                            .foregroundStyle(NomadTheme.secondaryText)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 3) {
                        Text(model.priceValue)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(model.tint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        if let updatedText = model.updatedText {
                            Text(updatedText)
                                .font(.caption2)
                                .foregroundStyle(NomadTheme.tertiaryText)
                        }

                        mapActions
                    }
                }
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

    @ViewBuilder
    private var mapActions: some View {
        if let stationDestination = model.stationDestination, model.hasMapActions {
            HStack(spacing: isCompact ? 4 : 6) {
                if model.hasPreviewMapAction {
                    FuelRowActionButton(
                        title: "Map",
                        systemImage: "map.fill",
                        isCompact: isCompact
                    ) {
                        previewMapAction(stationDestination)
                    }
                }

                if model.hasGoogleMapsAction {
                    FuelRowActionButton(
                        title: "Google",
                        systemImage: "arrow.up.right.square.fill",
                        isCompact: isCompact
                    ) {
                        openGoogleMapsAction(stationDestination)
                    }
                }
            }
        }
    }
}

private struct FuelRowActionButton: View {
    let title: String
    let systemImage: String
    var isCompact: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: isCompact ? 10 : 11, weight: .semibold))
                .foregroundStyle(NomadTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, isCompact ? 5 : 8)
                .padding(.vertical, isCompact ? 4 : 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(NomadTheme.inlineButtonBackground)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(NomadTheme.cardBorder.opacity(0.85), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

private enum DashboardScrollCoordinateSpace {
    static let name = "DashboardPanelScrollSpace"
}

private struct FuelCardFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect { .null }

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
    let accessory: AnyView
    let openSettingsAction: () -> Void
    let previewMapAction: (EmergencyHospitalMapDestination) -> Void
    let openGoogleMapsAction: (EmergencyHospitalMapDestination) -> Void

    var body: some View {
        DashboardCard(
            title: "Emergency Care",
            subtitle: presentation.subtitle,
            badge: presentation.badge,
            accessory: accessory,
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

private struct LocalPriceLevelSectionView: View {
    let presentation: LocalPriceLevelSectionPresentation
    let widthMode: DashboardCardWidthMode
    let accessory: AnyView
    let openSettingsAction: () -> Void

    var body: some View {
        DashboardCard(
            title: "Local Price Level",
            subtitle: presentation.subtitle,
            badge: presentation.badge,
            accessory: accessory,
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
                            .buttonStyle(.borderedProminent)
                            .tint(Color(nsColor: .controlAccentColor))
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(presentation.rows) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(row.title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(NomadTheme.secondaryText)

                                    Spacer(minLength: 12)

                                    Text(row.value)
                                        .font(widthMode == .narrow ? .subheadline.weight(.semibold) : .headline)
                                        .foregroundStyle(NomadTheme.primaryText)
                                }

                                Text(row.detail)
                                    .font(.caption)
                                    .foregroundStyle(NomadTheme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
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

private struct FuelPricesSectionView: View {
    let presentation: FuelPricesSectionPresentation
    let widthMode: DashboardCardWidthMode
    let viewportHeight: CGFloat
    let accessory: AnyView
    let openSettingsAction: () -> Void
    let previewMapAction: (FuelStationMapDestination) -> Void
    let openGoogleMapsAction: (FuelStationMapDestination) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cardFrame: CGRect = .null

    var body: some View {
        let animationState = fuelBackdropAnimationState(
            frame: cardFrame,
            viewportHeight: viewportHeight,
            visualMode: presentation.visualMode,
            reduceMotion: reduceMotion
        )

        DashboardCard(
            title: "Fuel Prices",
            subtitle: presentation.subtitle,
            badge: presentation.badge,
            accessory: accessory,
            backgroundDecoration: AnyView(
                FuelCardBackdrop(
                    visualMode: presentation.visualMode,
                    badgeTint: presentation.badge.tint,
                    isAnimating: animationState.isAnimating,
                    isCompact: widthMode == .narrow
                )
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
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
            return lastResolvedPhase
        case .ambient, .staticScene:
            return 0.18
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
                Capsule(style: .continuous)
                    .fill(index == 1 ? NomadTheme.teal.opacity(0.06) : NomadTheme.fuelGlow.opacity(0.05))
                    .frame(width: max(22, metrics.width * (0.11 - CGFloat(index) * 0.018)), height: 7)
                    .rotationEffect(.degrees(Double(index * 6) - 7))
                    .offset(
                        x: metrics.width * (xFractions[index] - 0.5) + CGFloat(drift) * metrics.width * 0.04,
                        y: -metrics.height * 0.15 + CGFloat(index) * 10
                    )
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
    let freshnessText: String
    let metadataText: String
    let sourceName: String
    let count: Int?
    let severity: TravelAlertSeverity
    let tint: Color
    let symbolName: String
    let status: TravelAlertSignalStatus

    static func == (lhs: TravelAlertRowModel, rhs: TravelAlertRowModel) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.statusLabel == rhs.statusLabel
            && lhs.impactText == rhs.impactText
            && lhs.summary == rhs.summary
            && lhs.freshnessText == rhs.freshnessText
            && lhs.metadataText == rhs.metadataText
            && lhs.sourceName == rhs.sourceName
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
            return row.id.rawValue
        case let .overflow(count):
            return "overflow-\(count)"
        }
    }
}

struct TravelAlertsCardPresentation: Equatable {
    let badge: TravelAlertsBadgePresentation
    let rows: [TravelAlertRowModel]
    let showsAllClearRow: Bool

    init(preferences: TravelAlertPreferences, snapshot: TravelAlertsSnapshot?) {
        guard preferences.enabledKinds.isEmpty == false else {
            badge = .off
            rows = []
            showsAllClearRow = false
            return
        }

        guard let snapshot else {
            badge = .checking
            rows = []
            showsAllClearRow = false
            return
        }

        rows = preferences.enabledKinds.compactMap { kind in
            guard let state = snapshot.state(for: kind) else {
                return nil
            }

            return TravelAlertRowModel(state: state)
        }

        showsAllClearRow = snapshot.allResolvedClear
        badge = TravelAlertsBadgePresentation.resolve(for: snapshot)
    }
}

enum TravelAlertsBadgePresentation: Equatable {
    case off
    case checking
    case limited
    case stale
    case severity(TravelAlertSeverity)

    fileprivate var pillBadge: PillBadge {
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

    fileprivate static func resolve(for snapshot: TravelAlertsSnapshot) -> TravelAlertsBadgePresentation {
        let highestSeverity = snapshot.states.compactMap(\.highestSeverity).max()

        if let highestSeverity, highestSeverity >= .warning {
            return .severity(highestSeverity)
        }

        if snapshot.hasStaleStates {
            return .stale
        }

        if snapshot.hasUnavailableStates {
            return .limited
        }

        if let highestSeverity {
            return .severity(highestSeverity)
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
                freshnessText: freshnessText,
                metadataText: [sourceName, freshnessText].filter { $0.isEmpty == false }.joined(separator: " · "),
                sourceName: sourceName,
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
                freshnessText: freshnessText,
                metadataText: [sourceName, freshnessText].filter { $0.isEmpty == false }.joined(separator: " · "),
                sourceName: sourceName,
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
                freshnessText: freshnessText,
                metadataText: [sourceName, freshnessText].filter { $0.isEmpty == false }.joined(separator: " · "),
                sourceName: sourceName,
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
                freshnessText: freshnessText,
                metadataText: [sourceName, freshnessText].filter { $0.isEmpty == false }.joined(separator: " · "),
                sourceName: sourceName,
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
    var isCompact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 8 : 10) {
            HStack(alignment: .top, spacing: 12) {
                Text(row.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NomadTheme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                BadgeView(
                    badge: PillBadge(
                        title: row.statusLabel,
                        symbolName: row.symbolName,
                        tint: row.tint
                    )
                )
            }

            Text(row.impactText.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(row.tint.opacity(0.92))
                .tracking(0.4)

            Text(row.summary)
                .font(isCompact ? .caption : .caption)
                .foregroundStyle(NomadTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

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
}

private struct BadgeView: View {
    let badge: PillBadge
    var isCompact: Bool = false

    var body: some View {
        Group {
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
}

private struct ThroughputTrendChart: View {
    let downloadPoints: [MetricPoint]
    let uploadPoints: [MetricPoint]
    var isCompact: Bool = false

    var body: some View {
        let downloadSeries = renderablePoints(downloadPoints)
        let uploadSeries = renderablePoints(uploadPoints)

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Throughput")
                    .font(.caption2)
                    .foregroundStyle(NomadTheme.tertiaryText)

                Spacer()

                HStack(spacing: isCompact ? 6 : 10) {
                    if downloadSeries != nil {
                        TrendLegendItem(title: "Down", color: NomadTheme.teal)
                    }

                    if uploadSeries != nil {
                        TrendLegendItem(title: "Up", color: NomadTheme.sand)
                    }
                }
            }

            if downloadSeries == nil, uploadSeries == nil {
                ChartPlaceholder(unitLabel: "Mbps", message: "Collecting trend…")
            } else {
                Chart {
                    if let downloadSeries {
                        ForEach(downloadSeries) { point in
                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Download", point.value)
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(NomadTheme.teal)

                            AreaMark(
                                x: .value("Time", point.timestamp),
                                yStart: .value("Base", 0),
                                yEnd: .value("Download", point.value)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [NomadTheme.teal.opacity(0.30), NomadTheme.teal.opacity(0.02)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        }
                    }

                    if let uploadSeries {
                        ForEach(uploadSeries) { point in
                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Upload", point.value)
                            )
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                            .foregroundStyle(NomadTheme.sand)
                        }
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(maxWidth: .infinity)
                .frame(height: 82)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(isCompact ? 8 : 10)
        .background(chartContainerBackground)
    }

    private var chartContainerBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(NomadTheme.chartBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(NomadTheme.cardBorder.opacity(0.9), lineWidth: 1)
            )
    }
}

private struct MiniTrendChart: View {
    let points: [MetricPoint]
    let color: Color
    let yLabel: String
    let unitLabel: String
    var placeholderText: String = "Collecting trend…"
    var isCompact: Bool = false

    var body: some View {
        let series = renderablePoints(points)

        VStack(alignment: .leading, spacing: 6) {
            Text(yLabel)
                .font(.caption2)
                .foregroundStyle(NomadTheme.tertiaryText)

            if let series {
                Chart(series) {
                    LineMark(
                        x: .value("Time", $0.timestamp),
                        y: .value("Value", $0.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(color)

                    AreaMark(
                        x: .value("Time", $0.timestamp),
                        yStart: .value("Base", 0),
                        yEnd: .value("Value", $0.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [color.opacity(0.35), color.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(maxWidth: .infinity)
                .frame(height: 82)
            } else {
                ChartPlaceholder(unitLabel: unitLabel, message: placeholderText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(isCompact ? 8 : 10)
        .background(chartContainerBackground)
    }

    private var chartContainerBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(NomadTheme.chartBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(NomadTheme.cardBorder.opacity(0.9), lineWidth: 1)
            )
    }
}

private struct WeatherEmptyState: View {
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
                        .buttonStyle(.link)
                        .font(.caption.weight(.semibold))
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
            subtitle = weather.conditionDescription
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
    let hourlySlots: [WeatherHourlyForecastSlotPresentation]
    let dailyRows: [WeatherDaySummary]
    let isForecastExpanded: Bool
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
        let canShowExpandedForecast = widthMode != .narrow
        isForecastExpanded = canShowExpandedForecast && settings.weatherForecastExpanded
        showsForecastDisclosure = canShowExpandedForecast && (hourlySlots.isEmpty == false || dailyRows.isEmpty == false)
        shouldShowTomorrowSummary = weather.tomorrow != nil && (showsForecastDisclosure == false || isForecastExpanded == false)
    }
}

struct WeatherHourlyForecastSlotPresentation: Identifiable, Equatable {
    let id: String
    let title: String
    let symbolName: String
    let temperatureValue: String
    let detailValue: String

    init(index: Int, slot: WeatherHourlyForecastSlot, referenceDate: Date) {
        id = "\(index)-\(slot.date.timeIntervalSinceReferenceDate)"
        let hourOffset = max(0, Int((slot.date.timeIntervalSince(referenceDate) / 3_600).rounded()))
        title = "+\(hourOffset)h"
        symbolName = slot.symbolName
        temperatureValue = NomadFormatters.celsius(slot.temperatureCelsius)
        detailValue = Self.detailValue(for: slot)
    }

    private static func detailValue(for slot: WeatherHourlyForecastSlot) -> String {
        let rainValue = slot.precipitationChance.map { "Rain \(NomadFormatters.precipitation($0))" }
        let windSummary = WeatherWindMetricPresentation.summary(
            speedKph: slot.windSpeedKph,
            directionDegrees: slot.windDirectionDegrees
        )
        let windValue = windSummary == "n/a" ? nil : windSummary
        let parts = [rainValue, windValue].compactMap(\.self)

        if parts.isEmpty == false {
            return parts.joined(separator: " · ")
        }

        return slot.conditionDescription
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
    let summary: String
    let isExpanded: Bool
    let action: () -> Void
    let content: Content

    init(
        title: String,
        summary: String,
        isExpanded: Bool,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.summary = summary
        self.isExpanded = isExpanded
        self.action = action
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: action) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NomadTheme.primaryText)

                        Text(summary)
                            .font(.caption2)
                            .foregroundStyle(NomadTheme.secondaryText)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(NomadTheme.tertiaryText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
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

            if isExpanded {
                content
            }
        }
    }
}

private struct WeatherHourlyForecastChip: View {
    let model: WeatherHourlyForecastSlotPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(NomadTheme.tertiaryText)

            Label(model.temperatureValue, systemImage: model.symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NomadTheme.primaryText)
                .lineLimit(1)

            Text(model.detailValue)
                .font(.caption2)
                .foregroundStyle(NomadTheme.secondaryText)
                .lineLimit(2)
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
                    priceValue: NomadFormatters.fuelPricePerLiter(station.pricePerLiter),
                    updatedText: station.updatedAt.map { "Updated \(NomadFormatters.compactClockTime($0))" },
                    tint: station.fuelType == .diesel ? NomadTheme.teal : NomadTheme.sand,
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

struct LocalPriceLevelRowModel: Identifiable {
    let id: LocalPriceIndicatorKind
    let title: String
    let value: String
    let detail: String

    init(row: LocalPriceIndicatorRow) {
        id = row.kind
        title = row.kind.displayName
        value = row.value
        detail = row.detail
    }
}

struct LocalPriceLevelSectionPresentation {
    let badge: PillBadge
    let subtitle: String
    let rows: [LocalPriceLevelRowModel]
    let emptyTitle: String
    let emptySystemImage: String
    let emptyMessage: String
    let emptyActionTitle: String?
    let sourceLine: String?
    let note: String?

    init(
        settings: AppSettings,
        snapshot: DashboardSnapshot,
        locationStatusDetail: String?
    ) {
        guard settings.localPriceLevelEnabled else {
            badge = PillBadge(title: "Off", symbolName: "wallet.pass.fill", tint: NomadTheme.primaryText)
            subtitle = "Traveller price levels are disabled"
            rows = []
            emptyTitle = "Local Price Level Off"
            emptySystemImage = "wallet.pass.fill"
            emptyMessage = "Enable local price level in Settings."
            emptyActionTitle = "Open Settings"
            sourceLine = nil
            note = nil
            return
        }

        guard let localPriceLevel = snapshot.localPriceLevel else {
            badge = PillBadge(title: "Checking", symbolName: "creditcard.viewfinder", tint: NomadTheme.secondaryText)
            subtitle = "Looking up price levels"
            rows = []
            emptyTitle = "Checking Local Price Level"
            emptySystemImage = "creditcard.viewfinder"
            emptyMessage = "Looking up meal, grocery, rent, and overall price signals."
            emptyActionTitle = nil
            sourceLine = nil
            note = nil
            return
        }

        rows = localPriceLevel.rows.map(LocalPriceLevelRowModel.init)
        sourceLine = localPriceLevel.sources.isEmpty ? nil : "Sources: " + localPriceLevel.sources.map(\.name).joined(separator: " · ")
        note = [localPriceLevel.detail, localPriceLevel.note]
            .compactMap(\.self)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
            .nilIfEmpty

        let subtitleCountry = localPriceLevel.countryName ?? "Current country"
        let precisionSummary = localPriceLevel.rows.map { $0.precision.displayName }
            .reduce(into: [String]()) { result, value in
                if result.contains(value) == false {
                    result.append(value)
                }
            }
            .joined(separator: " · ")

        switch localPriceLevel.status {
        case .ready, .partial:
            badge = Self.badge(for: localPriceLevel)
            subtitle = [subtitleCountry, precisionSummary.nilIfEmpty]
                .compactMap(\.self)
                .joined(separator: " · ")
            emptyTitle = ""
            emptySystemImage = "creditcard.viewfinder"
            emptyMessage = ""
            emptyActionTitle = nil
        case .locationRequired:
            badge = PillBadge(title: "Location Needed", symbolName: "location.slash.fill", tint: NomadTheme.sand)
            subtitle = "Country context is required"
            emptyTitle = "Location Needed"
            emptySystemImage = "location.slash.fill"
            emptyMessage = locationStatusDetail ?? localPriceLevel.detail ?? "Allow location access or enable external IP location."
            emptyActionTitle = "Open Settings"
        case .configurationRequired:
            badge = PillBadge(title: "Setup", symbolName: "key.fill", tint: NomadTheme.sand)
            subtitle = subtitleCountry
            emptyTitle = "Source Setup Needed"
            emptySystemImage = "key.fill"
            emptyMessage = localPriceLevel.detail ?? "This source needs extra configuration."
            emptyActionTitle = "Open Settings"
        case .unsupported:
            badge = PillBadge(title: "Unsupported", symbolName: "globe.badge.chevron.backward", tint: NomadTheme.primaryText)
            subtitle = subtitleCountry
            emptyTitle = "Region Unsupported"
            emptySystemImage = "globe.badge.chevron.backward"
            emptyMessage = localPriceLevel.detail ?? "Local price level is not supported here yet."
            emptyActionTitle = nil
        case .unavailable:
            badge = PillBadge(title: "Unavailable", symbolName: "wifi.exclamationmark", tint: NomadTheme.primaryText)
            subtitle = subtitleCountry
            emptyTitle = "Local Price Level Unavailable"
            emptySystemImage = "wifi.exclamationmark"
            emptyMessage = localPriceLevel.detail ?? "Local price level is unavailable right now."
            emptyActionTitle = nil
        }
    }

    private static func badge(for snapshot: LocalPriceLevelSnapshot) -> PillBadge {
        switch snapshot.summaryBand {
        case .low:
            PillBadge(title: "Low", symbolName: "arrow.down.circle.fill", tint: NomadTheme.teal)
        case .high:
            PillBadge(title: "High", symbolName: "arrow.up.circle.fill", tint: NomadTheme.coral)
        case .limited:
            PillBadge(title: "Limited", symbolName: "ellipsis.circle.fill", tint: NomadTheme.sand)
        case .medium, .none:
            PillBadge(title: "Medium", symbolName: "equal.circle.fill", tint: NomadTheme.sand)
        }
    }
}

struct EmergencyCareSectionPresentation {
    let badge: PillBadge
    let subtitle: String
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
            rows = []
            emptyTitle = "Emergency Care Off"
            emptySystemImage = "cross.case"
            emptyMessage = "Enable nearby emergency hospitals in Settings."
            emptyActionTitle = "Open Settings"
            return
        }

        guard let emergencyCare = snapshot.emergencyCare else {
            badge = PillBadge(title: "Checking", symbolName: "cross.case.fill", tint: NomadTheme.secondaryText)
            subtitle = "Looking for nearby hospitals"
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
            subtitle = "Within \(Int(emergencyCare.searchRadiusKilometers)) km"
            rows = emergencyCare.hospitals.map { hospital in
                EmergencyHospitalRowModel(
                    id: hospital.id,
                    hospitalName: hospital.name,
                    hospitalDetail: Self.hospitalDetail(for: hospital),
                    distanceText: NomadFormatters.kilometers(hospital.distanceKilometers),
                    ownershipTitle: hospital.ownership == .unknown ? nil : hospital.ownership.displayName,
                    ownershipTint: Self.ownershipTint(for: hospital.ownership),
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
            subtitle = "Precise location is required"
            rows = []
            emptyTitle = "Current Location Needed"
            emptySystemImage = "location.slash.fill"
            emptyMessage = locationStatusDetail ?? emergencyCare.detail ?? "Allow current location to look up nearby emergency hospitals."
            emptyActionTitle = "Open Settings"
        case .unavailable:
            badge = PillBadge(title: "Unavailable", symbolName: "wifi.exclamationmark", tint: NomadTheme.primaryText)
            subtitle = emergencyCare.sourceName
            rows = []
            emptyTitle = "Emergency Care Unavailable"
            emptySystemImage = "wifi.exclamationmark"
            emptyMessage = emergencyCare.detail ?? "Nearby emergency hospitals are unavailable right now."
            emptyActionTitle = nil
        case .noHospitalsFound:
            badge = PillBadge(title: "No Matches", symbolName: "mappin.slash", tint: NomadTheme.primaryText)
            subtitle = "Within \(Int(emergencyCare.searchRadiusKilometers)) km"
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

    private static func ownershipTint(for ownership: HospitalOwnership) -> Color? {
        switch ownership {
        case .public:
            NomadTheme.teal
        case .private:
            NomadTheme.sand
        case .unknown:
            nil
        }
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
            "\(NomadFormatters.kilometersPerHour($0)) · \(NomadFormatters.compassDirection(slot.windDirectionDegrees))"
        } ?? "n/a"
    }
}

private struct MarineForecastChip: View {
    let model: SurfForecastSlotPresentation
    var isCompact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(NomadTheme.tertiaryText)

            Text(model.waveValue)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NomadTheme.primaryText)

            Text(model.windValue)
                .font(.caption2)
                .foregroundStyle(NomadTheme.secondaryText)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(isCompact ? 8 : 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(NomadTheme.chartBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(NomadTheme.cardBorder.opacity(0.9), lineWidth: 1)
                )
        )
    }
}

private struct ChartPlaceholder: View {
    let unitLabel: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(unitLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(NomadTheme.tertiaryText)

            Spacer()

            Text(message)
                .font(.caption)
                .foregroundStyle(NomadTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 82)
    }
}

private struct TrendLegendItem: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(NomadTheme.secondaryText)
        }
    }
}

struct PillBadge {
    let title: String
    let symbolName: String
    let tint: Color
}

private func renderablePoints(_ points: [MetricPoint]) -> [MetricPoint]? {
    guard points.count >= 3 else {
        return nil
    }

    guard let minimum = points.map(\.value).min(),
          let maximum = points.map(\.value).max(),
          abs(maximum - minimum) > 0.01
    else {
        return nil
    }

    return points
}

private extension HealthLevel {
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
