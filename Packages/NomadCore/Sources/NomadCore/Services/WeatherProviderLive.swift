import CoreLocation
import Foundation
import WeatherKit

public actor LiveWeatherProvider: WeatherProvider {
    private let loadSnapshot: @Sendable (CLLocationCoordinate2D) async throws -> WeatherSnapshot
    private let ttl: TimeInterval
    private var cache: (key: String, snapshot: WeatherSnapshot)?
    static let forecastHourOffsets = [3, 6, 12, 24]

    public init(service: WeatherService = WeatherService(), ttl: TimeInterval = 1_800) {
        loadSnapshot = { coordinate in
            try await WeatherKitSnapshotProjector.snapshot(using: service, coordinate: coordinate)
        }
        self.ttl = ttl
    }

    init(ttl: TimeInterval = 1_800, loadSnapshot: @escaping @Sendable (CLLocationCoordinate2D) async throws -> WeatherSnapshot) {
        self.ttl = ttl
        self.loadSnapshot = loadSnapshot
    }

    public func weather(for coordinate: CLLocationCoordinate2D?) async throws -> WeatherSnapshot {
        try await weather(for: coordinate, forceRefresh: false)
    }

    public func weather(for coordinate: CLLocationCoordinate2D?, forceRefresh: Bool) async throws -> WeatherSnapshot {
        guard let coordinate else {
            throw ProviderError.missingCoordinate
        }

        let cacheKey = Self.cacheKey(for: coordinate)

        if !forceRefresh, let cache, cache.key == cacheKey, abs(cache.snapshot.fetchedAt.timeIntervalSinceNow) < ttl {
            return cache.snapshot
        }

        let snapshot = try await loadSnapshot(coordinate)

        cache = (cacheKey, snapshot)
        return snapshot
    }

    static func nearTermPrecipitationChance(minuteForecastChance: Double?, hourlyForecastChance: Double?) -> Double? {
        minuteForecastChance ?? hourlyForecastChance
    }

    static func forecastTargetDates(from referenceDate: Date) -> [Date] {
        forecastHourOffsets.map { referenceDate.addingTimeInterval(TimeInterval($0 * 3_600)) }
    }

    static func upcomingDailyForecasts(_ days: [WeatherDaySummary], now: Date = .now, calendar: Calendar = .current) -> [WeatherDaySummary] {
        Array(days.filter { $0.date >= calendar.startOfDay(for: now) }.sorted { $0.date < $1.date }.prefix(7))
    }

    static func nearestIndex(in dates: [Date], to targetDate: Date) -> Int? {
        dates.enumerated().min { lhs, rhs in
            abs(lhs.element.timeIntervalSince(targetDate)) < abs(rhs.element.timeIntervalSince(targetDate))
        }?.offset
    }

    private static func cacheKey(for coordinate: CLLocationCoordinate2D) -> String {
        let latitude = String(format: "%.3f", coordinate.latitude)
        let longitude = String(format: "%.3f", coordinate.longitude)
        return "\(latitude),\(longitude)"
    }
}

private enum WeatherKitSnapshotProjector {
    static func snapshot(using service: WeatherService, coordinate: CLLocationCoordinate2D) async throws -> WeatherSnapshot {
        let weather = try await service.weather(
            for: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        )
        let fetchedAt = Date()
        let precipitationChance = LiveWeatherProvider.nearTermPrecipitationChance(
            minuteForecastChance: weather.minuteForecast?.forecast.first?.precipitationChance,
            hourlyForecastChance: weather.hourlyForecast.forecast.first?.precipitationChance
        )
        let dailyForecast = LiveWeatherProvider.upcomingDailyForecasts(
            weather.dailyForecast.forecast.map(daySummary(from:)),
            now: fetchedAt
        )
        let hourlyForecast = hourlyForecastSlots(
            from: weather.hourlyForecast.forecast,
            referenceDate: fetchedAt
        )

        return WeatherSnapshot(
            currentTemperatureCelsius: weather.currentWeather.temperature.converted(to: .celsius).value,
            apparentTemperatureCelsius: weather.currentWeather.apparentTemperature.converted(to: .celsius).value,
            conditionDescription: weather.currentWeather.condition.description,
            symbolName: weather.currentWeather.symbolName,
            precipitationChance: precipitationChance,
            windSpeedKph: weather.currentWeather.wind.speed.converted(to: .kilometersPerHour).value,
            windDirectionDegrees: weather.currentWeather.wind.direction.converted(to: .degrees).value,
            uvIndex: weather.currentWeather.uvIndex.value,
            hourlyForecastSlots: hourlyForecast,
            dailyForecast: dailyForecast,
            fetchedAt: fetchedAt
        )
    }

