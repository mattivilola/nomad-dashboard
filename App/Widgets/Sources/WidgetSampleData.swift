import Foundation
import NomadCore

extension WidgetSnapshot {
    /// What the widget gallery and the redacted placeholder show.
    static func sample(savedAt: Date) -> WidgetSnapshot {
        let sunset = Calendar.current.date(bySettingHour: 19, minute: 42, second: 0, of: savedAt) ?? savedAt
        let sunrise = Calendar.current.date(bySettingHour: 6, minute: 31, second: 0, of: savedAt) ?? savedAt
        return WidgetSnapshot(
            verdict: .init(title: "Ready", level: .ready),
            placeName: "Lisbon, Portugal",
            headsUp: [
                .init(title: "Wind up to 48 km/h", symbolName: "wind", severity: .caution),
                .init(title: "Public holiday tomorrow", symbolName: "calendar", severity: .info)
            ],
            emergency: .init(countryName: "Portugal", generalNumber: "112"),
            embassy: .init(name: "Embassy of Finland in Lisbon", hotline: "+00 123 456 789"),
            daylight: DaylightOutlook(
                sunrise: sunrise,
                sunset: sunset,
                nextSunrise: sunrise.addingTimeInterval(24 * 3_600),
                isPolarDay: false,
                isPolarNight: false,
                timeZoneIdentifier: TimeZone.current.identifier
            ),
            savedAt: savedAt
        )
    }
}
