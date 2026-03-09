import CoreLocation
import Foundation
import WeatherKit

public actor LiveWeatherProvider: WeatherProvider {
    private let service: WeatherService
    private let ttl: TimeInterval
    private var cache: (key: String, snapshot: WeatherSnapshot)?

    public init(service: WeatherService = WeatherService(), ttl: TimeInterval = 1_800) {
        self.service = service
        self.ttl = ttl
    }

    public func weather(for coordinate: CLLocationCoordinate2D?) async throws -> WeatherSnapshot {
        guard let coordinate else {
            throw ProviderError.missingCoordinate
        }

        let cacheKey = Self.cacheKey(for: coordinate)

        if let cache, cache.key == cacheKey, abs(cache.snapshot.fetchedAt.timeIntervalSinceNow) < ttl {
            return cache.snapshot
        }

        let weather = try await service.weather(for: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        let tomorrow = weather.dailyForecast.forecast.dropFirst().first ?? weather.dailyForecast.forecast.first

        let snapshot = WeatherSnapshot(
            currentTemperatureCelsius: weather.currentWeather.temperature.converted(to: .celsius).value,
            apparentTemperatureCelsius: weather.currentWeather.apparentTemperature.converted(to: .celsius).value,
            conditionDescription: weather.currentWeather.condition.description,
            symbolName: weather.currentWeather.symbolName,
            precipitationChance: nil,
            windSpeedKph: weather.currentWeather.wind.speed.converted(to: .kilometersPerHour).value,
            tomorrow: tomorrow.map {
                WeatherDaySummary(
                    date: $0.date,
                    symbolName: $0.symbolName,
                    summary: $0.condition.description,
                    temperatureMinCelsius: $0.lowTemperature.converted(to: .celsius).value,
                    temperatureMaxCelsius: $0.highTemperature.converted(to: .celsius).value,
                    precipitationChance: $0.precipitationChance
                )
            },
            fetchedAt: Date()
        )

        cache = (cacheKey, snapshot)
        return snapshot
    }

    private static func cacheKey(for coordinate: CLLocationCoordinate2D) -> String {
        let latitude = String(format: "%.3f", coordinate.latitude)
        let longitude = String(format: "%.3f", coordinate.longitude)
        return "\(latitude),\(longitude)"
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
