import Foundation

/// Open-Meteo returns local wall-clock times without an offset ("2026-10-12T14:00") plus the location's
/// time zone and UTC offset. Shared by the Open-Meteo marine and air quality providers.
enum OpenMeteoTimestamps {
    static func dates(from values: [String], timezoneIdentifier: String?, utcOffsetSeconds: Int?) throws -> [Date] {
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
