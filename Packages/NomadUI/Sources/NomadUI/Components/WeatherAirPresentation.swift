import Foundation
import NomadCore

/// The UV index stat of the weather card: "UV 7 (high)" with the day's peak when it is still to come.
///
/// Bands follow the WHO UV index scale: 0-2 low, 3-5 moderate, 6-7 high, 8-10 very high, 11+ extreme.
/// https://www.who.int/news-room/questions-and-answers/item/radiation-the-ultraviolet-(uv)-index
struct WeatherUVPresentation: Equatable {
    /// "7 (high)".
    let value: String
    /// "peak 9 at 13:00", only when a higher reading follows today.
    let peak: String?
    /// Sand for high to very high, coral for extreme, neutral below high.
    let tone: SummaryTileTone

    var text: String {
        "UV \(value)"
    }

    /// Nil when the weather has no UV reading.
    init?(weather: WeatherSnapshot?, travelContext: TravelContextSnapshot, now: Date, calendar: Calendar, locale: Locale) {
        guard let uv = weather?.uvIndex, let weather else {
            return nil
        }

        value = "\(uv) (\(Self.bandName(uv)))"
        tone = Self.tone(uv)

        let reference = DaylightReference(travelContext: travelContext)
        let later = weather.hourlyForecastSlots
            .filter { $0.date >= now && calendar.isDate($0.date, inSameDayAs: now) }
            .compactMap { slot in slot.uvIndex.map { (date: slot.date, uv: $0) } }
        if let highest = later.max(by: { $0.uv < $1.uv }), highest.uv > uv {
            let time = reference?.clockTime(highest.date, locale: locale)
                ?? highest.date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: calendar.timeZone))
            peak = "peak \(highest.uv) at \(time)"
        } else {
            peak = nil
        }
    }

    static func bandName(_ uv: Int) -> String {
        switch uv {
        case ..<3: "low"
        case 3..<6: "moderate"
        case 6..<8: "high"
        case 8..<11: "very high"
        default: "extreme"
        }
    }

    static func tone(_ uv: Int) -> SummaryTileTone {
        switch uv {
        case ..<6: .neutral
        case 6..<11: .caution
        default: .attention
        }
    }
}

/// The air quality block of the weather card: "AQI 38 · Fair · mostly PM10" and a 12 hour outlook.
struct WeatherAirQualityPresentation: Equatable {
    /// One hour of the outlook as a bar.
    struct Bar: Identifiable, Equatable {
        let id: Date
        /// 0...1, the European AQI against 100 (the top of "very poor").
        let height: Double
        let tone: SummaryTileTone
        let help: String
    }

    /// "AQI 38 · Fair · mostly PM10".
    let headline: String
    /// Good, fair and moderate stay neutral; poor is sand; very poor and worse are coral.
    let tone: SummaryTileTone
    let bars: [Bar]
    /// "Next 12 h · peak 64 at 15:00", nil without an outlook.
    let outlookCaption: String?
    /// Concentrations for hover and VoiceOver.
    let help: String

    /// Nil unless air quality is on for the weather location and a reading exists.
    init?(
        airQuality: AirQualitySnapshot?,
        settings: AppSettings,
        travelContext: TravelContextSnapshot,
        now: Date,
        calendar: Calendar,
        locale: Locale
    ) {
        guard settings.isAirQualityActive, let airQuality else {
            return nil
        }

        let band = airQuality.band
        headline = [
            "AQI \(airQuality.europeanAQI)",
            band.title,
            airQuality.mainPollutant.map { "mostly \($0.displayName)" }
        ]
        .compactMap(\.self)
        .joined(separator: " · ")
        tone = Self.tone(band)

        let reference = DaylightReference(travelContext: travelContext)
        let time = { (date: Date) -> String in
            reference?.clockTime(date, locale: locale)
                ?? date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: calendar.timeZone))
        }

        let upcoming = airQuality.forecastSlots
            .filter { $0.date > now.addingTimeInterval(-3_600) }
            .sorted { $0.date < $1.date }
            .compactMap { slot in slot.europeanAQI.map { (date: slot.date, aqi: $0) } }
        bars = upcoming.map { entry in
            let entryBand = EuropeanAQIBand(index: entry.aqi)
            return Bar(
                id: entry.date,
                height: min(max(Double(entry.aqi) / Double(EuropeanAQIBand.extremelyPoorThreshold), 0.08), 1),
                tone: Self.tone(entryBand),
                help: "\(time(entry.date)) · AQI \(entry.aqi) · \(entryBand.title)"
            )
        }

        if let peak = upcoming.max(by: { $0.aqi < $1.aqi }) {
            outlookCaption = "Next \(upcoming.count) h · peak \(peak.aqi) at \(time(peak.date))"
        } else {
            outlookCaption = nil
        }

        let concentrations = [
            airQuality.pm2_5.map { "PM2.5 \(Int($0.rounded())) µg/m³" },
            airQuality.pm10.map { "PM10 \(Int($0.rounded())) µg/m³" },
            airQuality.ozone.map { "ozone \(Int($0.rounded())) µg/m³" },
            airQuality.nitrogenDioxide.map { "NO₂ \(Int($0.rounded())) µg/m³" }
        ]
        .compactMap(\.self)
        help = ([headline] + concentrations).joined(separator: " · ")
    }

    static func tone(_ band: EuropeanAQIBand) -> SummaryTileTone {
        switch band {
        case .good, .fair, .moderate: .neutral
        case .poor: .caution
        case .veryPoor, .extremelyPoor: .attention
        }
    }
}
