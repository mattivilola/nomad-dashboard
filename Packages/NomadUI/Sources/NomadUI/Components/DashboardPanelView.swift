import Charts
import NomadCore
import SwiftUI

public struct DashboardPanelView: View {
    private let snapshot: DashboardSnapshot
    private let isPublicIPLocationEnabled: Bool
    private let travelAlertPreferences: TravelAlertPreferences
    private let versionDescription: String
    private let refreshAction: () -> Void
    private let toggleAppearanceAction: () -> Void
    private let copyIPAddressAction: () -> Void
    private let openVisitedMapAction: () -> Void
    private let openNetworkSettingsAction: () -> Void
    private let checkForUpdatesAction: (() -> Void)?
    private let openSettingsAction: () -> Void
    private let openAboutAction: () -> Void
    private let quitAction: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    public init(
        snapshot: DashboardSnapshot,
        isPublicIPLocationEnabled: Bool,
        travelAlertPreferences: TravelAlertPreferences,
        versionDescription: String = "",
        refreshAction: @escaping () -> Void,
        toggleAppearanceAction: @escaping () -> Void,
        copyIPAddressAction: @escaping () -> Void,
        openVisitedMapAction: @escaping () -> Void,
        openNetworkSettingsAction: @escaping () -> Void,
        checkForUpdatesAction: (() -> Void)? = nil,
        openSettingsAction: @escaping () -> Void,
        openAboutAction: @escaping () -> Void,
        quitAction: @escaping () -> Void
    ) {
        self.snapshot = snapshot
        self.isPublicIPLocationEnabled = isPublicIPLocationEnabled
        self.travelAlertPreferences = travelAlertPreferences
        self.versionDescription = versionDescription
        self.refreshAction = refreshAction
        self.toggleAppearanceAction = toggleAppearanceAction
        self.copyIPAddressAction = copyIPAddressAction
        self.openVisitedMapAction = openVisitedMapAction
        self.openNetworkSettingsAction = openNetworkSettingsAction
        self.checkForUpdatesAction = checkForUpdatesAction
        self.openSettingsAction = openSettingsAction
        self.openAboutAction = openAboutAction
        self.quitAction = quitAction
    }

