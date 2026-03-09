import Foundation
import NomadCore

public enum NomadFormatters {
    public static func megabitsPerSecond(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.1f Mbps", value)
    }

    public static func latency(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.0f ms", value)
    }

    public static func percentage(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.0f%%", value)
    }

    public static func celsius(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.0f C", value)
    }

    public static func kilometersPerHour(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.0f km/h", value)
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
        let normalized = value.truncatingRemainder(dividingBy: 360)
        let degrees = normalized >= 0 ? normalized : normalized + 360
        let index = Int((degrees + 22.5) / 45.0) % 8
        return ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][index]
    }

    public static func watts(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.1f W", value)
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

    public static func fuelPricePerLiter(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "EUR %.3f/L", value)
    }

    public static func kilometers(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: value >= 10 ? "%.0f km" : "%.1f km", value)
    }

    public static func relativeDate(_ value: Date?) -> String {
        guard let value else { return "Waiting for first refresh"
        }

        return value.formatted(date: .omitted, time: .shortened)
    }
}
