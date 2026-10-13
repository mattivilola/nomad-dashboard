import CoreLocation
import Foundation

public struct LatencyEndpoint: Equatable, Sendable {
    public let host: String
    public let port: UInt16

    public init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }
}

public protocol ThroughputMonitor: Sendable {
    func currentSample() async -> NetworkThroughputSample?
}

public protocol ConnectivityMonitor: Sendable {
    func currentSnapshot() async -> ConnectivitySnapshot
}

public protocol LatencyProbe: Sendable {
    func currentSample() async -> LatencySample?
}

public protocol PowerMonitor: Sendable {
    func currentSnapshot() async -> PowerSnapshot?
}

public protocol WiFiMonitor: Sendable {
    func currentSnapshot() async -> WiFiSnapshot?
}

public protocol VPNStatusProvider: Sendable {
    func currentStatus() async -> VPNStatusSnapshot
}

public protocol PublicIPProvider: Sendable {
    func currentIP(forceRefresh: Bool) async throws -> PublicIPSnapshot
}

public protocol PublicIPLocationProvider: Sendable {
    func currentLocation(for ipAddress: String, forceRefresh: Bool) async throws -> IPLocationSnapshot
}

public protocol ReverseGeocodingProvider: Sendable {
    func details(for location: CLLocation) async throws -> ReverseGeocodedLocation
}

public protocol WeatherProvider: Sendable {
    func weather(for coordinate: CLLocationCoordinate2D?) async throws -> WeatherSnapshot
}

public protocol FuelPriceProvider: Sendable {
    func prices(for request: FuelSearchRequest, forceRefresh: Bool) async throws -> FuelPriceSnapshot
}

public protocol EmergencyCareProvider: Sendable {
    func nearbyHospitals(for request: EmergencyCareSearchRequest, forceRefresh: Bool) async throws -> EmergencyCareSnapshot
}

public protocol LocalPriceLevelProvider: Sendable {
    func prices(for request: LocalPriceSearchRequest, forceRefresh: Bool) async throws -> LocalPriceLevelSnapshot
}

public protocol LocalInfoProvider: Sendable {
    func info(for request: LocalInfoRequest, forceRefresh: Bool) async throws -> LocalInfoSnapshot
}

public protocol PublicHolidayProvider: Sendable {
    /// The nationwide public holidays of a country in a year, as single-day periods in `timeZone`. Throws
    /// `ProviderError.missingCountryCode` when the source does not cover the country.
    func publicHolidays(
        inCountry countryCode: String,
        year: Int,
        timeZone: TimeZone,
        forceRefresh: Bool
    ) async throws -> [HolidayPeriodSnapshot]
}

public protocol PriceLevelIndexProvider: Sendable {
    /// Eurostat price-level indices (EU27 = 100) for one country, keyed by category. Empty, never an error,
    /// for a country the source does not cover. Only the country code is sent.
    func indices(forCountryCode countryCode: String) async throws -> [LocalPriceIndicatorKind: Double]
}

public protocol TripPreviewService: Sendable {
    /// The network-backed parts of a trip preview. Only the trip's destination country code is sent; the
    /// dates and the user's location never are. Nil when neither part is available. Offline, or in Low Data
    /// mode, it answers from what is saved and never goes to the network.
    func online(
        for trip: PlannedTrip,
        settings: AppSettings,
        policy: DashboardResourcePolicy,
        forceRefresh: Bool,
        calendar: Calendar
    ) async -> TripPreviewOnline?
}

public protocol FuelPriceProviderConfigurationUpdating: Sendable {
    func setTankerkonigAPIKey(_ apiKey: String?) async
}

public protocol LocalPriceLevelProviderConfigurationUpdating: Sendable {
    func setHUDUserAPIToken(_ token: String?) async
}

public protocol MarineProvider: Sendable {
    func marine(for spot: MarineSpot) async throws -> MarineSnapshot
}

public protocol AirQualityProvider: Sendable {
    /// The implementation decides how precisely the coordinate is shared with its service.
    func airQuality(for coordinate: CLLocationCoordinate2D) async throws -> AirQualitySnapshot
}

public protocol NeighborCountryResolver: Sendable {
    func neighboringCountryCodes(for countryCode: String) -> [String]
}

public protocol TravelAdvisoryProvider: Sendable {
    var sourceDescriptor: TravelAlertSourceDescriptor { get }
    func advisory(for countryCodes: [String], primaryCountryCode: String, forceRefresh: Bool) async throws -> TravelAlertSignalSnapshot
}

public protocol SmartravellerBrowserFetcher: Sendable {
    func destinationsHTML() async throws -> String
}

public protocol TravelWeatherAlertsProvider: Sendable {
    var sourceDescriptor: TravelAlertSourceDescriptor { get }
    func alerts(for coordinate: CLLocationCoordinate2D?, forceRefresh: Bool) async throws -> TravelAlertSignalSnapshot
}

public protocol RegionalSecurityProvider: Sendable {
    var sourceDescriptor: TravelAlertSourceDescriptor { get }
    func security(for countryCodes: [String], primaryCountryCode: String, forceRefresh: Bool) async throws -> TravelAlertSignalSnapshot
}

public protocol VisitedPlacesStore: Sendable {
    func loadAll() async throws -> [VisitedPlace]
    func record(_ input: VisitedPlaceInput) async throws
    func reset() async throws
}

public protocol VisitedPlaceEventsStore: Sendable {
    func loadAll() async throws -> [VisitedPlaceEvent]
    func record(_ input: VisitedPlaceEventInput) async throws
    func reset() async throws
}

/// A short local history of the Mac's time zone changes, for the jet-lag nudge.
public protocol TimeZoneShiftStore: Sendable {
    /// The kept records, oldest first.
    func loadAll() async throws -> [TimeZoneShiftRecord]
    /// Appends `record` unless the latest record already has the same time zone and offset.
    func record(_ record: TimeZoneShiftRecord) async throws
    func reset() async throws
}

public protocol VisitedCountryDaysStore: Sendable {
    func loadAll() async throws -> [VisitedCountryDay]
    func record(_ input: VisitedCountryDayInput) async throws
    func reset() async throws
}

public protocol MetricHistoryStore: Sendable {
    func loadAll() async throws -> [MetricSeriesKind: [MetricPoint]]
    func append(_ point: MetricPoint, to series: MetricSeriesKind) async throws
    func reset() async throws
    func setRetentionHours(_ retentionHours: Int) async throws
}

public protocol TimeTrackingLedgerStore: Sendable {
    func load() async throws -> TimeTrackingLedger
    func save(_ ledger: TimeTrackingLedger) async throws
    func reset() async throws
}

public protocol UpdateCoordinator: Sendable {
    func currentState() async -> UpdateStateSnapshot
    func checkForUpdates() async
    func setAutomaticChecksEnabled(_ isEnabled: Bool) async
}