    private static func daySummary(from forecast: DayWeather) -> WeatherDaySummary {
        WeatherDaySummary(
            date: forecast.date,
            symbolName: forecast.symbolName,
            summary: forecast.condition.description,
            temperatureMinCelsius: forecast.lowTemperature.converted(to: .celsius).value,
            temperatureMaxCelsius: forecast.highTemperature.converted(to: .celsius).value,
            precipitationChance: forecast.precipitationChance
        )
    }

    private static func hourlyForecastSlots(
        from forecast: [HourWeather],
        referenceDate: Date
    ) -> [WeatherHourlyForecastSlot] {
        let forecastDates = forecast.map(\.date)

        return LiveWeatherProvider.forecastTargetDates(from: referenceDate).compactMap { targetDate -> WeatherHourlyForecastSlot? in
            guard let index = LiveWeatherProvider.nearestIndex(in: forecastDates, to: targetDate) else {
                return nil
            }

            let hour = forecast[index]
            return WeatherHourlyForecastSlot(
                date: targetDate,
                symbolName: hour.symbolName,
                conditionDescription: hour.condition.description,
                temperatureCelsius: hour.temperature.converted(to: .celsius).value,
                precipitationChance: hour.precipitationChance,
                windSpeedKph: hour.wind.speed.converted(to: .kilometersPerHour).value,
                windDirectionDegrees: hour.wind.direction.converted(to: .degrees).value,
                uvIndex: hour.uvIndex.value
            )
        }
    }
}

private extension WeatherCondition {
    var description: String {
        switch self {
        case .blizzard: "Blizzard"
        case .blowingDust: "Blowing Dust"
        case .blowingSnow: "Blowing Snow"
        case .breezy: "Breezy"
        case .clear: "Clear"
        case .cloudy: "Cloudy"
        case .drizzle: "Drizzle"
        case .flurries: "Flurries"
        case .foggy: "Foggy"
        case .freezingDrizzle: "Freezing Drizzle"
        case .freezingRain: "Freezing Rain"
        case .frigid: "Frigid"
        case .hail: "Hail"
        case .haze: "Haze"
        case .heavyRain: "Heavy Rain"
        case .heavySnow: "Heavy Snow"
        case .hot: "Hot"
        case .hurricane: "Hurricane"
        case .isolatedThunderstorms: "Isolated Thunderstorms"
        case .mostlyClear: "Mostly Clear"
        case .mostlyCloudy: "Mostly Cloudy"
        case .partlyCloudy: "Partly Cloudy"
        case .rain: "Rain"
        case .scatteredThunderstorms: "Scattered Thunderstorms"
        case .sleet: "Sleet"
        case .smoky: "Smoky"
        case .snow: "Snow"
        case .strongStorms: "Strong Storms"
        case .sunFlurries: "Sun Flurries"
        case .sunShowers: "Sun Showers"
        case .thunderstorms: "Thunderstorms"
        case .tropicalStorm: "Tropical Storm"
        case .windy: "Windy"
        case .wintryMix: "Wintry Mix"
        @unknown default: "Unknown"
        }
    }
}
