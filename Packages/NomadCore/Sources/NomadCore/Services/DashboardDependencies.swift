import Foundation

public struct DashboardDependencies: Sendable {
    public let throughputMonitor: any ThroughputMonitor
    public let latencyProbe: any LatencyProbe
    public let powerMonitor: any PowerMonitor
    public let wifiMonitor: any WiFiMonitor
    public let vpnStatusProvider: any VPNStatusProvider
    public let publicIPProvider: any PublicIPProvider
    public let publicIPLocationProvider: any PublicIPLocationProvider
    public let weatherProvider: any WeatherProvider
    public let historyStore: any MetricHistoryStore
    public let updateCoordinator: any UpdateCoordinator

    public init(
        throughputMonitor: any ThroughputMonitor,
        latencyProbe: any LatencyProbe,
        powerMonitor: any PowerMonitor,
        wifiMonitor: any WiFiMonitor,
        vpnStatusProvider: any VPNStatusProvider,
        publicIPProvider: any PublicIPProvider,
        publicIPLocationProvider: any PublicIPLocationProvider,
        weatherProvider: any WeatherProvider,
        historyStore: any MetricHistoryStore,
        updateCoordinator: any UpdateCoordinator
    ) {
        self.throughputMonitor = throughputMonitor
        self.latencyProbe = latencyProbe
        self.powerMonitor = powerMonitor
        self.wifiMonitor = wifiMonitor
        self.vpnStatusProvider = vpnStatusProvider
        self.publicIPProvider = publicIPProvider
        self.publicIPLocationProvider = publicIPLocationProvider
        self.weatherProvider = weatherProvider
        self.historyStore = historyStore
        self.updateCoordinator = updateCoordinator
    }

    public static func live(
        applicationSupportDirectory: URL,
        latencyHosts: [String] = ["1.1.1.1:443", "8.8.8.8:443"],
        historyRetentionHours: Int = 24,
        updateCoordinator: any UpdateCoordinator
    ) -> DashboardDependencies {
        DashboardDependencies(
            throughputMonitor: LiveThroughputMonitor(),
            latencyProbe: LiveLatencyProbe(endpoints: latencyHosts.compactMap(LatencyEndpoint.from(hostString:))),
            powerMonitor: LivePowerMonitor(),
            wifiMonitor: LiveWiFiMonitor(),
            vpnStatusProvider: LiveVPNStatusProvider(),
            publicIPProvider: CachedPublicIPProvider(),
            publicIPLocationProvider: CachedIPLocationProvider(),
            weatherProvider: LiveWeatherProvider(),
            historyStore: FileMetricHistoryStore(
                fileURL: applicationSupportDirectory.appendingPathComponent("metric-history.json"),
                retentionHours: historyRetentionHours
            ),
            updateCoordinator: updateCoordinator
        )
    }
}

private extension LatencyEndpoint {
    static func from(hostString: String) -> LatencyEndpoint? {
        let parts = hostString.split(separator: ":", maxSplits: 1).map(String.init)
        guard let host = parts.first, !host.isEmpty else {
            return nil
        }

        let port = parts.count == 2 ? UInt16(parts[1]) ?? 443 : 443
        return LatencyEndpoint(host: host, port: port)
    }
}
