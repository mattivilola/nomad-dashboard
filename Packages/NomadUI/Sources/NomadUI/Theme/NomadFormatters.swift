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

    public static func relativeDate(_ value: Date?) -> String {
        guard let value else { return "Waiting for first refresh"
        }

        return value.formatted(date: .omitted, time: .shortened)
    }
}
