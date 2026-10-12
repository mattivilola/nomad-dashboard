import CoreLocation
import Foundation

/// European Air Quality Index (EAQI) bands.
///
/// Sources:
/// - EEA European Air Quality Index, https://airindex.eea.europa.eu/AQI/index.html: six classes (good, fair,
///   moderate, poor, very poor, extremely poor); the overall class is the poorest class of PM2.5, PM10, O3, NO2 and SO2.
/// - Open-Meteo Air Quality API, https://open-meteo.com/en/docs/air-quality-api (2024 EEA revision): the numeric
///   `european_aqi` scale used here, where 0-20 is good, 20-40 fair, 40-60 moderate, 60-80 poor, 80-100 very poor
///   and above 100 extremely poor. `european_aqi` is the maximum of the per-pollutant `european_aqi_*` indices.
///
/// A band starts at its lower bound (an index of exactly 60 is already "poor"); 100 is still "very poor".
public enum EuropeanAQIBand: Int, Codable, CaseIterable, Comparable, Sendable {
    case good, fair, moderate, poor, veryPoor, extremelyPoor

    public static let fairThreshold = 20
    public static let moderateThreshold = 40
    public static let poorThreshold = 60
    public static let veryPoorThreshold = 80
    public static let extremelyPoorThreshold = 100

    public init(index: Int) {
        switch index {
        case ..<Self.fairThreshold: self = .good
        case ..<Self.moderateThreshold: self = .fair
        case ..<Self.poorThreshold: self = .moderate
        case ..<Self.veryPoorThreshold: self = .poor
        case ...Self.extremelyPoorThreshold: self = .veryPoor
        default: self = .extremelyPoor
        }
    }

    public var title: String {
        switch self {
        case .good: "Good"
        case .fair: "Fair"
        case .moderate: "Moderate"
        case .poor: "Poor"
        case .veryPoor: "Very poor"
        case .extremelyPoor: "Extremely poor"
        }
    }

    public static func < (lhs: EuropeanAQIBand, rhs: EuropeanAQIBand) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The pollutants that make up the European AQI.
public enum AirQualityPollutant: String, Codable, CaseIterable, Sendable {
    case pm2_5, pm10, ozone, nitrogenDioxide, sulphurDioxide

    public var displayName: String {
        switch self {
        case .pm2_5: "PM2.5"
        case .pm10: "PM10"
        case .ozone: "ozone"
        case .nitrogenDioxide: "NO₂"
        case .sulphurDioxide: "SO₂"
        }
    }

    /// The pollutant with the highest sub-index, which is the one that sets the overall European AQI.
    /// Ties go to the earlier pollutant in `allCases`; nil when no sub-index is positive.
    public static func dominant(in subIndices: [AirQualityPollutant: Double]) -> AirQualityPollutant? {
        allCases
            .compactMap { pollutant in subIndices[pollutant].map { (pollutant, $0) } }
            .filter { $0.1 > 0 }
            .reduce(nil as (AirQualityPollutant, Double)?) { best, candidate in
                guard let best else { return candidate }
                return candidate.1 > best.1 ? candidate : best
            }?.0
    }
}

public struct AirQualityForecastSlot: Codable, Equatable, Sendable, Identifiable {
    public let date: Date
    public let europeanAQI: Int?

    public var id: Date {
        date
    }

    public init(date: Date, europeanAQI: Int?) {
        self.date = date
        self.europeanAQI = europeanAQI
    }
}

/// Current air quality and a 12 hour European AQI outlook for the weather location.
///
/// The coordinates are the ~11 km grid point that was requested, never the exact device location.
public struct AirQualitySnapshot: Codable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let sourceName: String
    public let europeanAQI: Int
    public let mainPollutant: AirQualityPollutant?
    /// Concentrations in µg/m³.
    public let pm2_5: Double?
    public let pm10: Double?
    public let ozone: Double?
    public let nitrogenDioxide: Double?
    /// Hourly European AQI after `fetchedAt`, earliest first (up to 12).
    public let forecastSlots: [AirQualityForecastSlot]
    public let fetchedAt: Date

    public var band: EuropeanAQIBand {
        EuropeanAQIBand(index: europeanAQI)
    }

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    public init(
        latitude: Double,
        longitude: Double,
        sourceName: String,
        europeanAQI: Int,
        mainPollutant: AirQualityPollutant?,
        pm2_5: Double?,
        pm10: Double?,
        ozone: Double?,
        nitrogenDioxide: Double?,
        forecastSlots: [AirQualityForecastSlot],
        fetchedAt: Date
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.sourceName = sourceName
        self.europeanAQI = europeanAQI
        self.mainPollutant = mainPollutant
        self.pm2_5 = pm2_5
        self.pm10 = pm10
        self.ozone = ozone
        self.nitrogenDioxide = nitrogenDioxide
        self.forecastSlots = forecastSlots
        self.fetchedAt = fetchedAt
    }
}
