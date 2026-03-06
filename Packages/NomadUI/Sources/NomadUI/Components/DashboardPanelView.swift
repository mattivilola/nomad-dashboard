import Charts
import NomadCore
import SwiftUI

public struct DashboardPanelView: View {
    private let snapshot: DashboardSnapshot
    private let versionDescription: String
    private let refreshAction: () -> Void
    private let copyIPAddressAction: () -> Void
    private let openNetworkSettingsAction: () -> Void
    private let checkForUpdatesAction: () -> Void
    private let openSettingsAction: () -> Void
    private let openAboutAction: () -> Void

    public init(
        snapshot: DashboardSnapshot,
        versionDescription: String,
        refreshAction: @escaping () -> Void,
        copyIPAddressAction: @escaping () -> Void,
        openNetworkSettingsAction: @escaping () -> Void,
        checkForUpdatesAction: @escaping () -> Void,
        openSettingsAction: @escaping () -> Void,
        openAboutAction: @escaping () -> Void
    ) {
        self.snapshot = snapshot
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
                    actionBar
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nomad Dashboard")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(NomadTheme.fog)

                    Text(snapshot.travelContext.location.map(locationLine) ?? "Travel-ready system telemetry")
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.68))
                }

                Spacer()

                Image(systemName: snapshot.weather?.symbolName ?? "airplane.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(NomadTheme.sand)
            }

            Text("Last refresh \(NomadFormatters.relativeDate(snapshot.appState.lastRefresh))")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.58))
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            ActionPill(title: "Refresh", systemImage: "arrow.clockwise", action: refreshAction)
            ActionPill(title: "Copy IP", systemImage: "document.on.document", action: copyIPAddressAction)
            ActionPill(title: "Network", systemImage: "gearshape.2", action: openNetworkSettingsAction)
            ActionPill(title: "Updates", systemImage: "sparkles", action: checkForUpdatesAction)
            ActionPill(title: "Settings", systemImage: "slider.horizontal.3", action: openSettingsAction)
            ActionPill(title: "About", systemImage: "info.circle", action: openAboutAction)
        }
    }

    private var connectivitySection: some View {
        DashboardCard(title: "Connectivity", subtitle: snapshot.network.throughput?.activeInterface ?? "Interface unavailable") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    MetricBlock(title: "Down", value: NomadFormatters.megabitsPerSecond(snapshot.network.throughput?.downloadMegabitsPerSecond), tint: NomadTheme.teal)
                    MetricBlock(title: "Up", value: NomadFormatters.megabitsPerSecond(snapshot.network.throughput?.uploadMegabitsPerSecond), tint: NomadTheme.sand)
                    MetricBlock(title: "Latency", value: NomadFormatters.latency(snapshot.network.latency?.milliseconds), tint: NomadTheme.coral)
                }

                HStack(spacing: 12) {
                    MiniTrendChart(points: snapshot.network.downloadHistory, color: NomadTheme.teal, yLabel: "Mbps")
                    MiniTrendChart(points: snapshot.network.latencyHistory, color: NomadTheme.coral, yLabel: "ms")
                }

                if let jitter = snapshot.network.latency?.jitterMilliseconds {
                    Text("Jitter \(NomadFormatters.latency(jitter)) via \(snapshot.network.latency?.host ?? "n/a")")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.62))
                }
            }
        }
    }

    private var powerSection: some View {
        DashboardCard(title: "Power", subtitle: snapshot.power.snapshot.map(powerSubtitle) ?? "Power source unavailable") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    MetricBlock(
                        title: "Battery",
                        value: NomadFormatters.percentage(snapshot.power.snapshot?.chargePercent.map { $0 * 100 }),
                        tint: NomadTheme.sand
                    )
                    MetricBlock(
                        title: "Drain",
                        value: NomadFormatters.watts(snapshot.power.snapshot?.dischargeRateWatts),
                        tint: NomadTheme.coral
                    )
                    MetricBlock(
                        title: "Time Left",
                        value: NomadFormatters.minutes(snapshot.power.snapshot?.timeRemainingMinutes),
                        tint: NomadTheme.teal
                    )
                }

                HStack(spacing: 12) {
                    MiniTrendChart(points: snapshot.power.chargeHistory, color: NomadTheme.sand, yLabel: "%")
                    MiniTrendChart(points: snapshot.power.dischargeHistory, color: NomadTheme.coral, yLabel: "W")
                }
            }
        }
    }

    private var travelSection: some View {
        DashboardCard(title: "Travel Context", subtitle: snapshot.travelContext.publicIP?.address ?? "Public IP unavailable") {
            VStack(alignment: .leading, spacing: 10) {
                DetailRow(label: "Wi-Fi", value: snapshot.travelContext.wifi?.ssid ?? "Not connected")
                DetailRow(label: "Signal", value: signalDescription(snapshot.travelContext.wifi))
                DetailRow(label: "VPN", value: snapshot.travelContext.vpn?.isActive == true ? snapshot.travelContext.vpn?.interfaceNames.joined(separator: ", ") ?? "Active" : "Inactive")
                DetailRow(label: "Time Zone", value: snapshot.travelContext.timeZoneIdentifier)
                DetailRow(label: "Country", value: snapshot.travelContext.location?.country ?? "Geolocation disabled")
            }
        }
    }

    private var weatherSection: some View {
        DashboardCard(title: "Weather", subtitle: snapshot.weather?.conditionDescription ?? "Waiting for location-enabled weather") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    MetricBlock(title: "Current", value: NomadFormatters.celsius(snapshot.weather?.currentTemperatureCelsius), tint: NomadTheme.teal)
                    MetricBlock(title: "Feels Like", value: NomadFormatters.celsius(snapshot.weather?.apparentTemperatureCelsius), tint: NomadTheme.sand)
                    MetricBlock(title: "Rain", value: NomadFormatters.precipitation(snapshot.weather?.precipitationChance), tint: NomadTheme.coral)
                }

                if let tomorrow = snapshot.weather?.tomorrow {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tomorrow")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.72))

                        HStack {
                            Label(tomorrow.summary, systemImage: tomorrow.symbolName)
                                .foregroundStyle(NomadTheme.fog)

                            Spacer()

                            Text("\(NomadFormatters.celsius(tomorrow.temperatureMinCelsius)) / \(NomadFormatters.celsius(tomorrow.temperatureMaxCelsius))")
                                .foregroundStyle(Color.white.opacity(0.72))
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.appState.updateState.detail ?? "Update channel idle")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.62))

                Spacer()

                Text(versionDescription)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.48))
            }

            if snapshot.appState.issues.isEmpty == false {
                Text(snapshot.appState.issues.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(NomadTheme.coral)
            }
        }
    }

    private func locationLine(_ location: IPLocationSnapshot) -> String {
        [location.city, location.country]
            .compactMap { $0 }
            .joined(separator: ", ")
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

        return pieces.compactMap { $0 }.joined(separator: " · ")
    }
}

private struct DashboardCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(NomadTheme.fog)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.64))
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

private struct MetricBlock: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.white.opacity(0.5))

            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.55))

            Spacer()

            Text(value)
                .font(.caption)
                .foregroundStyle(NomadTheme.fog)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct ActionPill: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .foregroundStyle(Color.white.opacity(0.84))
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.09))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct MiniTrendChart: View {
    let points: [MetricPoint]
    let color: Color
    let yLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(yLabel)
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.5))

            Chart(points) {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.14))
        )
    }
}
