import CoreLocation
import Foundation

public actor LiveOpenMeteoMarineProvider: MarineProvider {
    private let session: URLSession
    private let ttl: TimeInterval
    private let marineEndpoint: URL
    private let forecastEndpoint: URL
    private var cache: [String: MarineSnapshot] = [:]

    public init(
        session: URLSession = .shared,
        ttl: TimeInterval = 1_800,
        marineEndpoint: URL = URL(string: "https://marine-api.open-meteo.com/v1/marine")!,
        forecastEndpoint: URL = URL(string: "https://api.open-meteo.com/v1/forecast")!
    ) {
        self.session = session
        self.ttl = ttl
        self.marineEndpoint = marineEndpoint
        self.forecastEndpoint = forecastEndpoint
    }

    public func marine(for spot: MarineSpot) async throws -> MarineSnapshot {
        let cacheKey = Self.cacheKey(for: spot)

        if let cached = cache[cacheKey], abs(cached.fetchedAt.timeIntervalSinceNow) < ttl {
            return cached
        }

        async let marineResponse = fetchMarineResponse(for: spot.coordinate)
        async let forecastResponse = fetchForecastResponse(for: spot.coordinate)

        let snapshot = try await buildSnapshot(
            spot: spot,
            marineResponse: marineResponse,
            forecastResponse: forecastResponse,
            now: Date()
        )
        cache[cacheKey] = snapshot
        return snapshot
    }

    private func fetchMarineResponse(for coordinate: CLLocationCoordinate2D) async throws -> OpenMeteoMarineResponse {
        var components = URLComponents(url: marineEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(
                name: "hourly",
                value: [
                    "wave_height",
                    "wave_period",
                    "swell_wave_height",
                    "swell_wave_period",
                    "swell_wave_direction",
                    "sea_surface_temperature"
                ].joined(separator: ",")
            ),
            URLQueryItem(name: "forecast_days", value: "2"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        guard let url = components?.url else {
            throw ProviderError.invalidResponse
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw ProviderError.invalidResponse
        }

        return try JSONDecoder().decode(OpenMeteoMarineResponse.self, from: data)
    }

    private func fetchForecastResponse(for coordinate: CLLocationCoordinate2D) async throws -> OpenMeteoForecastResponse {
        var components = URLComponents(url: forecastEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(
                name: "hourly",
                value: [
                    "wind_speed_10m",
                    "wind_gusts_10m",
                    "wind_direction_10m"
                ].joined(separator: ",")
            ),
            URLQueryItem(name: "forecast_days", value: "2"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        guard let url = components?.url else {
            throw ProviderError.invalidResponse
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw ProviderError.invalidResponse
        }

        return try JSONDecoder().decode(OpenMeteoForecastResponse.self, from: data)
    }

    private func buildSnapshot(
        spot: MarineSpot,
        marineResponse: OpenMeteoMarineResponse,
        forecastResponse: OpenMeteoForecastResponse,
        now: Date
    ) throws -> MarineSnapshot {
        let marineSeries = try MarineSeries(response: marineResponse)
        let forecastSeries = try ForecastSeries(response: forecastResponse)
        guard let currentMarineIndex = Self.nearestIndex(in: marineSeries.times, to: now),
              let currentForecastIndex = Self.nearestIndex(in: forecastSeries.times, to: now)
        else {
            throw ProviderError.invalidResponse
        }

        let forecastHourOffsets: [Int] = [3, 6, 12, 24]
        let forecastSlots: [MarineForecastSlot] = forecastHourOffsets.compactMap { hourOffset in
            let targetDate = now.addingTimeInterval(TimeInterval(hourOffset * 3_600))
            guard let marineIndex = Self.nearestIndex(in: marineSeries.times, to: targetDate),
                  let forecastIndex = Self.nearestIndex(in: forecastSeries.times, to: targetDate)
            else {
                return nil
            }

            return MarineForecastSlot(
                date: targetDate,
                waveHeightMeters: marineSeries.waveHeight.value(at: marineIndex),
                swellHeightMeters: marineSeries.swellWaveHeight.value(at: marineIndex),
                windSpeedKph: forecastSeries.windSpeed.value(at: forecastIndex),
                windDirectionDegrees: forecastSeries.windDirection.value(at: forecastIndex)
            )
        }

        return MarineSnapshot(
            spotName: spot.name,
            coordinate: spot.coordinate,
            sourceName: "Open-Meteo",
            waveHeightMeters: marineSeries.waveHeight.value(at: currentMarineIndex),
            wavePeriodSeconds: marineSeries.wavePeriod.value(at: currentMarineIndex),
            swellHeightMeters: marineSeries.swellWaveHeight.value(at: currentMarineIndex),
            swellPeriodSeconds: marineSeries.swellWavePeriod.value(at: currentMarineIndex),
            swellDirectionDegrees: marineSeries.swellWaveDirection.value(at: currentMarineIndex),
            windSpeedKph: forecastSeries.windSpeed.value(at: currentForecastIndex),
            windGustKph: forecastSeries.windGusts.value(at: currentForecastIndex),
            windDirectionDegrees: forecastSeries.windDirection.value(at: currentForecastIndex),
            seaSurfaceTemperatureCelsius: marineSeries.seaSurfaceTemperature.value(at: currentMarineIndex),
            forecastSlots: forecastSlots,
            fetchedAt: now
        )
    }

    private static func nearestIndex(in dates: [Date], to targetDate: Date) -> Int? {
        dates.enumerated().min { lhs, rhs in
            abs(lhs.element.timeIntervalSince(targetDate)) < abs(rhs.element.timeIntervalSince(targetDate))
        }?.offset
    }

    private static func cacheKey(for spot: MarineSpot) -> String {
        let latitude = String(format: "%.3f", spot.coordinate.latitude)
        let longitude = String(format: "%.3f", spot.coordinate.longitude)
        return "\(spot.name.lowercased())|\(latitude),\(longitude)"
    }
}

struct OpenMeteoMarineResponse: Decodable {
    let timezone: String?
    let utcOffsetSeconds: Int?
    let hourly: Hourly

    enum CodingKeys: String, CodingKey {
        case timezone
        case utcOffsetSeconds = "utc_offset_seconds"
        case hourly
    }

    struct Hourly: Decodable {
        let time: [String]
        let waveHeight: [Double?]
        let wavePeriod: [Double?]
        let swellWaveHeight: [Double?]
        let swellWavePeriod: [Double?]
        let swellWaveDirection: [Double?]
        let seaSurfaceTemperature: [Double?]

        enum CodingKeys: String, CodingKey {
            case time
            case waveHeight = "wave_height"
            case wavePeriod = "wave_period"
            case swellWaveHeight = "swell_wave_height"
            case swellWavePeriod = "swell_wave_period"
            case swellWaveDirection = "swell_wave_direction"
            case seaSurfaceTemperature = "sea_surface_temperature"
        }
    }
}

struct OpenMeteoForecastResponse: Decodable {
    let timezone: String?
    let utcOffsetSeconds: Int?
    let hourly: Hourly

    enum CodingKeys: String, CodingKey {
        case timezone
        case utcOffsetSeconds = "utc_offset_seconds"
        case hourly
    }

    struct Hourly: Decodable {
        let time: [String]
        let windSpeed: [Double?]
        let windGusts: [Double?]
        let windDirection: [Double?]

        enum CodingKeys: String, CodingKey {
            case time
            case windSpeed = "wind_speed_10m"
            case windGusts = "wind_gusts_10m"
            case windDirection = "wind_direction_10m"
        }
    }
}

private struct MarineSeries {
    let times: [Date]
    let waveHeight: [Double?]
    let wavePeriod: [Double?]
    let swellWaveHeight: [Double?]
    let swellWavePeriod: [Double?]
    let swellWaveDirection: [Double?]
    let seaSurfaceTemperature: [Double?]

    init(response: OpenMeteoMarineResponse) throws {
        times = try Self.parseDates(
            response.hourly.time,
            timezoneIdentifier: response.timezone,
            utcOffsetSeconds: response.utcOffsetSeconds
        )
        waveHeight = response.hourly.waveHeight
        wavePeriod = response.hourly.wavePeriod
        swellWaveHeight = response.hourly.swellWaveHeight
        swellWavePeriod = response.hourly.swellWavePeriod
        swellWaveDirection = response.hourly.swellWaveDirection
        seaSurfaceTemperature = response.hourly.seaSurfaceTemperature
    }
}

private struct ForecastSeries {
    let times: [Date]
    let windSpeed: [Double?]
    let windGusts: [Double?]
    let windDirection: [Double?]

    init(response: OpenMeteoForecastResponse) throws {
        times = try Self.parseDates(
            response.hourly.time,
            timezoneIdentifier: response.timezone,
            utcOffsetSeconds: response.utcOffsetSeconds
        )
        windSpeed = response.hourly.windSpeed
        windGusts = response.hourly.windGusts
        windDirection = response.hourly.windDirection
    }
}

private extension [Double?] {
    func value(at index: Int) -> Double? {
        guard indices.contains(index) else {
            return nil
        }

        return self[index]
    }
}

private extension MarineSeries {
    static func parseDates(_ values: [String], timezoneIdentifier: String?, utcOffsetSeconds: Int?) throws -> [Date] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"

        if let timezoneIdentifier, let timezone = TimeZone(identifier: timezoneIdentifier) {
            formatter.timeZone = timezone
        } else if let utcOffsetSeconds, let timezone = TimeZone(secondsFromGMT: utcOffsetSeconds) {
            formatter.timeZone = timezone
        } else {
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
        }

        let dates = values.compactMap { formatter.date(from: $0) }
        guard dates.count == values.count else {
            throw ProviderError.invalidResponse
        }

        return dates
    }
}

private extension ForecastSeries {
    static func parseDates(_ values: [String], timezoneIdentifier: String?, utcOffsetSeconds: Int?) throws -> [Date] {
        try MarineSeries.parseDates(values, timezoneIdentifier: timezoneIdentifier, utcOffsetSeconds: utcOffsetSeconds)
    }
}
