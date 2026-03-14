import CoreLocation
import Foundation

public struct MetricPoint: Codable, Equatable, Sendable, Identifiable {
    public let timestamp: Date
    public let value: Double

    public var id: Date {
        timestamp
    }

    public init(timestamp: Date, value: Double) {
        self.timestamp = timestamp
        self.value = value
    }
}

public enum MetricSeriesKind: String, Codable, CaseIterable, Sendable {
    case downloadMbps
    case uploadMbps
    case latencyMilliseconds
    case batteryChargePercent
    case batteryDischargeWatts
}

public struct NetworkThroughputSample: Equatable, Sendable {
    public let downloadBytesPerSecond: Double
    public let uploadBytesPerSecond: Double
    public let activeInterface: String?
    public let collectedAt: Date

    public init(
        downloadBytesPerSecond: Double,
        uploadBytesPerSecond: Double,
        activeInterface: String?,
        collectedAt: Date
    ) {
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
        self.activeInterface = activeInterface
        self.collectedAt = collectedAt
    }

    public var downloadMegabitsPerSecond: Double {
        downloadBytesPerSecond * 8 / 1_000_000
    }

    public var uploadMegabitsPerSecond: Double {
        uploadBytesPerSecond * 8 / 1_000_000
    }
}

public struct LatencySample: Equatable, Sendable {
    public let host: String
    public let milliseconds: Double
    public let jitterMilliseconds: Double?
    public let collectedAt: Date

    public init(host: String, milliseconds: Double, jitterMilliseconds: Double?, collectedAt: Date) {
        self.host = host
        self.milliseconds = milliseconds
        self.jitterMilliseconds = jitterMilliseconds
        self.collectedAt = collectedAt
    }
}

public enum InternetReachabilityState: String, Codable, CaseIterable, Equatable, Sendable {
    case checking
    case online
    case offline
}

public struct ConnectivitySnapshot: Equatable, Sendable {
    public let pathAvailable: Bool?
    public let internetState: InternetReachabilityState
    public let lastCheckedAt: Date?

    public init(pathAvailable: Bool?, internetState: InternetReachabilityState, lastCheckedAt: Date?) {
        self.pathAvailable = pathAvailable
        self.internetState = internetState
        self.lastCheckedAt = lastCheckedAt
    }
}

public extension ConnectivitySnapshot {
    static let checking = ConnectivitySnapshot(pathAvailable: nil, internetState: .checking, lastCheckedAt: nil)
}

public enum PowerSourceState: String, Codable, Equatable, Sendable {
    case battery
    case charging
    case charged
    case unknown
}

public struct PowerSnapshot: Equatable, Sendable {
    public let chargePercent: Double?
    public let state: PowerSourceState
    public let timeRemainingMinutes: Int?
    public let timeToFullChargeMinutes: Int?
    public let isLowPowerModeEnabled: Bool
    public let dischargeRateWatts: Double?
    public let adapterWatts: Double?
    public let collectedAt: Date

    public init(
        chargePercent: Double?,
        state: PowerSourceState,
        timeRemainingMinutes: Int?,
        timeToFullChargeMinutes: Int?,
        isLowPowerModeEnabled: Bool,
        dischargeRateWatts: Double?,
        adapterWatts: Double?,
        collectedAt: Date
    ) {
        self.chargePercent = chargePercent
        self.state = state
        self.timeRemainingMinutes = timeRemainingMinutes
        self.timeToFullChargeMinutes = timeToFullChargeMinutes
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
        self.dischargeRateWatts = dischargeRateWatts
        self.adapterWatts = adapterWatts
        self.collectedAt = collectedAt
    }
}

public struct WiFiSnapshot: Equatable, Sendable {
    public let interfaceName: String?
    public let ssid: String?
    public let rssi: Int?
    public let noise: Int?
    public let transmitRateMbps: Double?

    public init(interfaceName: String?, ssid: String?, rssi: Int?, noise: Int?, transmitRateMbps: Double?) {
        self.interfaceName = interfaceName
        self.ssid = ssid
        self.rssi = rssi
        self.noise = noise
        self.transmitRateMbps = transmitRateMbps
    }
}

