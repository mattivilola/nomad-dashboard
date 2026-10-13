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

    /// A running clock for a countdown or elapsed time: "4:09" under one hour and "1:05:09" from one hour on.
    /// Floors to whole seconds and never goes negative.
    public static func countdown(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(max(interval, 0).rounded(.down))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return "\(hours):" + String(format: "%02d:%02d", minutes, seconds)
        }
        return "\(minutes):" + String(format: "%02d", seconds)
    }
}
