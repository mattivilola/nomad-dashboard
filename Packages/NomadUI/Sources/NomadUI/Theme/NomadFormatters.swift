import Foundation
import NomadCore

/// A formatted number and its unit kept apart, so a layout can draw the unit small.
public struct FormattedMetric: Equatable, Sendable {
    public let number: String
    public let unit: String?

    public init(number: String, unit: String? = nil) {
        self.number = number
        self.unit = unit
    }

    /// "96.0 Mbps": the same text the plain string formatters return.
    public var text: String {
        unit.map { "\(number) \($0)" } ?? number
    }
}

public enum NomadFormatters {
    public static func megabitsPerSecond(_ value: Double?) -> String {
        megabitsPerSecondParts(value).text
    }

    public static func megabitsPerSecondParts(_ value: Double?) -> FormattedMetric {
        guard let value else { return FormattedMetric(number: "n/a") }
        return FormattedMetric(number: String(format: "%.1f", value), unit: "Mbps")
    }

    public static func latency(_ value: Double?) -> String {
        latencyParts(value).text
    }

    public static func latencyParts(_ value: Double?) -> FormattedMetric {
        guard let value else { return FormattedMetric(number: "n/a") }
        return FormattedMetric(number: String(format: "%.0f", value), unit: "ms")
    }

    public static func percentage(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.0f%%", value)
    }

    public static func celsius(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return TravelUnitFormatting.temperature(value)
    }

    public static func kilometersPerHour(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.0f km/h", value)
    }

    public static func metersPerSecond(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.1f m/s", value / 3.6)
    }

    public static func meters(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.1f m", value)
    }

    public static func seconds(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.0f s", value)
    }

    public static func compactClockTime(_ value: Date?) -> String {
        guard let value else { return "n/a" }
        return value.formatted(date: .omitted, time: .shortened)
    }

    public static func compassDirection(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return TravelUnitFormatting.compassDirection(value)
    }

    public static func watts(_ value: Double?) -> String {
        wattsParts(value).text
    }

    public static func wattsParts(_ value: Double?) -> FormattedMetric {
        guard let value else { return FormattedMetric(number: "n/a") }
        return FormattedMetric(number: String(format: "%.1f", value), unit: "W")
    }

    public static func minutes(_ value: Int?) -> String {
        guard let value, value >= 0 else { return "n/a" }
        let hours = value / 60
        let minutes = value % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        return "\(minutes)m"
    }

    public static func precipitation(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.0f%%", value * 100)
    }

    public static func kilometers(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return TravelUnitFormatting.kilometers(value)
    }

    public static func relativeDate(_ value: Date?) -> String {
        guard let value else { return "Waiting for first refresh"
        }

        return value.formatted(date: .omitted, time: .shortened)
    }
}