public struct VPNStatusSnapshot: Equatable, Sendable {
    public let isActive: Bool
    public let interfaceNames: [String]
    public let serviceNames: [String]

    public init(isActive: Bool, interfaceNames: [String], serviceNames: [String] = []) {
        self.isActive = isActive
        self.interfaceNames = interfaceNames
        self.serviceNames = serviceNames
    }
}

public struct PublicIPSnapshot: Equatable, Sendable {
    public let address: String
    public let provider: String
    public let fetchedAt: Date

    public init(address: String, provider: String, fetchedAt: Date) {
        self.address = address
        self.provider = provider
        self.fetchedAt = fetchedAt
    }
}

public struct IPLocationSnapshot: Equatable, Sendable {
    public let city: String?
    public let region: String?
    public let country: String?
    public let countryCode: String?
    public let latitude: Double?
    public let longitude: Double?
    public let timeZone: String?
    public let provider: String
    public let fetchedAt: Date

    public init(
        city: String?,
        region: String?,
        country: String?,
        countryCode: String?,
        latitude: Double?,
        longitude: Double?,
        timeZone: String?,
        provider: String,
        fetchedAt: Date
    ) {
        self.city = city
        self.region = region
        self.country = country
        self.countryCode = countryCode
        self.latitude = latitude
        self.longitude = longitude
        self.timeZone = timeZone
        self.provider = provider
        self.fetchedAt = fetchedAt
    }

    public var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else {
            return nil
        }

        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

public struct WeatherDaySummary: Equatable, Sendable {
    public let date: Date
    public let symbolName: String
    public let summary: String
    public let temperatureMinCelsius: Double?
    public let temperatureMaxCelsius: Double?
    public let precipitationChance: Double?

    public init(
        date: Date,
        symbolName: String,
        summary: String,
        temperatureMinCelsius: Double?,
        temperatureMaxCelsius: Double?,
        precipitationChance: Double?
    ) {
        self.date = date
        self.symbolName = symbolName
        self.summary = summary
        self.temperatureMinCelsius = temperatureMinCelsius
        self.temperatureMaxCelsius = temperatureMaxCelsius
        self.precipitationChance = precipitationChance
    }
}

public struct WeatherSnapshot: Equatable, Sendable {
    public let currentTemperatureCelsius: Double?
    public let apparentTemperatureCelsius: Double?
    public let conditionDescription: String
    public let symbolName: String
    public let precipitationChance: Double?
    public let windSpeedKph: Double?
    public let tomorrow: WeatherDaySummary?
    public let fetchedAt: Date

    public init(
        currentTemperatureCelsius: Double?,
        apparentTemperatureCelsius: Double?,
        conditionDescription: String,
        symbolName: String,
        precipitationChance: Double?,
        windSpeedKph: Double?,
        tomorrow: WeatherDaySummary?,
        fetchedAt: Date
    ) {
        self.currentTemperatureCelsius = currentTemperatureCelsius
        self.apparentTemperatureCelsius = apparentTemperatureCelsius
        self.conditionDescription = conditionDescription
        self.symbolName = symbolName
        self.precipitationChance = precipitationChance
        self.windSpeedKph = windSpeedKph
        self.tomorrow = tomorrow
        self.fetchedAt = fetchedAt
    }
}

public struct MarineSpot: Equatable, Sendable {
    public let name: String
    public let coordinate: CLLocationCoordinate2D

    public init(name: String, coordinate: CLLocationCoordinate2D) {
        self.name = name
        self.coordinate = coordinate
    }

