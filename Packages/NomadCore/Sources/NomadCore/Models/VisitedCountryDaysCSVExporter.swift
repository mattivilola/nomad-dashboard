import Foundation

public enum VisitedCountryDaysCSVExporter {
    public static let formatVersion = "1"

    /// Produces a UTF-8 CSV with one effective country-day per row.
    public static func export(_ days: [VisitedCountryDay], year: Int? = nil) -> String {
        let selectedDays = days
            .filter { year == nil || $0.day.year == year }
            .sorted { $0.day < $1.day }

        var rows = [[
            "format_version", "day", "country", "country_code", "origin",
            "capture_source", "is_inferred", "is_manual"
        ]]
        rows.append(contentsOf: selectedDays.map { day in
            [
                formatVersion,
                day.day.key,
                day.country,
                day.countryCode ?? "",
                day.origin.rawValue,
                day.isManual ? VisitedCountryDayOrigin.manual.rawValue : day.source.rawValue,
                day.isInferred ? "true" : "false",
                day.isManual ? "true" : "false"
            ]
        })
        return rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    private static func escape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") || escaped.contains("\r") {
            return "\"\(escaped)\""
        }
        return escaped
    }
}
