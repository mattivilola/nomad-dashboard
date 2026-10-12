import Foundation

/// The one way the app writes a short duration, so every surface (dashboard, heads-ups, Siri answers and
/// widgets) reads the same.
public enum DurationText {
    /// "45 min", "1 h" or "3 h 11 min", rounded to the nearest minute (at least one minute).
    public static func hoursAndMinutes(_ interval: TimeInterval) -> String {
        let minutes = max(Int((interval / 60).rounded()), 1)
        let hours = minutes / 60
        let remainder = minutes % 60
        switch (hours, remainder) {
        case (0, _): return "\(remainder) min"
        case (_, 0): return "\(hours) h"
        default: return "\(hours) h \(remainder) min"
        }
    }
}
