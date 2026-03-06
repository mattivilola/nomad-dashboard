import Charts
import NomadCore
import SwiftUI

public struct DashboardPanelView: View {
    private let snapshot: DashboardSnapshot
    private let isPublicIPLocationEnabled: Bool
    private let versionDescription: String
    private let refreshAction: () -> Void
    private let copyIPAddressAction: () -> Void
    private let openNetworkSettingsAction: () -> Void
    private let checkForUpdatesAction: (() -> Void)?
    private let openSettingsAction: () -> Void
    private let openAboutAction: () -> Void

    public init(
        snapshot: DashboardSnapshot,
        isPublicIPLocationEnabled: Bool,
        versionDescription: String = "",
        refreshAction: @escaping () -> Void,
        copyIPAddressAction: @escaping () -> Void,
        openNetworkSettingsAction: @escaping () -> Void,
        checkForUpdatesAction: (() -> Void)? = nil,
        openSettingsAction: @escaping () -> Void,
        openAboutAction: @escaping () -> Void
    ) {
        self.snapshot = snapshot
        self.isPublicIPLocationEnabled = isPublicIPLocationEnabled
        self.versionDescription = versionDescription
        self.refreshAction = refreshAction
        self.copyIPAddressAction = copyIPAddressAction
        self.openNetworkSettingsAction = openNetworkSettingsAction
        self.checkForUpdatesAction = checkForUpdatesAction
        self.openSettingsAction = openSettingsAction
        self.openAboutAction = openAboutAction
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
                    .foregroundStyle(NomadTheme.fog)

                Text(snapshot.travelContext.location.flatMap(formattedLocation) ?? "Travel-ready system telemetry")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.68))

                Text("Last refresh \(NomadFormatters.relativeDate(snapshot.appState.lastRefresh))")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.58))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                HeaderIconButton(systemImage: "arrow.clockwise", title: "Refresh", action: refreshAction)
                HeaderIconButton(systemImage: "slider.horizontal.3", title: "Settings", action: openSettingsAction)

                Menu {
                    Button("Open Network Settings", systemImage: "gearshape.2") {
                        openNetworkSettingsAction()
                    }

                    if let checkForUpdatesAction {
                        Button("Check for Updates", systemImage: "sparkles") {
                            checkForUpdatesAction()
                        }
                    }

                    Divider()

                    Button("About Nomad Dashboard", systemImage: "info.circle") {
                        openAboutAction()
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
                    .foregroundStyle(Color.white.opacity(0.62))
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
            badge: travelBadge,
            accessory: AnyView(
                InlineActionButton(
                    title: "Copy Public IP",
                    systemImage: "document.on.document",
                    isEnabled: snapshot.travelContext.publicIP != nil,
                    action: copyIPAddressAction
                )
            )
        ) {
            VStack(alignment: .leading, spacing: 10) {
                DetailRow(label: "Public IP", value: publicIPValue)
                DetailRow(label: "Wi-Fi", value: snapshot.travelContext.wifi?.ssid ?? "Not connected")
                DetailRow(label: "Signal", value: signalDescription(snapshot.travelContext.wifi))
                DetailRow(label: "VPN", value: vpnDescription)
                DetailRow(label: "Time Zone", value: snapshot.travelContext.timeZoneIdentifier)
                DetailRow(label: "Location", value: locationValue)
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
                                .foregroundStyle(Color.white.opacity(0.72))

                            HStack(alignment: .top, spacing: 10) {
                                Label(tomorrow.summary, systemImage: tomorrow.symbolName)
                                    .foregroundStyle(NomadTheme.fog)

                                Spacer()

                                Text(temperatureRangeText(for: tomorrow))
                                    .foregroundStyle(Color.white.opacity(0.72))
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

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(snapshot.appState.updateState.detail ?? "Update channel idle")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.62))

            if versionDescription.isEmpty == false {
                Text(versionDescription)
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.44))
            }
        }
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
            return PillBadge(title: "VPN On", symbolName: "lock.shield.fill", tint: NomadTheme.fog)
        }

        return PillBadge(title: "VPN Off", symbolName: "lock.open.fill", tint: NomadTheme.fog)
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

        return PillBadge(title: "Unavailable", symbolName: "cloud.slash.fill", tint: NomadTheme.fog)
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
                        .foregroundStyle(NomadTheme.fog)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.64))
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
            .foregroundStyle(Color.white.opacity(0.88))
            .frame(width: 34, height: 34)
            .background(
                Circle()
                    .fill(Color.white.opacity(0.10))
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
                .foregroundStyle(Color.white.opacity(0.48))

            Label(health.label, systemImage: health.symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(health.level.tint)
                .lineLimit(1)

            Text(health.reason)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.74))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(health.level.tint.opacity(0.16), lineWidth: 1)
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
                .foregroundStyle(Color.white.opacity(0.5))

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
            return NomadTheme.teal
        case "Up", "Battery", "Feels Like":
            return NomadTheme.sand
        default:
            return NomadTheme.coral
        }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.55))

            Spacer(minLength: 12)

            Text(value)
                .font(.caption)
                .foregroundStyle(NomadTheme.fog)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct InlineActionButton: View {
    let title: String
    let systemImage: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(Color.white.opacity(isEnabled ? 0.84 : 0.42))
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(isEnabled ? 0.09 : 0.05))
                )
        }
        .buttonStyle(.plain)
        .disabled(isEnabled == false)
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
                    .foregroundStyle(Color.white.opacity(0.5))

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
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.14))
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
                .foregroundStyle(Color.white.opacity(0.5))

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
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.14))
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
                .foregroundStyle(Color.white.opacity(0.56))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NomadTheme.fog)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.64))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.12))
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
                .foregroundStyle(Color.white.opacity(0.5))

            Spacer()

            Text(message)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.58))
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
                .foregroundStyle(Color.white.opacity(0.56))
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
            NomadTheme.fog
        }
    }
}
