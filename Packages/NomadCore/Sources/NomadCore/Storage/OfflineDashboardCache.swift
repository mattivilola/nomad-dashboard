import Foundation

/// The remote and place-derived parts of a dashboard snapshot that remain useful offline.
/// Live network, latency, battery, diagnostics, and metric history intentionally stay out of this value.
public struct OfflineDashboardContent: Codable, Equatable, Sendable {
    public let savedAt: Date
    public let locationKey: String?
    public let weather: WeatherSnapshot?
    public let localInfo: LocalInfoSnapshot?
    public let fuelPrices: FuelPriceSnapshot?
    public let emergencyCare: EmergencyCareSnapshot?
    public let marine: MarineSnapshot?
    public let travelAlerts: TravelAlertsSnapshot?
    public let deviceLocation: IPLocationSnapshot?
    public let location: IPLocationSnapshot?

    public init(snapshot: DashboardSnapshot, savedAt: Date, locationKey: String?) {
        self.savedAt = savedAt
        let trimmedLocationKey = locationKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.locationKey = trimmedLocationKey.isEmpty ? nil : trimmedLocationKey
        weather = Self.bounded(snapshot.weather)
        localInfo = snapshot.localInfo
        fuelPrices = snapshot.fuelPrices
        emergencyCare = Self.bounded(snapshot.emergencyCare)
        marine = Self.bounded(snapshot.marine)
        travelAlerts = Self.bounded(snapshot.travelAlerts)
        deviceLocation = snapshot.travelContext.deviceLocation
        location = snapshot.travelContext.location
    }

    /// Applies cached remote content while retaining the caller's live network, power, and app state.
    public func applying(to snapshot: DashboardSnapshot) -> DashboardSnapshot {
        DashboardSnapshot(
            network: snapshot.network,
            power: snapshot.power,
            travelContext: TravelContextSnapshot(
                wifi: snapshot.travelContext.wifi,
                vpn: snapshot.travelContext.vpn,
                timeZoneIdentifier: snapshot.travelContext.timeZoneIdentifier,
                deviceLocation: deviceLocation ?? snapshot.travelContext.deviceLocation,
                publicIP: snapshot.travelContext.publicIP,
                location: location ?? snapshot.travelContext.location
            ),
            travelAlerts: travelAlerts,
            weather: weather,
            localInfo: localInfo,
            fuelPrices: fuelPrices,
            fuelDiagnostics: snapshot.fuelDiagnostics,
            emergencyCare: emergencyCare,
            marine: marine,
            appState: snapshot.appState
        )
    }

    private static func bounded(_ weather: WeatherSnapshot?) -> WeatherSnapshot? {
        guard let weather else { return nil }
        return WeatherSnapshot(
            currentTemperatureCelsius: weather.currentTemperatureCelsius,
            apparentTemperatureCelsius: weather.apparentTemperatureCelsius,
            conditionDescription: weather.conditionDescription,
            symbolName: weather.symbolName,
            precipitationChance: weather.precipitationChance,
            windSpeedKph: weather.windSpeedKph,
            windDirectionDegrees: weather.windDirectionDegrees,
            hourlyForecastSlots: Array(weather.hourlyForecastSlots.prefix(48)),
            dailyForecast: Array(weather.dailyForecast.prefix(10)),
            fetchedAt: weather.fetchedAt
        )
    }

    private static func bounded(_ emergencyCare: EmergencyCareSnapshot?) -> EmergencyCareSnapshot? {
        guard let emergencyCare else { return nil }
        return EmergencyCareSnapshot(
            status: emergencyCare.status,
            sourceName: emergencyCare.sourceName,
            sourceURL: emergencyCare.sourceURL,
            searchRadiusKilometers: emergencyCare.searchRadiusKilometers,
            hospitals: Array(emergencyCare.hospitals.prefix(12)),
            fetchedAt: emergencyCare.fetchedAt,
            detail: emergencyCare.detail
        )
    }