    public static func == (lhs: MarineSpot, rhs: MarineSpot) -> Bool {
        lhs.name == rhs.name
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

public struct MarineForecastSlot: Equatable, Sendable, Identifiable {
    public let date: Date
    public let waveHeightMeters: Double?
    public let swellHeightMeters: Double?
    public let windSpeedKph: Double?
    public let windDirectionDegrees: Double?

    public var id: Date {
        date
    }

    public init(
        date: Date,
        waveHeightMeters: Double?,
        swellHeightMeters: Double?,
        windSpeedKph: Double?,
        windDirectionDegrees: Double?
    ) {
        self.date = date
        self.waveHeightMeters = waveHeightMeters
        self.swellHeightMeters = swellHeightMeters
        self.windSpeedKph = windSpeedKph
        self.windDirectionDegrees = windDirectionDegrees
    }
}

public struct MarineSnapshot: Equatable, Sendable {
    public let spotName: String
    public let coordinate: CLLocationCoordinate2D
    public let sourceName: String
    public let waveHeightMeters: Double?
    public let wavePeriodSeconds: Double?
    public let swellHeightMeters: Double?
    public let swellPeriodSeconds: Double?
    public let swellDirectionDegrees: Double?
    public let windSpeedKph: Double?
    public let windGustKph: Double?
    public let windDirectionDegrees: Double?
    public let seaSurfaceTemperatureCelsius: Double?
    public let forecastSlots: [MarineForecastSlot]
    public let fetchedAt: Date

    public init(
        spotName: String,
        coordinate: CLLocationCoordinate2D,
        sourceName: String,
        waveHeightMeters: Double?,
        wavePeriodSeconds: Double?,
        swellHeightMeters: Double?,
        swellPeriodSeconds: Double?,
        swellDirectionDegrees: Double?,
        windSpeedKph: Double?,
        windGustKph: Double?,
        windDirectionDegrees: Double?,
        seaSurfaceTemperatureCelsius: Double?,
        forecastSlots: [MarineForecastSlot],
        fetchedAt: Date
    ) {
        self.spotName = spotName
        self.coordinate = coordinate
        self.sourceName = sourceName
        self.waveHeightMeters = waveHeightMeters
        self.wavePeriodSeconds = wavePeriodSeconds
        self.swellHeightMeters = swellHeightMeters
        self.swellPeriodSeconds = swellPeriodSeconds
        self.swellDirectionDegrees = swellDirectionDegrees
        self.windSpeedKph = windSpeedKph
        self.windGustKph = windGustKph
        self.windDirectionDegrees = windDirectionDegrees
        self.seaSurfaceTemperatureCelsius = seaSurfaceTemperatureCelsius
        self.forecastSlots = forecastSlots
        self.fetchedAt = fetchedAt
    }

    public static func == (lhs: MarineSnapshot, rhs: MarineSnapshot) -> Bool {
        lhs.spotName == rhs.spotName
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.sourceName == rhs.sourceName
            && lhs.waveHeightMeters == rhs.waveHeightMeters
            && lhs.wavePeriodSeconds == rhs.wavePeriodSeconds
            && lhs.swellHeightMeters == rhs.swellHeightMeters
            && lhs.swellPeriodSeconds == rhs.swellPeriodSeconds
            && lhs.swellDirectionDegrees == rhs.swellDirectionDegrees
            && lhs.windSpeedKph == rhs.windSpeedKph
            && lhs.windGustKph == rhs.windGustKph
            && lhs.windDirectionDegrees == rhs.windDirectionDegrees
            && lhs.seaSurfaceTemperatureCelsius == rhs.seaSurfaceTemperatureCelsius
            && lhs.forecastSlots == rhs.forecastSlots
            && lhs.fetchedAt == rhs.fetchedAt
    }
}

public enum UpdateStateKind: String, Codable, Equatable, Sendable {
    case idle
    case checking
    case updateAvailable
    case unavailable
}

public struct UpdateStateSnapshot: Equatable, Sendable {
    public let kind: UpdateStateKind
    public let detail: String?
    public let lastCheckedAt: Date?

    public init(kind: UpdateStateKind, detail: String?, lastCheckedAt: Date?) {
        self.kind = kind
        self.detail = detail
        self.lastCheckedAt = lastCheckedAt
    }

    public static let idle = UpdateStateSnapshot(kind: .idle, detail: nil, lastCheckedAt: nil)
}

public enum DashboardRefreshActivity: Equatable, Sendable {
    case idle
    case manualInProgress
    case slowAutomaticInProgress
}

public struct NetworkSectionSnapshot: Equatable, Sendable {
    public let throughput: NetworkThroughputSample?
    public let connectivity: ConnectivitySnapshot
    public let latency: LatencySample?
    public let downloadHistory: [MetricPoint]
    public let uploadHistory: [MetricPoint]
    public let latencyHistory: [MetricPoint]

    public init(
        throughput: NetworkThroughputSample?,
        connectivity: ConnectivitySnapshot = .checking,
        latency: LatencySample?,
        downloadHistory: [MetricPoint],
        uploadHistory: [MetricPoint],
        latencyHistory: [MetricPoint]
    ) {
        self.throughput = throughput
        self.connectivity = connectivity
        self.latency = latency
        self.downloadHistory = downloadHistory
        self.uploadHistory = uploadHistory
        self.latencyHistory = latencyHistory
    }
}

public struct PowerSectionSnapshot: Equatable, Sendable {
    public let snapshot: PowerSnapshot?
    public let chargeHistory: [MetricPoint]
    public let dischargeHistory: [MetricPoint]

    public init(snapshot: PowerSnapshot?, chargeHistory: [MetricPoint], dischargeHistory: [MetricPoint]) {
        self.snapshot = snapshot
        self.chargeHistory = chargeHistory
        self.dischargeHistory = dischargeHistory
    }
}

public struct TravelContextSnapshot: Equatable, Sendable {
    public let wifi: WiFiSnapshot?
    public let vpn: VPNStatusSnapshot?
    public let timeZoneIdentifier: String
    public let publicIP: PublicIPSnapshot?
    public let location: IPLocationSnapshot?

    public init(
        wifi: WiFiSnapshot?,
        vpn: VPNStatusSnapshot?,
        timeZoneIdentifier: String,
        publicIP: PublicIPSnapshot?,
        location: IPLocationSnapshot?
    ) {
        self.wifi = wifi
        self.vpn = vpn
        self.timeZoneIdentifier = timeZoneIdentifier
        self.publicIP = publicIP
        self.location = location
    }
}

public struct AppStatusSnapshot: Equatable, Sendable {
    public let lastRefresh: Date?
    public let updateState: UpdateStateSnapshot
    public let issues: [DashboardIssue]

    public init(lastRefresh: Date?, updateState: UpdateStateSnapshot, issues: [DashboardIssue]) {
        self.lastRefresh = lastRefresh
        self.updateState = updateState
        self.issues = issues
    }
}

public struct DashboardSnapshot: Equatable, Sendable {
    public let network: NetworkSectionSnapshot
    public let power: PowerSectionSnapshot
    public let travelContext: TravelContextSnapshot
    public let travelAlerts: TravelAlertsSnapshot?
    public let weather: WeatherSnapshot?
    public let fuelPrices: FuelPriceSnapshot?
    public let fuelDiagnostics: FuelDiagnosticsSnapshot?
    public let marine: MarineSnapshot?
    public let appState: AppStatusSnapshot
    public let healthSummary: DashboardHealthSummary

    public init(
        network: NetworkSectionSnapshot,
        power: PowerSectionSnapshot,
        travelContext: TravelContextSnapshot,
        travelAlerts: TravelAlertsSnapshot? = nil,
        weather: WeatherSnapshot?,
        fuelPrices: FuelPriceSnapshot? = nil,
        fuelDiagnostics: FuelDiagnosticsSnapshot? = nil,
        marine: MarineSnapshot? = nil,
        appState: AppStatusSnapshot,
        healthSummary: DashboardHealthSummary? = nil
    ) {
        self.network = network
        self.power = power
        self.travelContext = travelContext
        self.travelAlerts = travelAlerts
        self.weather = weather
        self.fuelPrices = fuelPrices
        self.fuelDiagnostics = fuelDiagnostics
        self.marine = marine
        self.appState = appState
        self.healthSummary = healthSummary ?? DashboardHealthEvaluator.makeSummary(
            network: network,
            power: power,
            travelContext: travelContext,
            appState: appState
        )
    }
}

public extension DashboardSnapshot {
    static let placeholder = DashboardSnapshot(
        network: NetworkSectionSnapshot(
            throughput: NetworkThroughputSample(
                downloadBytesPerSecond: 0,
                uploadBytesPerSecond: 0,
                activeInterface: nil,
                collectedAt: .now
            ),
            connectivity: .checking,
            latency: nil,
            downloadHistory: [],
            uploadHistory: [],
            latencyHistory: []
        ),
        power: PowerSectionSnapshot(snapshot: nil, chargeHistory: [], dischargeHistory: []),
        travelContext: TravelContextSnapshot(
            wifi: nil,
            vpn: VPNStatusSnapshot(isActive: false, interfaceNames: [], serviceNames: []),
            timeZoneIdentifier: TimeZone.current.identifier,
            publicIP: nil,
            location: nil
        ),
        travelAlerts: TravelAlertsSnapshot(
            enabledKinds: [.advisory],
            primaryCountryCode: nil,
            primaryCountryName: nil,
            coverageCountryCodes: [],
            states: [
                TravelAlertSignalState(
                    kind: .advisory,
                    status: .checking,
                    signal: nil,
                    reason: nil,
                    sourceName: "Smartraveller",
                    sourceURL: URL(string: "https://www.smartraveller.gov.au"),
                    lastAttemptedAt: nil,
                    lastSuccessAt: nil
                )
            ],
            fetchedAt: nil
        ),
        weather: nil,
        fuelPrices: nil,
        marine: nil,
        appState: AppStatusSnapshot(lastRefresh: nil, updateState: .idle, issues: [])
    )

    static let preview = DashboardSnapshot(
        network: NetworkSectionSnapshot(
            throughput: NetworkThroughputSample(
                downloadBytesPerSecond: 12_000_000,
                uploadBytesPerSecond: 2_400_000,
                activeInterface: "en0",
                collectedAt: .now
            ),
            connectivity: ConnectivitySnapshot(pathAvailable: true, internetState: .online, lastCheckedAt: .now),
            latency: LatencySample(
                host: "1.1.1.1",
                milliseconds: 28,
                jitterMilliseconds: 3,
                collectedAt: .now
            ),
            downloadHistory: stride(from: 0, through: 9, by: 1).map {
                MetricPoint(timestamp: Date().addingTimeInterval(Double(-$0) * 60), value: 65 - Double($0 * 3))
            }.reversed(),
            uploadHistory: stride(from: 0, through: 9, by: 1).map {
                MetricPoint(timestamp: Date().addingTimeInterval(Double(-$0) * 60), value: 12 - Double($0))
            }.reversed(),
            latencyHistory: stride(from: 0, through: 9, by: 1).map {
                MetricPoint(timestamp: Date().addingTimeInterval(Double(-$0) * 60), value: 22 + Double($0))
            }.reversed()
        ),
        power: PowerSectionSnapshot(
            snapshot: PowerSnapshot(
                chargePercent: 0.72,
                state: .battery,
                timeRemainingMinutes: 208,
                timeToFullChargeMinutes: nil,
                isLowPowerModeEnabled: false,
                dischargeRateWatts: 11.4,
                adapterWatts: nil,
                collectedAt: .now
            ),
            chargeHistory: stride(from: 0, through: 9, by: 1).map {
                MetricPoint(timestamp: Date().addingTimeInterval(Double(-$0) * 60), value: 72.0 + Double($0) * 0.3)
            }.reversed(),
            dischargeHistory: stride(from: 0, through: 9, by: 1).map {
                MetricPoint(timestamp: Date().addingTimeInterval(Double(-$0) * 60), value: 9.5 + Double($0) * 0.2)
            }.reversed()
        ),
        travelContext: TravelContextSnapshot(
            wifi: WiFiSnapshot(interfaceName: "en0", ssid: "Nomad Hub", rssi: -56, noise: -91, transmitRateMbps: 720),
            vpn: VPNStatusSnapshot(isActive: true, interfaceNames: [], serviceNames: ["Nomad VPN"]),
            timeZoneIdentifier: "Europe/Madrid",
            publicIP: PublicIPSnapshot(address: "203.0.113.42", provider: "preview", fetchedAt: .now),
            location: IPLocationSnapshot(
                city: "Valencia",
                region: "Valencian Community",
                country: "Spain",
                countryCode: "ES",
                latitude: 39.4699,
                longitude: -0.3763,
                timeZone: "Europe/Madrid",
                provider: "preview",
                fetchedAt: .now
            )
        ),
        travelAlerts: TravelAlertsSnapshot(
            enabledKinds: [.advisory, .weather, .security],
            primaryCountryCode: "ES",
            primaryCountryName: "Spain",
            coverageCountryCodes: ["ES", "FR", "PT", "AD", "MA"],
            states: [
                TravelAlertSignalState(
                    kind: .advisory,
                    status: .ready,
                    signal: TravelAlertSignalSnapshot(
                        kind: .advisory,
                        severity: .caution,
                        title: "Travel advisory",
                        summary: "France remains at a higher caution level nearby.",
                        sourceName: "Smartraveller",
                        sourceURL: URL(string: "https://www.smartraveller.gov.au"),
                        updatedAt: .now,
                        affectedCountryCodes: ["FR"]
                    ),
                    reason: nil,
                    sourceName: "Smartraveller",
                    sourceURL: URL(string: "https://www.smartraveller.gov.au"),
                    lastAttemptedAt: .now,
                    lastSuccessAt: .now
                ),
                TravelAlertSignalState(
                    kind: .weather,
                    status: .ready,
                    signal: TravelAlertSignalSnapshot(
                        kind: .weather,
                        severity: .clear,
                        title: "Weather alerts",
                        summary: "No severe weather alerts near Valencia.",
                        sourceName: "WeatherKit",
                        sourceURL: URL(string: "https://developer.apple.com/weatherkit/"),
                        updatedAt: .now,
                        affectedCountryCodes: ["ES"]
                    ),
                    reason: nil,
                    sourceName: "WeatherKit",
                    sourceURL: URL(string: "https://developer.apple.com/weatherkit/"),
                    lastAttemptedAt: .now,
                    lastSuccessAt: .now
                ),
                TravelAlertSignalState(
                    kind: .security,
                    status: .stale,
                    signal: TravelAlertSignalSnapshot(
                        kind: .security,
                        severity: .info,
                        title: "Regional security",
                        summary: "One recent security bulletin was published nearby.",
                        sourceName: "ReliefWeb",
                        sourceURL: URL(string: "https://reliefweb.int"),
                        updatedAt: .now,
                        affectedCountryCodes: ["MA"],
                        itemCount: 1
                    ),
                    reason: .sourceUnavailable,
                    sourceName: "ReliefWeb",
                    sourceURL: URL(string: "https://reliefweb.int"),
                    lastAttemptedAt: .now,
                    lastSuccessAt: Date().addingTimeInterval(-900)
                )
            ],
            fetchedAt: .now
        ),
        weather: WeatherSnapshot(
            currentTemperatureCelsius: 19,
            apparentTemperatureCelsius: 18,
            conditionDescription: "Partly Cloudy",
            symbolName: "cloud.sun.fill",
            precipitationChance: 0.18,
            windSpeedKph: 14,
            tomorrow: WeatherDaySummary(
                date: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now,
                symbolName: "sun.max.fill",
                summary: "Clear and mild",
                temperatureMinCelsius: 13,
                temperatureMaxCelsius: 23,
                precipitationChance: 0.04
            ),
            fetchedAt: .now
        ),
        fuelPrices: FuelPriceSnapshot(
            status: .ready,
            sourceName: "Spanish Ministry for the Ecological Transition",
            sourceURL: URL(string: "https://sedeaplicaciones.minetur.gob.es/ServiciosRESTCarburantes/PreciosCarburantes/EstacionesTerrestres/"),
            countryCode: "ES",
            countryName: "Spain",
            searchRadiusKilometers: 50,
            diesel: FuelStationPrice(
                fuelType: .diesel,
                stationName: "Plenoil Valencia Puerto",
                address: "Carrer d'Eivissa 12",
                locality: "Valencia",
                pricePerLiter: 1.429,
                distanceKilometers: 4.8,
                latitude: 39.457,
                longitude: -0.332,
                updatedAt: .now,
                isSelfService: nil
            ),
            gasoline: FuelStationPrice(
                fuelType: .gasoline,
                stationName: "Ballenoil Alfafar",
                address: "Carrer Alcalde José Puertes",
                locality: "Alfafar",
                pricePerLiter: 1.519,
                distanceKilometers: 8.6,
                latitude: 39.423,
                longitude: -0.384,
                updatedAt: .now,
                isSelfService: nil
            ),
            fetchedAt: .now,
            detail: "Cheapest prices within 50 km.",
            note: nil
        ),
        fuelDiagnostics: FuelDiagnosticsSnapshot(
            status: .ready,
            stage: .bestPriceSelection,
            countryCode: "ES",
            countryName: "Spain",
            latitude: 39.4699,
            longitude: -0.3763,
            searchRadiusKilometers: 50,
            providerName: "Spanish Ministry for the Ecological Transition",
            sourceURL: URL(string: "https://sedeaplicaciones.minetur.gob.es/ServiciosRESTCarburantes/PreciosCarburantes/EstacionesTerrestres/"),
            startedAt: Date().addingTimeInterval(-1.2),
            finishedAt: .now,
            elapsedMilliseconds: 1_200,
            summary: "Fuel prices loaded successfully.",
            error: nil
        ),
        marine: MarineSnapshot(
            spotName: "El Saler",
            coordinate: CLLocationCoordinate2D(latitude: 39.355, longitude: -0.314),
            sourceName: "Open-Meteo",
            waveHeightMeters: 1.6,
            wavePeriodSeconds: 11,
            swellHeightMeters: 1.2,
            swellPeriodSeconds: 10,
            swellDirectionDegrees: 67.5,
            windSpeedKph: 18,
            windGustKph: 24,
            windDirectionDegrees: 315,
            seaSurfaceTemperatureCelsius: 17,
            forecastSlots: [
                MarineForecastSlot(date: .now, waveHeightMeters: 1.6, swellHeightMeters: 1.2, windSpeedKph: 18, windDirectionDegrees: 315),
                MarineForecastSlot(date: Date().addingTimeInterval(3 * 3_600), waveHeightMeters: 1.5, swellHeightMeters: 1.1, windSpeedKph: 16, windDirectionDegrees: 300),
                MarineForecastSlot(date: Date().addingTimeInterval(6 * 3_600), waveHeightMeters: 1.3, swellHeightMeters: 1.0, windSpeedKph: 14, windDirectionDegrees: 290),
                MarineForecastSlot(date: Date().addingTimeInterval(12 * 3_600), waveHeightMeters: 1.1, swellHeightMeters: 0.9, windSpeedKph: 11, windDirectionDegrees: 270)
            ],
            fetchedAt: .now
        ),
        appState: AppStatusSnapshot(
            lastRefresh: .now,
            updateState: UpdateStateSnapshot(kind: .idle, detail: "Up to date", lastCheckedAt: .now),
            issues: []
        )
    )

    func replacingTravelAlerts(_ travelAlerts: TravelAlertsSnapshot?) -> DashboardSnapshot {
        DashboardSnapshot(
            network: network,
            power: power,
            travelContext: travelContext,
            travelAlerts: travelAlerts,
            weather: weather,
            fuelPrices: fuelPrices,
            fuelDiagnostics: fuelDiagnostics,
            marine: marine,
            appState: appState,
            healthSummary: healthSummary
        )
    }
}