    public var body: some View {
        ZStack {
            NomadTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    summaryStrip
                    connectivitySection
                    powerSection
                    travelSection
                    travelAlertsSection
                    weatherSection
                    footer
                }
                .padding(18)
            }
        }
        .frame(width: 430, height: 640)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Nomad Dashboard")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(NomadTheme.primaryText)

                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    Text(snapshot.travelContext.location.flatMap(formattedLocation) ?? "Travel-ready system telemetry")
                        .font(.subheadline)
                        .foregroundStyle(NomadTheme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 12)

                    Text("Last refresh \(NomadFormatters.relativeDate(snapshot.appState.lastRefresh))")
                        .font(.caption)
                        .foregroundStyle(NomadTheme.tertiaryText)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                HeaderIconButton(systemImage: "arrow.clockwise", title: "Refresh", action: refreshAction)
                HeaderIconButton(systemImage: appearanceToggleSystemImage, title: appearanceToggleTitle, action: toggleAppearanceAction)

                Menu {
                    Button("Open Visited Map", systemImage: "globe.europe.africa.fill") {
                        openVisitedMapAction()
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
    }

    private var summaryStrip: some View {
        HStack(spacing: 10) {
            SummaryTile(title: "Overall", health: snapshot.healthSummary.overall)
            SummaryTile(title: "Network", health: snapshot.healthSummary.network)
            SummaryTile(title: "Power", health: snapshot.healthSummary.power)
        }
    }

    private var connectivitySection: some View {
        DashboardCard(
            title: "Connectivity",
            subtitle: snapshot.network.throughput?.activeInterface ?? "Interface unavailable",
            badge: badge(for: snapshot.healthSummary.network)
        ) {
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

    private var powerSection: some View {
        DashboardCard(
            title: "Power",
            subtitle: snapshot.power.snapshot.map(powerSubtitle) ?? "Power source unavailable",
            badge: badge(for: snapshot.healthSummary.power)
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    MetricBlock(
                        title: "Battery",
                        value: metricValue(snapshot.power.snapshot?.chargePercent.map { $0 * 100 }, formatter: NomadFormatters.percentage, fallback: "Estimating")
                    )
                    MetricBlock(title: "Drain", value: drainValue)
                    MetricBlock(title: "Time Left", value: timeLeftValue)
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

    private var travelSection: some View {
        DashboardCard(
            title: "Travel Context",
            subtitle: travelSubtitle,
            badge: travelBadge
        ) {
            VStack(alignment: .leading, spacing: 10) {
                DetailRow(
                    label: "Public IP",
                    value: publicIPValue,
                    action: DetailRowAction(
                        title: "Copy Public IP",
                        systemImage: "document.on.document",
                        isEnabled: snapshot.travelContext.publicIP != nil,
                        action: copyIPAddressAction
                    )
                )
                DetailRow(label: "Wi-Fi", value: snapshot.travelContext.wifi?.ssid ?? "Not connected")
                DetailRow(label: "Signal", value: signalDescription(snapshot.travelContext.wifi))
                DetailRow(label: "VPN", value: vpnDescription)
                DetailRow(label: "Time Zone", value: snapshot.travelContext.timeZoneIdentifier)
                DetailRow(
                    label: "Location",
                    value: locationValue,
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

    private var weatherSection: some View {
        DashboardCard(
            title: "Weather",
            subtitle: weatherSubtitle,
            badge: weatherBadge
        ) {
            if let weather = snapshot.weather {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        MetricBlock(
                            title: "Current",
                            value: metricValue(weather.currentTemperatureCelsius, formatter: NomadFormatters.celsius, fallback: "Estimating")
                        )
                        MetricBlock(
                            title: "Feels Like",
                            value: metricValue(weather.apparentTemperatureCelsius, formatter: NomadFormatters.celsius, fallback: "Estimating")
                        )
                        MetricBlock(
                            title: "Rain",
                            value: weather.precipitationChance.map { NomadFormatters.precipitation($0) } ?? "Estimating"
                        )
                    }

                    if let tomorrow = weather.tomorrow {
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
                }
            } else {
                WeatherEmptyState(
                    title: weatherBadge.title,
                    systemImage: weatherBadge.symbolName,
                    message: weatherEmptyMessage
                )
            }
        }
    }

    private var travelAlertsSection: some View {
        DashboardCard(
            title: "Travel Alerts",
            subtitle: travelAlertsSubtitle,
            badge: travelAlertsBadge
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
                        CompactAlertRow(
                            title: row.title,
                            summary: row.summary,
                            sourceName: row.sourceName,
                            count: row.count,
                            tint: row.tint,
                            symbolName: row.symbolName
                        )
                    }
                }
            }
        }
    }

    private var footer: some View {
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
    }

    private var appearanceToggleSystemImage: String {
        colorScheme == .dark ? "sun.max.fill" : "moon.fill"
    }

    private var appearanceToggleTitle: String {
        colorScheme == .dark ? "Switch to Light Appearance" : "Switch to Dark Appearance"
    }

    private var jitterDescription: String {
        if let jitter = snapshot.network.latency?.jitterMilliseconds {
            return "Jitter \(NomadFormatters.latency(jitter)) via \(snapshot.network.latency?.host ?? "n/a")"
        }

        return "Jitter will appear after the next slow refresh"
    }

    private var drainValue: String {
        guard let powerSnapshot = snapshot.power.snapshot else {
            return "Estimating"
        }

        switch powerSnapshot.state {
        case .charging:
            return "Charging"
        case .charged:
            return "Plugged in"
        case .battery:
            return powerSnapshot.dischargeRateWatts.map { NomadFormatters.watts($0) } ?? "Estimating"
        case .unknown:
            return "Estimating"
        }
    }

    private var timeLeftValue: String {
        guard let powerSnapshot = snapshot.power.snapshot else {
            return "Estimating"
        }

        switch powerSnapshot.state {
        case .charging:
            return "Plugged in"
        case .charged:
            return "Plugged in"
        case .battery:
            return powerSnapshot.timeRemainingMinutes.map { NomadFormatters.minutes($0) } ?? "Estimating"
        case .unknown:
            return "Estimating"
        }
    }

    private var travelSubtitle: String {
        if let location = snapshot.travelContext.location,
           let formattedLocation = formattedLocation(location) {
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
           let formattedLocation = formattedLocation(location) {
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

    private var weatherBadge: PillBadge {
        if snapshot.weather != nil {
            return PillBadge(title: "Live", symbolName: "cloud.sun.fill", tint: NomadTheme.teal)
        }

        if snapshot.appState.issues.contains(.weatherLocationRequired) {
            return PillBadge(title: "Location Needed", symbolName: "location.slash.fill", tint: NomadTheme.sand)
        }

        return PillBadge(title: "Unavailable", symbolName: "cloud.slash.fill", tint: NomadTheme.primaryText)
    }

    private var weatherSubtitle: String {
        if let weather = snapshot.weather {
            return weather.conditionDescription
        }

        if snapshot.appState.issues.contains(.weatherLocationRequired) {
            return "Location permission required"
        }

        return "Weather data unavailable"
    }

    private var weatherEmptyMessage: String {
        if snapshot.appState.issues.contains(.weatherLocationRequired) {
            return "Allow current location to load local weather."
        }

        return "Weather data is not available yet."
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

    private var travelAlertsPresentation: TravelAlertsCardPresentation {
        TravelAlertsCardPresentation(
            preferences: travelAlertPreferences,
            snapshot: snapshot.travelAlerts
        )
    }

    private func badge(for health: SectionHealth) -> PillBadge {
        PillBadge(title: health.label, symbolName: health.symbolName, tint: health.level.tint)
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
            return "Running on battery"
        case .charging:
            return "Charging"
        case .charged:
            return "Connected to power"
        case .unknown:
            return "Power status unavailable"
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

        let description = pieces.compactMap { $0 }.joined(separator: " · ")
        return description.isEmpty ? "Connected" : description
    }
}

private struct DashboardCard<Content: View>: View {
    let title: String
    let subtitle: String
    let badge: PillBadge?
    let accessory: AnyView?
    let content: Content

    init(
        title: String,
        subtitle: String,
        badge: PillBadge? = nil,
        accessory: AnyView? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.badge = badge
        self.accessory = accessory
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(NomadTheme.primaryText)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(NomadTheme.secondaryText)
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    if let badge {
                        BadgeView(badge: badge)
                    }

                    if let accessory {
                        accessory
                    }
                }
            }

            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(NomadTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(NomadTheme.cardBorder, lineWidth: 1)
                )
        )
    }
}

private struct HeaderIconButton: View {
    let systemImage: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HeaderActionIcon(systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

private struct HeaderActionIcon: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(NomadTheme.actionIconForeground)
            .frame(width: 34, height: 34)
            .background(
                Circle()
                    .fill(NomadTheme.actionIconBackground)
                    .overlay(
                        Circle()
                            .stroke(NomadTheme.actionIconBorder, lineWidth: 1)
                    )
            )
    }
}

private struct SummaryTile: View {
    let title: String
    let health: SectionHealth

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(NomadTheme.tertiaryText)

            Label(health.label, systemImage: health.symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(health.level.tint)
                .lineLimit(1)

            Text(health.reason)
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
                        .stroke(health.level.tint.opacity(0.18), lineWidth: 1)
                )
        )
    }
}

private struct MetricBlock: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(NomadTheme.tertiaryText)

            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(metricTint)
                .lineLimit(2)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metricTint: Color {
        switch title {
        case "Down", "Time Left", "Current":
            NomadTheme.teal
        case "Up", "Battery", "Feels Like":
            NomadTheme.sand
        default:
            NomadTheme.coral
        }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String
    let action: DetailRowAction?

    init(label: String, value: String, action: DetailRowAction? = nil) {
        self.label = label
        self.value = value
        self.action = action
    }

    var body: some View {
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

    var body: some View {
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
                    Text("\(count)")
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
        }
        .padding(.vertical, 2)
    }
}

struct TravelAlertRowModel: Identifiable, Equatable {
    let id: TravelAlertKind
    let title: String
    let summary: String
    let sourceName: String
    let count: Int?
    let severity: TravelAlertSeverity
    let tint: Color
    let symbolName: String
    let status: TravelAlertSignalStatus

    static func == (lhs: TravelAlertRowModel, rhs: TravelAlertRowModel) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.summary == rhs.summary
            && lhs.sourceName == rhs.sourceName
            && lhs.count == rhs.count
            && lhs.severity == rhs.severity
            && lhs.symbolName == rhs.symbolName
            && lhs.status == rhs.status
    }
}

struct TravelAlertsCardPresentation: Equatable {
    let badge: TravelAlertsBadgePresentation
    let rows: [TravelAlertRowModel]
    let showsAllClearRow: Bool

    init(preferences: TravelAlertPreferences, snapshot: TravelAlertsSnapshot?) {
        guard preferences.enabledKinds.isEmpty == false else {
            self.badge = .off
            self.rows = []
            self.showsAllClearRow = false
            return
        }

        guard let snapshot else {
            self.badge = .checking
            self.rows = []
            self.showsAllClearRow = false
            return
        }

        self.rows = preferences.enabledKinds.compactMap { kind in
            guard let state = snapshot.state(for: kind) else {
                return nil
            }

            return TravelAlertRowModel(state: state)
        }

        self.showsAllClearRow = snapshot.allResolvedClear
        self.badge = TravelAlertsBadgePresentation.resolve(for: snapshot)
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

        switch state.status {
        case .checking:
            self.init(
                id: state.kind,
                title: title,
                summary: "Checking alerts…",
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
                summary: signal?.summary ?? "No current alerts.",
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
                summary: summary,
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
                summary: state.reason?.summary ?? "Source unavailable",
                sourceName: sourceName,
                count: nil,
                severity: .info,
                tint: NomadTheme.sand,
                symbolName: "exclamationmark.triangle.fill",
                status: .unavailable
            )
        }
    }
}

private struct BadgeView: View {
    let badge: PillBadge

    var body: some View {
        Label(badge.title, systemImage: badge.symbolName)
            .font(.caption.weight(.semibold))
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

private struct ThroughputTrendChart: View {
    let downloadPoints: [MetricPoint]
    let uploadPoints: [MetricPoint]

    var body: some View {
        let downloadSeries = renderablePoints(downloadPoints)
        let uploadSeries = renderablePoints(uploadPoints)

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Throughput")
                    .font(.caption2)
                    .foregroundStyle(NomadTheme.tertiaryText)

                Spacer()

                HStack(spacing: 10) {
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
        .padding(10)
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
        .padding(10)
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

private struct PillBadge {
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
          abs(maximum - minimum) > 0.01 else {
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
