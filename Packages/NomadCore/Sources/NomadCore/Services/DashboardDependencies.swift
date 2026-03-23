import Foundation

public struct DashboardDependencies: Sendable {
    public let throughputMonitor: any ThroughputMonitor
    public let connectivityMonitor: any ConnectivityMonitor
    public let latencyProbe: any LatencyProbe
    public let powerMonitor: any PowerMonitor
    public let wifiMonitor: any WiFiMonitor
    public let vpnStatusProvider: any VPNStatusProvider
    public let publicIPProvider: any PublicIPProvider
    public let publicIPLocationProvider: any PublicIPLocationProvider
    public let reverseGeocodingProvider: any ReverseGeocodingProvider
    public let weatherProvider: any WeatherProvider
    public let fuelPriceProvider: any FuelPriceProvider
    public let emergencyCareProvider: any EmergencyCareProvider
    public let marineProvider: any MarineProvider
    public let neighborCountryResolver: any NeighborCountryResolver
    public let travelAdvisoryProvider: any TravelAdvisoryProvider
    public let travelWeatherAlertsProvider: any TravelWeatherAlertsProvider
    public let regionalSecurityProvider: any RegionalSecurityProvider
    public let visitedPlacesStore: any VisitedPlacesStore
    public let historyStore: any MetricHistoryStore
    public let updateCoordinator: any UpdateCoordinator

    public init(
        throughputMonitor: any ThroughputMonitor,
        connectivityMonitor: any ConnectivityMonitor,
        latencyProbe: any LatencyProbe,
        powerMonitor: any PowerMonitor,
        wifiMonitor: any WiFiMonitor,
        vpnStatusProvider: any VPNStatusProvider,
        publicIPProvider: any PublicIPProvider,
        publicIPLocationProvider: any PublicIPLocationProvider,
        reverseGeocodingProvider: any ReverseGeocodingProvider,
        weatherProvider: any WeatherProvider,
        fuelPriceProvider: any FuelPriceProvider,
        emergencyCareProvider: any EmergencyCareProvider,
        marineProvider: any MarineProvider,
        neighborCountryResolver: any NeighborCountryResolver,
        travelAdvisoryProvider: any TravelAdvisoryProvider,
        travelWeatherAlertsProvider: any TravelWeatherAlertsProvider,
        regionalSecurityProvider: any RegionalSecurityProvider,
        visitedPlacesStore: any VisitedPlacesStore,
        historyStore: any MetricHistoryStore,
        updateCoordinator: any UpdateCoordinator
    ) {
        self.throughputMonitor = throughputMonitor
        self.connectivityMonitor = connectivityMonitor
        self.latencyProbe = latencyProbe
        self.powerMonitor = powerMonitor
        self.wifiMonitor = wifiMonitor
        self.vpnStatusProvider = vpnStatusProvider
        self.publicIPProvider = publicIPProvider
        self.publicIPLocationProvider = publicIPLocationProvider
        self.reverseGeocodingProvider = reverseGeocodingProvider
        self.weatherProvider = weatherProvider
        self.fuelPriceProvider = fuelPriceProvider
        self.emergencyCareProvider = emergencyCareProvider
        self.marineProvider = marineProvider
        self.neighborCountryResolver = neighborCountryResolver
        self.travelAdvisoryProvider = travelAdvisoryProvider
        self.travelWeatherAlertsProvider = travelWeatherAlertsProvider
        self.regionalSecurityProvider = regionalSecurityProvider
        self.visitedPlacesStore = visitedPlacesStore
        self.historyStore = historyStore
        self.updateCoordinator = updateCoordinator
    }

    public static func live(
        applicationSupportDirectory: URL,
        latencyHosts: [String] = ["1.1.1.1:443", "8.8.8.8:443"],
        historyRetentionHours: Int = 24,
        reliefWebAppName: String? = nil,
        tankerkonigAPIKey: String? = nil,
        updateCoordinator: any UpdateCoordinator
    ) -> DashboardDependencies {
        let latencyEndpoints = latencyHosts.compactMap(LatencyEndpoint.from(hostString:))
        let publicIPClient = CachedFreeIPAPIClient()

        return DashboardDependencies(
            throughputMonitor: LiveThroughputMonitor(),
            connectivityMonitor: LiveConnectivityMonitor(endpoints: latencyEndpoints),
            latencyProbe: LiveLatencyProbe(endpoints: latencyEndpoints),
            powerMonitor: LivePowerMonitor(),
            wifiMonitor: LiveWiFiMonitor(),
            vpnStatusProvider: LiveVPNStatusProvider(),
            publicIPProvider: CachedPublicIPProvider(client: publicIPClient),
            publicIPLocationProvider: CachedIPLocationProvider(client: publicIPClient),
            reverseGeocodingProvider: CachedReverseGeocodingProvider(),
            weatherProvider: LiveWeatherProvider(),
            fuelPriceProvider: LiveEuropeanFuelPriceProvider(tankerkonigAPIKey: tankerkonigAPIKey),
            emergencyCareProvider: LiveEmergencyCareProvider(),
            marineProvider: LiveOpenMeteoMarineProvider(),
            neighborCountryResolver: BundledNeighborCountryResolver(),
            travelAdvisoryProvider: SmartravellerAdvisoryProvider(),
            travelWeatherAlertsProvider: WeatherKitAlertProvider(),
            regionalSecurityProvider: ReliefWebSecurityProvider(appName: reliefWebAppName),
            visitedPlacesStore: FileVisitedPlacesStore(
                fileURL: applicationSupportDirectory.appendingPathComponent("visited-places.json")
            ),
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
