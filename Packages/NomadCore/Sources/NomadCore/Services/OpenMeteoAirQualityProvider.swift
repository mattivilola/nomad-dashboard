import CoreLocation
import Foundation

/// Fetches current air quality and a 12 hour European AQI outlook from the keyless Open-Meteo Air Quality API
/// (CAMS Europe 0.1° ≈ 11 km, CAMS global 0.4° elsewhere).
///
/// Privacy: the coordinate is rounded to one decimal (~11 km) before it leaves the Mac, so the provider never
/// learns the exact device location. The rounded point is also the cache key and is stored in the snapshot.
public actor LiveOpenMeteoAirQualityProvider: AirQualityProvider {
    static let forecastHours = 12
    private static let currentVariables = [
        "european_aqi",
        "pm2_5",
        "pm10",
        "ozone",
        "nitrogen_dioxide",
        "european_aqi_pm2_5",
        "european_aqi_pm10",
        "european_aqi_ozone",
        "european_aqi_nitrogen_dioxide",
        "european_aqi_sulphur_dioxide"
    ]

    private let session: URLSession
    private let ttl: TimeInterval
    private let endpoint: URL
    private var cache: [String: AirQualitySnapshot] = [:]

    public init(
        session: URLSession = .shared,
        ttl: TimeInterval = 1_800,
        endpoint: URL = URL(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
    ) {
        self.session = session
        self.ttl = ttl
        self.endpoint = endpoint
    }

    public func airQuality(for coordinate: CLLocationCoordinate2D) async throws -> AirQualitySnapshot {
        guard let grid = Self.privacyGridPoint(for: coordinate) else {
            throw ProviderError.missingCoordinate
        }

        let cacheKey = Self.cacheKey(for: grid)
        if let cached = cache[cacheKey], abs(cached.fetchedAt.timeIntervalSinceNow) < ttl {
            return cached
        }

        let response = try await fetchResponse(for: grid)
        let snapshot = try Self.buildSnapshot(response: response, grid: grid, now: Date())
        cache[cacheKey] = snapshot
        return snapshot
    }

    /// The coordinate rounded to one decimal, or nil when it is not a valid latitude/longitude.
    static func privacyGridPoint(for coordinate: CLLocationCoordinate2D) -> (latitude: Double, longitude: Double)? {
        guard coordinate.latitude.isFinite, coordinate.longitude.isFinite,
              (-90.0...90.0).contains(coordinate.latitude),
              (-180.0...180.0).contains(coordinate.longitude)
        else {
            return nil
        }

        func round(_ value: Double) -> Double {
            let rounded = (value * 10).rounded() / 10
            return rounded == 0 ? 0 : rounded // normalises -0.0
        }

        return (round(coordinate.latitude), round(coordinate.longitude))
    }

    private static func cacheKey(for grid: (latitude: Double, longitude: Double)) -> String {
        "\(coordinateString(grid.latitude)),\(coordinateString(grid.longitude))"
    }

    private static func coordinateString(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func fetchResponse(for grid: (latitude: Double, longitude: Double)) async throws -> OpenMeteoAirQualityResponse {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: Self.coordinateString(grid.latitude)),
            URLQueryItem(name: "longitude", value: Self.coordinateString(grid.longitude)),
            URLQueryItem(name: "current", value: Self.currentVariables.joined(separator: ",")),
            URLQueryItem(name: "hourly", value: "european_aqi"),
            // The hourly series starts at the current hour, so one extra hour yields the next 12.
            URLQueryItem(name: "forecast_hours", value: String(Self.forecastHours + 1)),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        guard let url = components?.url else {
            throw ProviderError.invalidResponse
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw ProviderError.invalidResponse
        }

        return try JSONDecoder().decode(OpenMeteoAirQualityResponse.self, from: data)
    }

    static func buildSnapshot(
        response: OpenMeteoAirQualityResponse,
        grid: (latitude: Double, longitude: Double),
        now: Date
    ) throws -> AirQualitySnapshot {
        // Outside the model's coverage Open-Meteo answers with nulls; there is nothing useful to show then.
        guard let current = response.current, let currentAQI = current.europeanAQI.flatMap(Self.wholeIndex) else {
            throw ProviderError.invalidResponse
        }

        let times = try OpenMeteoTimestamps.dates(
            from: response.hourly.time,
            timezoneIdentifier: response.timezone,
            utcOffsetSeconds: response.utcOffsetSeconds
        )
        guard times.count == response.hourly.europeanAQI.count else {
            throw ProviderError.invalidResponse
        }

        let slots = zip(times, response.hourly.europeanAQI)
            .filter { $0.0 > now }
            .sorted { $0.0 < $1.0 }
            .prefix(forecastHours)
            .map { AirQualityForecastSlot(date: $0.0, europeanAQI: $0.1.flatMap(Self.wholeIndex)) }

        let subIndices = [AirQualityPollutant: Double?](uniqueKeysWithValues: [
            (.pm2_5, current.europeanAQIPM2_5),
            (.pm10, current.europeanAQIPM10),
            (.ozone, current.europeanAQIOzone),
            (.nitrogenDioxide, current.europeanAQINitrogenDioxide),
            (.sulphurDioxide, current.europeanAQISulphurDioxide)
        ]).compactMapValues { $0 }

        return AirQualitySnapshot(
            latitude: grid.latitude,
            longitude: grid.longitude,
            sourceName: "Open-Meteo",
            europeanAQI: currentAQI,
            mainPollutant: AirQualityPollutant.dominant(in: subIndices),
            pm2_5: current.pm2_5,
            pm10: current.pm10,
            ozone: current.ozone,
            nitrogenDioxide: current.nitrogenDioxide,
            forecastSlots: Array(slots),
            fetchedAt: now
        )
    }

    private static func wholeIndex(_ value: Double) -> Int? {
        value.isFinite && value >= 0 ? Int(value.rounded()) : nil
    }
}

struct OpenMeteoAirQualityResponse: Decodable {
    let timezone: String?
    let utcOffsetSeconds: Int?
    let current: Current?
    let hourly: Hourly

    enum CodingKeys: String, CodingKey {
        case timezone
        case utcOffsetSeconds = "utc_offset_seconds"
        case current
        case hourly
    }

    struct Current: Decodable {
        let europeanAQI: Double?
        let pm2_5: Double?
        let pm10: Double?
        let ozone: Double?
        let nitrogenDioxide: Double?
        let europeanAQIPM2_5: Double?
        let europeanAQIPM10: Double?
        let europeanAQIOzone: Double?
        let europeanAQINitrogenDioxide: Double?
        let europeanAQISulphurDioxide: Double?

        enum CodingKeys: String, CodingKey {
            case europeanAQI = "european_aqi"
            case pm2_5
            case pm10
            case ozone
            case nitrogenDioxide = "nitrogen_dioxide"
            case europeanAQIPM2_5 = "european_aqi_pm2_5"
            case europeanAQIPM10 = "european_aqi_pm10"
            case europeanAQIOzone = "european_aqi_ozone"
            case europeanAQINitrogenDioxide = "european_aqi_nitrogen_dioxide"
            case europeanAQISulphurDioxide = "european_aqi_sulphur_dioxide"
        }
    }

    struct Hourly: Decodable {
        let time: [String]
        let europeanAQI: [Double?]

        enum CodingKeys: String, CodingKey {
            case time
            case europeanAQI = "european_aqi"
        }
    }
}