    private static func bounded(_ marine: MarineSnapshot?) -> MarineSnapshot? {
        guard let marine else { return nil }
        return MarineSnapshot(
            spotName: marine.spotName,
            coordinate: marine.coordinate,
            sourceName: marine.sourceName,
            waveHeightMeters: marine.waveHeightMeters,
            wavePeriodSeconds: marine.wavePeriodSeconds,
            swellHeightMeters: marine.swellHeightMeters,
            swellPeriodSeconds: marine.swellPeriodSeconds,
            swellDirectionDegrees: marine.swellDirectionDegrees,
            windSpeedKph: marine.windSpeedKph,
            windGustKph: marine.windGustKph,
            windDirectionDegrees: marine.windDirectionDegrees,
            seaSurfaceTemperatureCelsius: marine.seaSurfaceTemperatureCelsius,
            forecastSlots: Array(marine.forecastSlots.prefix(48)),
            fetchedAt: marine.fetchedAt
        )
    }

    private static func bounded(_ alerts: TravelAlertsSnapshot?) -> TravelAlertsSnapshot? {
        guard let alerts else { return nil }
        let usefulStates = alerts.states.compactMap { state -> TravelAlertSignalState? in
            guard let signal = state.resolvedSignal else { return nil }
            return TravelAlertSignalState(
                kind: state.kind,
                status: state.status,
                signal: signal,
                reason: nil,
                diagnosticSummary: nil,
                sourceName: state.sourceName,
                sourceURL: state.sourceURL,
                lastAttemptedAt: nil,
                lastSuccessAt: state.lastSuccessAt
            )
        }
        return TravelAlertsSnapshot(
            enabledKinds: Array(alerts.enabledKinds.prefix(3)),
            primaryCountryCode: alerts.primaryCountryCode,
            primaryCountryName: alerts.primaryCountryName,
            coverageCountryCodes: Array(alerts.coverageCountryCodes.prefix(24)),
            states: Array(usefulStates.prefix(3)),
            fetchedAt: alerts.fetchedAt
        )
    }
}

public actor OfflineDashboardCache {
    private static let supportedVersion = 1
    private static let maximumPayloadBytes = 512 * 1_024

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() async throws -> OfflineDashboardContent? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
            guard data.count <= Self.maximumPayloadBytes else {
                throw OfflineDashboardCacheError.payloadTooLarge(fileURL: fileURL, byteCount: data.count)
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let version = object["version"] as? Int
            else {
                throw OfflineDashboardCacheError.corruptCache(fileURL: fileURL)
            }
            guard version == Self.supportedVersion else { return nil }
            return try decoder.decode(Payload.self, from: data).content
        } catch let error as OfflineDashboardCacheError {
            throw error
        } catch {
            throw OfflineDashboardCacheError.corruptCache(fileURL: fileURL)
        }
    }

    public func save(_ content: OfflineDashboardContent) async throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(Payload(version: Self.supportedVersion, content: content))
        guard data.count <= Self.maximumPayloadBytes else {
            throw OfflineDashboardCacheError.payloadTooLarge(fileURL: fileURL, byteCount: data.count)
        }
        try data.write(to: fileURL, options: [.atomic])
    }

    private struct Payload: Codable {
        let version: Int
        let content: OfflineDashboardContent
    }
}

public enum OfflineDashboardCacheError: LocalizedError, Equatable {
    case corruptCache(fileURL: URL)
    case payloadTooLarge(fileURL: URL, byteCount: Int)

    public var errorDescription: String? {
        switch self {
        case let .corruptCache(fileURL):
            "Offline dashboard cache at \(fileURL.lastPathComponent) could not be read."
        case let .payloadTooLarge(fileURL, byteCount):
            "Offline dashboard cache at \(fileURL.lastPathComponent) exceeds its \(byteCount)-byte safety limit."
        }
    }
}
